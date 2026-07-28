// SPDX-FileCopyrightText: 2026 Daito Manabe
// SPDX-License-Identifier: BSD-3-Clause

import ContourEffectsCore
import Foundation
import Metal

public enum MetalEffectError: LocalizedError, Equatable {
    case notPrepared
    case pipelineCreationFailed(String)
    case textureCreationFailed
    case incompatibleSource
    case incompatibleDestination
    case incompatibleHostContext(String)
    case incompatibleAnalysisTexture(String)
    case resizeRequired(expectedWidth: Int, expectedHeight: Int)
    case missingInputs(EffectInputRequirements)
    case unknownParameter(String)
    case parameterRequiresAssetResolver(String)
    case invalidState(String)

    public var errorDescription: String? {
        switch self {
        case .notPrepared:
            return "The Metal effect has not been prepared."
        case let .pipelineCreationFailed(message):
            return "The Metal effect pipeline could not be created: \(message)"
        case .textureCreationFailed:
            return "The Metal effect could not allocate its working texture."
        case .incompatibleSource:
            return "The source texture is not compatible with this effect."
        case .incompatibleDestination:
            return "The destination texture is not compatible with this effect."
        case let .incompatibleHostContext(message):
            return "The Metal host context is incompatible: \(message)"
        case let .incompatibleAnalysisTexture(name):
            return "The \(name) analysis texture does not match the SDK texture ABI."
        case let .resizeRequired(expectedWidth, expectedHeight):
            return "Resize the effect graph to \(expectedWidth)x\(expectedHeight) before encoding."
        case let .missingInputs(requirements):
            return "The effect is missing required inputs (0x\(String(requirements.rawValue, radix: 16)))."
        case let .unknownParameter(identifier):
            return "The effect does not expose a parameter named \(identifier)."
        case let .parameterRequiresAssetResolver(identifier):
            return "Effect parameter \(identifier) must be set through an asset resolver."
        case let .invalidState(message):
            return "The effect state is invalid: \(message)"
        }
    }
}

/// Immutable services supplied by a host before frame encoding begins.
public enum MetalWorkingColorSpace: String, Sendable {
    /// Display-referred sRGB transfer function and Rec.709/sRGB primaries.
    case displaySRGB
    /// Linear-light sRGB with Rec.709/sRGB primaries.
    case linearSRGB
}

public enum MetalAlphaMode: String, Sendable {
    case straight
    case premultiplied
}

public struct MetalEffectHostContext {
    public let device: MTLDevice
    public let workingPixelFormat: MTLPixelFormat
    public let workingColorSpace: MetalWorkingColorSpace
    public let alphaMode: MetalAlphaMode

    public init(
        device: MTLDevice,
        workingPixelFormat: MTLPixelFormat = .rgba16Float,
        workingColorSpace: MetalWorkingColorSpace = .displaySRGB,
        alphaMode: MetalAlphaMode = .straight
    ) {
        self.device = device
        self.workingPixelFormat = workingPixelFormat
        self.workingColorSpace = workingColorSpace
        self.alphaMode = alphaMode
    }
}

/// GPU textures produced once by the host's analysis pipeline and shared
/// across all effects in one frame.
public struct MetalAnalysisTextures {
    /// `r8Unorm`; R is edge magnitude in 0...1.
    public var edge: MTLTexture?
    /// `rg16Float`; RG is source-normalized UV displacement per input frame.
    /// +X points right and +Y points down.
    public var opticalFlow: MTLTexture?
    /// `r8Unorm`; R is person membership in 0...1.
    public var personMask: MTLTexture?
    /// `r8Unorm`; R is silhouette-boundary coverage in 0...1.
    public var silhouetteContour: MTLTexture?
    /// `r8Unorm`; R is scene/foreground membership in 0...1.
    public var sceneMask: MTLTexture?
    /// `r16Float`; R is normalized relative depth, near=1 and far=0.
    /// Negative values are invalid.
    public var depth: MTLTexture?

    public init(
        edge: MTLTexture? = nil,
        opticalFlow: MTLTexture? = nil,
        personMask: MTLTexture? = nil,
        silhouetteContour: MTLTexture? = nil,
        sceneMask: MTLTexture? = nil,
        depth: MTLTexture? = nil
    ) {
        self.edge = edge
        self.opticalFlow = opticalFlow
        self.personMask = personMask
        self.silhouetteContour = silhouetteContour
        self.sceneMask = sceneMask
        self.depth = depth
    }

    func validate(
        device: MTLDevice,
        sourceWidth: Int,
        sourceHeight: Int
    ) throws {
        try validateTexture(
            edge,
            name: "edge",
            pixelFormat: .r8Unorm,
            device: device,
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight
        )
        try validateTexture(
            opticalFlow,
            name: "optical-flow",
            pixelFormat: .rg16Float,
            device: device,
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight
        )
        try validateTexture(
            personMask,
            name: "person-mask",
            pixelFormat: .r8Unorm,
            device: device,
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight
        )
        try validateTexture(
            silhouetteContour,
            name: "silhouette-contour",
            pixelFormat: .r8Unorm,
            device: device,
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight
        )
        try validateTexture(
            sceneMask,
            name: "scene-mask",
            pixelFormat: .r8Unorm,
            device: device,
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight
        )
        try validateTexture(
            depth,
            name: "depth",
            pixelFormat: .r16Float,
            device: device,
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight
        )
    }

    private func validateTexture(
        _ texture: MTLTexture?,
        name: String,
        pixelFormat: MTLPixelFormat,
        device: MTLDevice,
        sourceWidth: Int,
        sourceHeight: Int
    ) throws {
        guard let texture else { return }
        guard texture.device === device,
              texture.textureType == .type2D,
              texture.sampleCount == 1,
              texture.width > 0,
              texture.height > 0,
              texture.pixelFormat == pixelFormat,
              texture.usage.contains(.shaderRead),
              texture.width * sourceHeight == texture.height * sourceWidth
        else {
            throw MetalEffectError.incompatibleAnalysisTexture(name)
        }
    }
}

/// One render-queue-confined frame passed to every Metal effect.
///
/// `source` is the current composed image. `rawCamera` remains separate so
/// effects can restore the camera outside a mask without creating feedback.
public struct MetalEffectFrame {
    public var source: MTLTexture
    public var rawCamera: MTLTexture?
    public var analysisTextures: MetalAnalysisTextures
    public var featurePoints: [EffectPoint]
    public var handLandmarks: [EffectLandmarkSet]
    public var bodyLandmarks: [EffectLandmarkSet]
    public var detections: [EffectObjectDetection]
    public var audio: EffectAudioFeatures
    public var macros: EffectPerformanceMacros
    public var timing: EffectFrameTiming
    /// Explicit provider availability is independent of observation count.
    /// The default keeps the always-present audio and macro buses available
    /// even when their current values are zero.
    public var providedInputs: EffectInputRequirements

    public init(
        source: MTLTexture,
        rawCamera: MTLTexture? = nil,
        analysisTextures: MetalAnalysisTextures = .init(),
        featurePoints: [EffectPoint] = [],
        handLandmarks: [EffectLandmarkSet] = [],
        bodyLandmarks: [EffectLandmarkSet] = [],
        detections: [EffectObjectDetection] = [],
        audio: EffectAudioFeatures = .zero,
        macros: EffectPerformanceMacros = .zero,
        timing: EffectFrameTiming,
        providedInputs: EffectInputRequirements = [.audio, .performanceMacros]
    ) {
        self.source = source
        self.rawCamera = rawCamera
        self.analysisTextures = analysisTextures
        self.featurePoints = featurePoints
        self.handLandmarks = handLandmarks
        self.bodyLandmarks = bodyLandmarks
        self.detections = detections
        self.audio = audio
        self.macros = macros
        self.timing = timing
        self.providedInputs = providedInputs
    }

    public var availableInputs: EffectInputRequirements {
        var result: EffectInputRequirements = [.composedColor]
        // GPU resources become available only through their non-nil texture.
        // Explicit availability is reserved for buses and observation
        // providers, where an empty result remains a valid result.
        result.formUnion(providedInputs.intersection(Self.explicitProviderInputs))
        if rawCamera != nil { result.insert(.rawCameraColor) }
        if analysisTextures.edge != nil { result.insert(.edge) }
        if analysisTextures.opticalFlow != nil { result.insert(.opticalFlow) }
        if analysisTextures.personMask != nil { result.insert(.personMask) }
        if analysisTextures.silhouetteContour != nil {
            result.insert(.silhouetteContour)
        }
        if analysisTextures.sceneMask != nil { result.insert(.sceneMask) }
        if analysisTextures.depth != nil { result.insert(.depth) }
        if !featurePoints.isEmpty { result.insert(.featurePoints) }
        if !handLandmarks.isEmpty { result.insert(.handLandmarks) }
        if !bodyLandmarks.isEmpty { result.insert(.bodyLandmarks) }
        if !detections.isEmpty { result.insert(.objectDetections) }
        return result
    }

    public func validate(requiredInputs: EffectInputRequirements) throws {
        let missing = requiredInputs.subtracting(availableInputs)
        guard missing.isEmpty else {
            throw MetalEffectError.missingInputs(missing)
        }
    }

    func validateResources(
        context: MetalEffectHostContext,
        commandBuffer: MTLCommandBuffer
    ) throws {
        guard source.device === context.device,
              source.device === commandBuffer.commandQueue.device
        else {
            throw MetalEffectError.incompatibleSource
        }
        if let rawCamera {
            guard rawCamera.device === context.device,
                  rawCamera.textureType == .type2D,
                  rawCamera.sampleCount == 1,
                  rawCamera.width == source.width,
                  rawCamera.height == source.height,
                  rawCamera.pixelFormat == context.workingPixelFormat,
                  rawCamera.usage.contains(.shaderRead)
            else {
                throw MetalEffectError.incompatibleSource
            }
        }
        try analysisTextures.validate(
            device: context.device,
            sourceWidth: source.width,
            sourceHeight: source.height
        )
    }

    private static let explicitProviderInputs: EffectInputRequirements = [
        .featurePoints,
        .handLandmarks,
        .bodyLandmarks,
        .objectDetections,
        .audio,
        .performanceMacros,
    ]
}

/// Common synchronous contract for zero-readback Metal effects.
///
/// The host calls every method on one serial render queue. Effects encode work
/// into the supplied uncommitted command buffer and never wait for the GPU.
public protocol MetalEffectInstance: AnyObject {
    var descriptor: EffectDescriptor { get }

    func prepare(context: MetalEffectHostContext) throws
    func resize(width: Int, height: Int) throws
    func encode(
        frame: MetalEffectFrame,
        to destination: MTLTexture,
        commandBuffer: MTLCommandBuffer
    ) throws
    func reset()
    func snapshotState() -> EffectStateSnapshot
    func restoreState(_ state: EffectStateSnapshot) throws
    func parameterValue(identifier: String) -> EffectValue?
    func setParameterValue(_ value: EffectValue, identifier: String) throws
}

public extension MetalEffectInstance {
    func parameterValue(identifier: String) -> EffectValue? {
        snapshotState().values[identifier]
    }

    func setParameterValue(
        _ value: EffectValue,
        identifier: String
    ) throws {
        try setStateParameterValue(value, identifier: identifier)
    }

    func setStateParameterValue(
        _ value: EffectValue,
        identifier: String
    ) throws {
        guard let parameter = descriptor.parameters.first(
            where: { $0.identifier == identifier }
        ) else {
            throw MetalEffectError.unknownParameter(identifier)
        }
        try parameter.validate(value: value)
        if parameter.kind == .fileReference {
            throw MetalEffectError.parameterRequiresAssetResolver(identifier)
        }
        var state = snapshotState()
        state.values[identifier] = value
        try restoreState(state)
    }
}

extension MetalEffectFrame {
    func replacingSource(_ source: MTLTexture) -> Self {
        var copy = self
        copy.source = source
        return copy
    }
}

func validateTexturePair(
    source: MTLTexture,
    destination: MTLTexture,
    expectedPixelFormat: MTLPixelFormat,
    preparedDevice: MTLDevice,
    commandBuffer: MTLCommandBuffer
) throws {
    guard source.width > 0,
          source.height > 0,
          source.textureType == .type2D,
          source.sampleCount == 1,
          source.pixelFormat == expectedPixelFormat,
          source.usage.contains(.shaderRead),
          source.device === preparedDevice,
          source.device === destination.device,
          source.device === commandBuffer.commandQueue.device
    else {
        throw MetalEffectError.incompatibleSource
    }
    guard source !== destination,
          destination.width == source.width,
          destination.height == source.height,
          destination.textureType == .type2D,
          destination.sampleCount == 1,
          destination.pixelFormat == expectedPixelFormat,
          destination.device === preparedDevice,
          destination.usage.contains(.renderTarget)
    else {
        throw MetalEffectError.incompatibleDestination
    }
}
