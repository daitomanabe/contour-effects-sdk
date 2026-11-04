<!-- SPDX-FileCopyrightText: 2026 Daito Manabe -->
<!-- SPDX-License-Identifier: BSD-3-Clause -->

# ContourEffects SDK

ContourEffects is a reusable Swift/Metal effect SDK extracted from the
ContourFlow VJ application. This repository is a clean, standalone source
workspace with its own Git history.

Current preview support:

- macOS 14 or later
- Apple Silicon (`arm64`)
- Swift Package Manager
- API contract `1.0`
- BSD-3-Clause for the first-party SDK scope

## Products

- `ContourEffectsCore`: effect descriptors, state, timing, analysis payloads,
  audio features, performance macros, and dependency metadata.
- `ContourEffectsMetal`: Metal effect instances, frame and texture contracts,
  effect graph composition, Final Color Grade / Film Finish, and 3D LUTs.

Neither product links GLIC, Syphon, Vision, Core ML, YOLO, or Depth Anything.
Those remain optional host capabilities.

## Add the package

For the public source preview, add the GitHub package:

```swift
dependencies: [
    .package(
        url: "https://github.com/daitomanabe/contour-effects-sdk.git",
        branch: "main"
    ),
],
targets: [
    .executableTarget(
        name: "MyVJHost",
        dependencies: [
            .product(
                name: "ContourEffectsCore",
                package: "contour-effects-sdk"
            ),
            .product(
                name: "ContourEffectsMetal",
                package: "contour-effects-sdk"
            ),
        ]
    ),
]
```

There is not yet a stable release tag. Pin an exact revision when a host needs
a reproducible preview dependency.

For local development, choose **File > Add Package Dependencies > Add Local**
in Xcode and select this repository. For another local Swift package:

```swift
dependencies: [
    .package(
        name: "ContourEffectsSDK",
        path: "/path/to/contour-effects-sdk"
    ),
],
targets: [
    .executableTarget(
        name: "MyVJHost",
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
```

## Verify

```bash
./scripts/verify_contour_effects_sdk.sh
```

The verifier builds the SDK in isolation, runs all unit tests, executes the
minimal Metal host and all eight examples, generates both DocC archives, and
checks that optional host dependencies did not enter the SDK target closure.

## Documentation

- [Installation and render contract](docs/CONTOUR_EFFECTS_SDK.md)
- [API and major classes](docs/CONTOUR_EFFECTS_API.md)
- [Optional host dependencies](docs/CONTOUR_EFFECTS_THIRD_PARTY.md)
- [Original ContourFlow effects and migration status](docs/CONTOUR_EFFECTS_ORIGINAL_CATALOG.md)
- [Eight executable examples](Examples/ContourEffectsExamples/README.md)
- [Minimal Metal host](Examples/MinimalContourEffectsHost/README.md)
- [Machine-readable manifest](SDK/contour-effects-sdk.json)

## License

Commercial use, modification, and redistribution are permitted under the
[BSD 3-Clause License](LICENSE). Redistributions must retain the complete
copyright and license notice. See [license scope](SDK/SCOPE.md) and
[attribution guidance](SDK/ATTRIBUTION.md).

Optional frameworks, model files, and other third-party components retain their
own licenses and are not included in this repository.
