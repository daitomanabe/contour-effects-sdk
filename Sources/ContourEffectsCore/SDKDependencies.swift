// SPDX-FileCopyrightText: 2026 Daito Manabe
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

public enum ContourEffectsDependencyID: String, Codable, CaseIterable, Sendable {
    case appleVision
    case appleCoreML
    case yoloV3TinyCoreML
    case depthAnythingV2SmallCoreML
    case glicMetal
    case syphon
}

public enum SDKDependencyDistribution: String, Codable, Sendable {
    case systemFramework
    case modelResource
    case xcframeworkAndResources
    case framework
}

/// Machine-readable third-party capability metadata.
///
/// None of these dependencies is linked by `ContourEffectsCore`. Hosts add
/// only the adapters and resources needed by the effects they select.
public struct SDKDependencyDescriptor: Codable, Equatable, Sendable, Identifiable {
    public var id: ContourEffectsDependencyID
    public var displayName: String
    public var role: String
    public var distribution: SDKDependencyDistribution
    public var isOptional: Bool
    public var license: String
    public var homepage: URL
    public var installSummary: String

    public init(
        id: ContourEffectsDependencyID,
        displayName: String,
        role: String,
        distribution: SDKDependencyDistribution,
        isOptional: Bool = true,
        license: String,
        homepage: URL,
        installSummary: String
    ) {
        self.id = id
        self.displayName = displayName
        self.role = role
        self.distribution = distribution
        self.isOptional = isOptional
        self.license = license
        self.homepage = homepage
        self.installSummary = installSummary
    }
}

public enum ContourEffectsDependencies {
    public static let all: [SDKDependencyDescriptor] = [
        SDKDependencyDescriptor(
            id: .appleVision,
            displayName: "Apple Vision",
            role: "Person masks, contours, hands, body pose, scene analysis",
            distribution: .systemFramework,
            license: "Apple SDK Agreement",
            homepage: URL(string: "https://developer.apple.com/documentation/vision")!,
            installSummary: "No download. Link Vision.framework in the host target."
        ),
        SDKDependencyDescriptor(
            id: .appleCoreML,
            displayName: "Apple Core ML",
            role: "On-device YOLO and monocular-depth inference",
            distribution: .systemFramework,
            license: "Apple SDK Agreement",
            homepage: URL(string: "https://developer.apple.com/documentation/coreml")!,
            installSummary: "No download. Link CoreML.framework and bundle a compiled model."
        ),
        SDKDependencyDescriptor(
            id: .yoloV3TinyCoreML,
            displayName: "YOLOv3 Tiny Int8 LUT",
            role: "Fast object detection and host-side tracking",
            distribution: .modelResource,
            license: "YOLO License v2; Darknet public domain",
            homepage: URL(string: "https://developer.apple.com/machine-learning/models/")!,
            installSummary: "Compile YOLOv3TinyInt8LUT.mlmodel with coremlcompiler and copy the .mlmodelc into the host bundle."
        ),
        SDKDependencyDescriptor(
            id: .depthAnythingV2SmallCoreML,
            displayName: "Depth Anything V2 Small Float16",
            role: "Monocular relative-depth estimation",
            distribution: .modelResource,
            license: "Apache-2.0 for the Small model",
            homepage: URL(string: "https://github.com/DepthAnything/Depth-Anything-V2")!,
            installSummary: "Compile DepthAnythingV2SmallF16.mlpackage with coremlcompiler and copy the .mlmodelc into the host bundle."
        ),
        SDKDependencyDescriptor(
            id: .glicMetal,
            displayName: "GLIC Metal",
            role: "Optional realtime Original, Spatial, and Codec glitch lanes",
            distribution: .xcframeworkAndResources,
            license: "MIT",
            homepage: URL(string: "https://github.com/daitomanabe/glic-metal")!,
            installSummary: "Embed matching GlicMetal.xcframework and GlicMetalResources.bundle artifacts from one SDK revision."
        ),
        SDKDependencyDescriptor(
            id: .syphon,
            displayName: "Official Syphon.framework",
            role: "Optional final-texture publishing between macOS applications",
            distribution: .framework,
            license: "BSD-3-Clause",
            homepage: URL(string: "https://github.com/Syphon/Syphon-Framework")!,
            installSummary: "Build or obtain the official Syphon.framework, embed it in the host app, then sign the framework and app."
        ),
    ]

    public static func descriptor(
        for id: ContourEffectsDependencyID
    ) -> SDKDependencyDescriptor {
        // The registry and ID enum are maintained together. Keeping this
        // fail-fast prevents a silently undocumented binary dependency.
        guard let descriptor = all.first(where: { $0.id == id }) else {
            preconditionFailure("Missing dependency descriptor for \(id.rawValue)")
        }
        return descriptor
    }
}
