// swift-tools-version: 5.9
// SPDX-FileCopyrightText: 2026 Daito Manabe
// SPDX-License-Identifier: BSD-3-Clause

import PackageDescription

let package = Package(
    name: "ContourEffectsExamples",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(
            name: "ContourEffectsCatalogStateExample",
            targets: ["ContourEffectsCatalogStateExample"]
        ),
        .executable(
            name: "ContourEffectsLUTRenderExample",
            targets: ["ContourEffectsLUTRenderExample"]
        ),
        .executable(
            name: "ContourEffectsAnalysisMaskExample",
            targets: ["ContourEffectsAnalysisMaskExample"]
        ),
        .executable(
            name: "ContourEffectsAudioMacroReactiveExample",
            targets: ["ContourEffectsAudioMacroReactiveExample"]
        ),
        .executable(
            name: "ContourEffectsGraphLifecycleExample",
            targets: ["ContourEffectsGraphLifecycleExample"]
        ),
        .executable(
            name: "ContourEffectsEdgeFlowWarpExample",
            targets: ["ContourEffectsEdgeFlowWarpExample"]
        ),
        .executable(
            name: "ContourEffectsColorLookGalleryExample",
            targets: ["ContourEffectsColorLookGalleryExample"]
        ),
        .executable(
            name: "ContourEffectsLiveInputsExample",
            targets: ["ContourEffectsLiveInputsExample"]
        ),
    ],
    dependencies: [
        .package(name: "ContourEffectsSDK", path: "../.."),
    ],
    targets: [
        .target(
            name: "ExampleSupport",
            linkerSettings: [
                .linkedFramework("Metal"),
            ]
        ),
        .executableTarget(
            name: "ContourEffectsCatalogStateExample",
            dependencies: [
                "ExampleSupport",
                .product(
                    name: "ContourEffectsCore",
                    package: "ContourEffectsSDK"
                ),
                .product(
                    name: "ContourEffectsMetal",
                    package: "ContourEffectsSDK"
                ),
            ]
        ),
        .executableTarget(
            name: "ContourEffectsLUTRenderExample",
            dependencies: [
                "ExampleSupport",
                .product(
                    name: "ContourEffectsCore",
                    package: "ContourEffectsSDK"
                ),
                .product(
                    name: "ContourEffectsMetal",
                    package: "ContourEffectsSDK"
                ),
            ],
            linkerSettings: [
                .linkedFramework("Metal"),
            ]
        ),
        .executableTarget(
            name: "ContourEffectsAnalysisMaskExample",
            dependencies: [
                "ExampleSupport",
                .product(
                    name: "ContourEffectsCore",
                    package: "ContourEffectsSDK"
                ),
                .product(
                    name: "ContourEffectsMetal",
                    package: "ContourEffectsSDK"
                ),
            ],
            linkerSettings: [
                .linkedFramework("Metal"),
            ]
        ),
        .executableTarget(
            name: "ContourEffectsAudioMacroReactiveExample",
            dependencies: [
                "ExampleSupport",
                .product(
                    name: "ContourEffectsCore",
                    package: "ContourEffectsSDK"
                ),
                .product(
                    name: "ContourEffectsMetal",
                    package: "ContourEffectsSDK"
                ),
            ],
            linkerSettings: [
                .linkedFramework("Metal"),
            ]
        ),
        .executableTarget(
            name: "ContourEffectsGraphLifecycleExample",
            dependencies: [
                "ExampleSupport",
                .product(
                    name: "ContourEffectsCore",
                    package: "ContourEffectsSDK"
                ),
                .product(
                    name: "ContourEffectsMetal",
                    package: "ContourEffectsSDK"
                ),
            ],
            linkerSettings: [
                .linkedFramework("Metal"),
            ]
        ),
        .executableTarget(
            name: "ContourEffectsEdgeFlowWarpExample",
            dependencies: [
                "ExampleSupport",
                .product(
                    name: "ContourEffectsCore",
                    package: "ContourEffectsSDK"
                ),
                .product(
                    name: "ContourEffectsMetal",
                    package: "ContourEffectsSDK"
                ),
            ],
            linkerSettings: [
                .linkedFramework("Metal"),
            ]
        ),
        .executableTarget(
            name: "ContourEffectsColorLookGalleryExample",
            dependencies: [
                "ExampleSupport",
                .product(
                    name: "ContourEffectsCore",
                    package: "ContourEffectsSDK"
                ),
                .product(
                    name: "ContourEffectsMetal",
                    package: "ContourEffectsSDK"
                ),
            ],
            linkerSettings: [
                .linkedFramework("Metal"),
            ]
        ),
        .executableTarget(
            name: "ContourEffectsLiveInputsExample",
            dependencies: [
                "ExampleSupport",
                .product(
                    name: "ContourEffectsCore",
                    package: "ContourEffectsSDK"
                ),
                .product(
                    name: "ContourEffectsMetal",
                    package: "ContourEffectsSDK"
                ),
            ],
            linkerSettings: [
                .linkedFramework("Metal"),
            ]
        ),
    ],
    swiftLanguageVersions: [.v5]
)
