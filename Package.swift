// swift-tools-version: 5.9
// SPDX-FileCopyrightText: 2026 Daito Manabe
// SPDX-License-Identifier: BSD-3-Clause

import PackageDescription

let package = Package(
    name: "ContourEffectsSDK",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "ContourEffectsCore",
            targets: ["ContourEffectsCore"]
        ),
        .library(
            name: "ContourEffectsMetal",
            targets: ["ContourEffectsMetal"]
        ),
    ],
    targets: [
        .target(
            name: "ContourEffectsCore"
        ),
        .target(
            name: "ContourEffectsMetal",
            dependencies: ["ContourEffectsCore"],
            linkerSettings: [
                .linkedFramework("Metal"),
            ]
        ),
        .testTarget(
            name: "ContourEffectsCoreTests",
            dependencies: ["ContourEffectsCore"]
        ),
        .testTarget(
            name: "ContourEffectsMetalTests",
            dependencies: [
                "ContourEffectsCore",
                "ContourEffectsMetal",
            ],
            linkerSettings: [
                .linkedFramework("Metal"),
            ]
        ),
    ],
    swiftLanguageVersions: [.v5]
)
