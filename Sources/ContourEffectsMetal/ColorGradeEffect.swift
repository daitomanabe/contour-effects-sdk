// SPDX-FileCopyrightText: 2026 Daito Manabe
// SPDX-License-Identifier: BSD-3-Clause

import ContourEffectsCore
import Foundation
import Metal

public enum ColorGradeLook: UInt32, CaseIterable, Sendable {
    case neutral = 0
    case cinema
    case warmPrint
    case coolPrint
    case reversal
    case bleach
    case night
    case monochrome

    var displayName: String {
        switch self {
        case .neutral: return "Neutral"
        case .cinema: return "Cinema"
        case .warmPrint: return "Warm Print"
        case .coolPrint: return "Cool Print"
        case .reversal: return "Reversal"
        case .bleach: return "Bleach"
        case .night: return "Night"
        case .monochrome: return "Monochrome"
        }
    }
}

public enum LUTInputSpace: UInt32, CaseIterable, Sendable {
    case displayRGB = 0
    case linearSRGB = 1
}

public struct ColorGradeConfiguration: Equatable, Sendable {
    public var isEnabled = true
    public var look: ColorGradeLook = .neutral
    public var exposure: Float = 0
    public var brightness: Float = 0
    public var contrast: Float = 1
    public var saturation: Float = 1
    public var temperature: Float = 0
    public var tint: Float = 0
    public var gamma: Float = 1
    public var blackLift: Float = 0
    public var highlightRolloff: Float = 0
    public var filmCurve: Float = 0
    public var grain: Float = 0
    public var vignette: Float = 0
    public var lutIdentifier: String?
    public var lutMix: Float = 0
    public var lutInputSpace: LUTInputSpace = .displayRGB

    public init() {}

    public var isIdentity: Bool {
        !isEnabled || (
            abs(exposure) < 0.000_1
                && abs(brightness) < 0.000_1
                && abs(contrast - 1) < 0.000_1
                && abs(saturation - 1) < 0.000_1
                && abs(temperature) < 0.000_1
                && abs(tint) < 0.000_1
                && abs(gamma - 1) < 0.000_1
                && abs(blackLift) < 0.000_1
                && abs(highlightRolloff) < 0.000_1
                && abs(filmCurve) < 0.000_1
                && abs(grain) < 0.000_1
                && abs(vignette) < 0.000_1
                && (lutIdentifier == nil || abs(lutMix) < 0.000_1)
        )
    }

    public mutating func applyLook(_ newLook: ColorGradeLook) {
        let retainedEnabled = isEnabled
        let retainedLUTIdentifier = lutIdentifier
        let retainedLUTMix = lutMix
        let retainedInputSpace = lutInputSpace
        self = Self()
        isEnabled = retainedEnabled
        look = newLook
        lutIdentifier = retainedLUTIdentifier
        lutMix = retainedLUTMix
        lutInputSpace = retainedInputSpace

        switch newLook {
        case .neutral:
            break
        case .cinema:
            exposure = -0.08
            contrast = 1.12
            saturation = 0.94
            temperature = 0.08
            tint = 0.025
            blackLift = 0.025
            highlightRolloff = 0.38
            filmCurve = 0.48
            grain = 0.08
            vignette = 0.12
        case .warmPrint:
            exposure = 0.06
            contrast = 1.08
            saturation = 1.04
            temperature = 0.22
            tint = 0.035
            blackLift = 0.018
            highlightRolloff = 0.30
            filmCurve = 0.56
            grain = 0.10
            vignette = 0.10
        case .coolPrint:
            exposure = -0.04
            contrast = 1.10
            saturation = 0.96
            temperature = -0.20
            tint = 0.02
            blackLift = 0.025
            highlightRolloff = 0.34
            filmCurve = 0.52
            grain = 0.09
            vignette = 0.11
        case .reversal:
            exposure = 0.04
            contrast = 1.24
            saturation = 1.18
            temperature = 0.03
            gamma = 0.94
            highlightRolloff = 0.22
            filmCurve = 0.32
            grain = 0.045
            vignette = 0.08
        case .bleach:
            exposure = 0.10
            contrast = 1.30
            saturation = 0.42
            temperature = 0.06
            gamma = 0.96
            blackLift = 0.012
            highlightRolloff = 0.28
            filmCurve = 0.38
            grain = 0.14
            vignette = 0.14
        case .night:
            exposure = -0.42
            contrast = 1.16
            saturation = 0.72
            temperature = -0.28
            tint = -0.04
            gamma = 1.08
            blackLift = 0.045
            highlightRolloff = 0.46
            filmCurve = 0.40
            grain = 0.07
            vignette = 0.18
        case .monochrome:
            contrast = 1.18
            saturation = 0
            gamma = 0.96
            blackLift = 0.02
            highlightRolloff = 0.36
            filmCurve = 0.46
            grain = 0.12
            vignette = 0.15
        }
    }

    public mutating func sanitize() {
        exposure = exposure.clamped(to: -3 ... 3)
        brightness = brightness.clamped(to: -0.5 ... 0.5)
        contrast = contrast.clamped(to: 0.5 ... 2)
        saturation = saturation.clamped(to: 0 ... 2)
        temperature = temperature.clamped(to: -1 ... 1)
        tint = tint.clamped(to: -1 ... 1)
        gamma = gamma.clamped(to: 0.5 ... 2)
        blackLift = blackLift.clamped(to: 0 ... 0.5)
        highlightRolloff = highlightRolloff.clamped(to: 0 ... 1)
        filmCurve = filmCurve.clamped(to: 0 ... 1)
        grain = grain.clamped(to: 0 ... 1)
        vignette = vignette.clamped(to: 0 ... 1)
        lutMix = lutMix.clamped(to: 0 ... 1)
        if lutIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            lutIdentifier = nil
        }
    }
}

/// Display-referred finishing pass. RGB output is intentionally clamped to
/// 0...1 while alpha is preserved.
public final class ColorGradeEffect: MetalEffectInstance {
    public static let identifier: EffectIdentifier =
        "ws.daito.contour-effects.color.final-grade"

    public static let effectDescriptor = EffectDescriptor(
        id: identifier,
        displayName: "Final Color Grade / Film Finish",
        category: .color,
        requiredInputs: [.composedColor],
        parameters: [
            EffectParameterDescriptor(
                identifier: "enabled",
                displayName: "Enabled",
                kind: .boolean,
                defaultValue: .bool(true)
            ),
            EffectParameterDescriptor(
                identifier: "look",
                displayName: "Look",
                kind: .enumeration,
                defaultValue: .number(0),
                choices: ColorGradeLook.allCases.map {
                    .init(id: String($0.rawValue), displayName: $0.displayName)
                }
            ),
            .float("exposure", "Exposure", 0, -3 ... 3),
            .float("brightness", "Brightness", 0, -0.5 ... 0.5),
            .float("contrast", "Contrast", 1, 0.5 ... 2),
            .float("saturation", "Saturation", 1, 0 ... 2),
            .float("temperature", "Temperature", 0, -1 ... 1),
            .float("tint", "Tint", 0, -1 ... 1),
            .float("gamma", "Gamma", 1, 0.5 ... 2),
            .float("blackLift", "Black Lift", 0, 0 ... 0.5),
            .float("highlightRolloff", "Highlight Rolloff", 0, 0 ... 1),
            .float("filmCurve", "Film Curve", 0, 0 ... 1),
            .float("grain", "Grain", 0, 0 ... 1),
            .float("vignette", "Vignette", 0, 0 ... 1),
            EffectParameterDescriptor(
                identifier: "lut",
                displayName: "3D LUT",
                kind: .fileReference,
                defaultValue: .null
            ),
            .float("lutMix", "LUT Mix", 0, 0 ... 1),
            EffectParameterDescriptor(
                identifier: "lutInputSpace",
                displayName: "LUT Input Space",
                kind: .enumeration,
                defaultValue: .number(0),
                choices: [
                    .init(id: "0", displayName: "Display RGB"),
                    .init(id: "1", displayName: "Linear sRGB"),
                ]
            ),
        ]
    )
    public let descriptor = effectDescriptor

    public var configuration: ColorGradeConfiguration {
        didSet { configuration.sanitize() }
    }
    public private(set) var lut: MetalLUT3D?

    private var pipeline: MTLRenderPipelineState?
    private var workingPixelFormat: MTLPixelFormat?
    private var preparedDevice: MTLDevice?
    private var preservedStateValues: [String: EffectValue] = [:]
    private var preservedSchemaVersion = 1

    public init(configuration: ColorGradeConfiguration = .init()) {
        var configuration = configuration
        configuration.sanitize()
        self.configuration = configuration
    }

    public func setLUT(_ lut: MetalLUT3D?) {
        self.lut = lut
        configuration.lutIdentifier = lut?.identifier
        if lut == nil {
            configuration.lutMix = 0
        }
    }

    public func prepare(context: MetalEffectHostContext) throws {
        guard context.workingPixelFormat == .rgba16Float else {
            throw MetalEffectError.incompatibleHostContext(
                "Final Color Grade requires rgba16Float."
            )
        }
        guard context.workingColorSpace == .displaySRGB else {
            throw MetalEffectError.incompatibleHostContext(
                "Final Color Grade requires display-referred sRGB."
            )
        }
        guard context.alphaMode == .straight else {
            throw MetalEffectError.incompatibleHostContext(
                "Final Color Grade requires straight alpha."
            )
        }
        do {
            let library = try context.device.makeLibrary(
                source: Self.shaderSource,
                options: nil
            )
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.label = "ContourEffects Final Color Grade"
            descriptor.vertexFunction = library.makeFunction(name: "contourFullScreenVertex")
            descriptor.fragmentFunction = library.makeFunction(name: "contourColorGradeFragment")
            descriptor.colorAttachments[0].pixelFormat = context.workingPixelFormat
            pipeline = try context.device.makeRenderPipelineState(descriptor: descriptor)
            workingPixelFormat = context.workingPixelFormat
            preparedDevice = context.device
        } catch {
            throw MetalEffectError.pipelineCreationFailed(error.localizedDescription)
        }
    }

    public func resize(width: Int, height: Int) throws {
        guard width > 0, height > 0 else {
            throw MetalEffectError.incompatibleDestination
        }
    }

    public func encode(
        frame: MetalEffectFrame,
        to destination: MTLTexture,
        commandBuffer: MTLCommandBuffer
    ) throws {
        guard let pipeline, let workingPixelFormat, let preparedDevice else {
            throw MetalEffectError.notPrepared
        }
        try frame.validate(requiredInputs: descriptor.requiredInputs)
        try validateTexturePair(
            source: frame.source,
            destination: destination,
            expectedPixelFormat: workingPixelFormat,
            preparedDevice: preparedDevice,
            commandBuffer: commandBuffer
        )
        if let lut {
            guard lut.texture.device === destination.device else {
                throw MetalEffectError.incompatibleSource
            }
        }
        guard let encoder = commandBuffer.makeRenderCommandEncoder(
            descriptor: Self.renderPassDescriptor(texture: destination)
        ) else {
            throw MetalEffectError.pipelineCreationFailed("render encoder unavailable")
        }

        let lutMatchesState = configuration.lutIdentifier != nil
            && configuration.lutIdentifier == lut?.identifier
        var uniforms = ColorGradeUniforms(
            controls0: SIMD4(
                configuration.exposure,
                configuration.brightness,
                configuration.contrast,
                configuration.saturation
            ),
            controls1: SIMD4(
                configuration.temperature,
                configuration.tint,
                configuration.gamma,
                configuration.blackLift
            ),
            controls2: SIMD4(
                configuration.highlightRolloff,
                configuration.filmCurve,
                configuration.grain,
                configuration.vignette
            ),
            viewport: SIMD4(
                Float(frame.timing.renderPresentationSeconds ?? 0),
                Float(destination.width),
                Float(destination.height),
                configuration.isEnabled ? 1 : 0
            ),
            lutControls: SIMD4(
                configuration.lutMix,
                Float(lut?.texture.width ?? 0),
                Float(configuration.lutInputSpace.rawValue),
                lutMatchesState ? 1 : 0
            ),
            lutDomainMinimum: SIMD4(lut?.domainMinimum ?? .zero, 0),
            lutDomainMaximum: SIMD4(
                lut?.domainMaximum ?? SIMD3<Float>(repeating: 1),
                0
            )
        )

        encoder.label = "ContourEffects Final Color Grade / Film Finish"
        encoder.setCullMode(.none)
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(frame.source, index: 0)
        encoder.setFragmentTexture(lut?.texture, index: 1)
        encoder.setFragmentBytes(
            &uniforms,
            length: MemoryLayout<ColorGradeUniforms>.stride,
            index: 0
        )
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        encoder.endEncoding()
    }

    public func reset() {}

    public func setParameterValue(
        _ value: EffectValue,
        identifier: String
    ) throws {
        guard identifier == "look" else {
            try setStateParameterValue(value, identifier: identifier)
            return
        }
        guard let parameter = descriptor.parameters.first(
            where: { $0.identifier == identifier }
        ) else {
            throw MetalEffectError.unknownParameter(identifier)
        }
        try parameter.validate(value: value)
        guard let rawValue = value.uint32Value,
              let look = ColorGradeLook(rawValue: rawValue)
        else {
            throw MetalEffectError.invalidState(
                "invalid Final Color Grade look"
            )
        }
        configuration.applyLook(look)
    }

    public func snapshotState() -> EffectStateSnapshot {
        var values = preservedStateValues
        values.merge(configuration.effectValues) { _, current in current }
        return EffectStateSnapshot(
            effectIdentifier: Self.identifier,
            schemaVersion: preservedSchemaVersion,
            values: values
        )
    }

    public func restoreState(_ state: EffectStateSnapshot) throws {
        guard state.effectIdentifier == Self.identifier else {
            throw MetalEffectError.invalidState(
                "expected \(Self.identifier.rawValue), received \(state.effectIdentifier.rawValue)"
            )
        }
        preservedSchemaVersion = state.schemaVersion
        preservedStateValues = state.values
        configuration.apply(effectValues: state.values)
    }

    private static func renderPassDescriptor(
        texture: MTLTexture
    ) -> MTLRenderPassDescriptor {
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = texture
        descriptor.colorAttachments[0].loadAction = .dontCare
        descriptor.colorAttachments[0].storeAction = .store
        return descriptor
    }
}

private struct ColorGradeUniforms {
    var controls0: SIMD4<Float>
    var controls1: SIMD4<Float>
    var controls2: SIMD4<Float>
    var viewport: SIMD4<Float>
    var lutControls: SIMD4<Float>
    var lutDomainMinimum: SIMD4<Float>
    var lutDomainMaximum: SIMD4<Float>
}

private extension EffectParameterDescriptor {
    static func float(
        _ identifier: String,
        _ displayName: String,
        _ defaultValue: Double,
        _ range: ClosedRange<Double>
    ) -> Self {
        Self(
            identifier: identifier,
            displayName: displayName,
            kind: .float,
            defaultValue: .number(defaultValue),
            minimum: range.lowerBound,
            maximum: range.upperBound
        )
    }
}

private extension ColorGradeConfiguration {
    var effectValues: [String: EffectValue] {
        [
            "enabled": .bool(isEnabled),
            "look": .number(Double(look.rawValue)),
            "exposure": .number(Double(exposure)),
            "brightness": .number(Double(brightness)),
            "contrast": .number(Double(contrast)),
            "saturation": .number(Double(saturation)),
            "temperature": .number(Double(temperature)),
            "tint": .number(Double(tint)),
            "gamma": .number(Double(gamma)),
            "blackLift": .number(Double(blackLift)),
            "highlightRolloff": .number(Double(highlightRolloff)),
            "filmCurve": .number(Double(filmCurve)),
            "grain": .number(Double(grain)),
            "vignette": .number(Double(vignette)),
            "lut": lutIdentifier.map(EffectValue.string) ?? .null,
            "lutMix": .number(Double(lutMix)),
            "lutInputSpace": .number(Double(lutInputSpace.rawValue)),
        ]
    }

    mutating func apply(effectValues: [String: EffectValue]) {
        if let value = effectValues["enabled"]?.boolValue { isEnabled = value }
        if let value = effectValues["look"]?.uint32Value,
           let parsed = ColorGradeLook(rawValue: value)
        {
            look = parsed
        }
        assign(effectValues, "exposure", to: &exposure)
        assign(effectValues, "brightness", to: &brightness)
        assign(effectValues, "contrast", to: &contrast)
        assign(effectValues, "saturation", to: &saturation)
        assign(effectValues, "temperature", to: &temperature)
        assign(effectValues, "tint", to: &tint)
        assign(effectValues, "gamma", to: &gamma)
        assign(effectValues, "blackLift", to: &blackLift)
        assign(effectValues, "highlightRolloff", to: &highlightRolloff)
        assign(effectValues, "filmCurve", to: &filmCurve)
        assign(effectValues, "grain", to: &grain)
        assign(effectValues, "vignette", to: &vignette)
        if let value = effectValues["lut"] {
            lutIdentifier = value.stringValue
        }
        assign(effectValues, "lutMix", to: &lutMix)
        if let value = effectValues["lutInputSpace"]?.uint32Value,
           let parsed = LUTInputSpace(rawValue: value)
        {
            lutInputSpace = parsed
        }
        sanitize()
    }

    private func assign(
        _ values: [String: EffectValue],
        _ key: String,
        to target: inout Float
    ) {
        guard let value = values[key]?.numberValue, value.isFinite else { return }
        target = Float(value)
    }
}

private extension EffectValue {
    var uint32Value: UInt32? {
        guard let value = numberValue,
              value.isFinite,
              value >= 0,
              value <= Double(UInt32.max),
              value.rounded(.towardZero) == value
        else {
            return nil
        }
        return UInt32(value)
    }
}

private extension Float {
    func clamped(to range: ClosedRange<Float>) -> Float {
        guard isFinite else { return range.lowerBound }
        return min(max(self, range.lowerBound), range.upperBound)
    }
}
