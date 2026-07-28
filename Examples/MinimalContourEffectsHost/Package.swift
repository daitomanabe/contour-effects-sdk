// swift-tools-version: 5.9
// SPDX-FileCopyrightText: 2026 Daito Manabe
// SPDX-License-Identifier: BSD-3-Clause

import PackageDescription

let package = Package(
    name: "MinimalContourEffectsHost",
    platforms: [
        .macOS(.v14),
    ],
    dependencies: [
        // A stable local alias keeps this example independent of the checkout
        // directory name. Replace the path with the SDK checkout location.
        .package(name: "ContourEffectsSDK", path: "../.."),
    ],
    targets: [
        .executableTarget(
            name: "MinimalContourEffectsHost",
            dependencies: [
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
    ]
)
