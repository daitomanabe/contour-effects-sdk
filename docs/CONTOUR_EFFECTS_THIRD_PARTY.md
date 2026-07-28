<!-- SPDX-FileCopyrightText: 2026 Daito Manabe -->
<!-- SPDX-License-Identifier: BSD-3-Clause -->

# ContourEffects Third-Party Integrations

## Dependency boundary

`ContourEffectsCore` and `ContourEffectsMetal` link only Apple Foundation and
Metal. The integrations below are optional host responsibilities: they are not
linked, downloaded, or bundled by this package.

| Capability | Typical use | Host install type | Required by SDK products |
| --- | --- | --- | ---: |
| Apple Vision | person masks, contours, hands, body pose, scene analysis | macOS system framework | No |
| Apple Core ML | on-device model inference | macOS system framework | No |
| YOLOv3 Tiny Int8 LUT | object detection and host-side tracking | compiled model resource | No |
| Depth Anything V2 Small | monocular relative depth | compiled model resource | No |
| GLIC Metal | Original, Spatial, and Codec glitch lanes | XCFramework and resource bundle | No |
| Official Syphon.framework | final Metal texture sharing | embedded framework | No |

Install only the integrations a host uses. The host owns their lifecycle,
permissions, signing, redistribution terms, and third-party notices. The
first-party BSD-3-Clause grant in [`LICENSE`](../LICENSE) does not
relicense any optional framework, model, or asset.

Pinned upstream locations, revisions, and hashes are recorded in
[`SDK/contour-effects-sdk.json`](../SDK/contour-effects-sdk.json).

## Apple Vision

There is no package payload to copy into this repository. Link
`Vision.framework` in the host:

```swift
.linkedFramework("Vision")
```

The host owns camera permission text, capture lifetime, request scheduling, and
conversion from Vision observations to `EffectLandmarkSet`,
`EffectObjectDetection`, masks, and contours. Run analysis once per input frame
and share the result across effects instead of repeating requests per effect.

## Apple Core ML

There is no package payload to copy into this repository. Link
`CoreML.framework` in the host:

```swift
.linkedFramework("CoreML")
```

Core ML supplies the inference runtime. YOLO and Depth Anything are separate
model resources that a host must obtain, verify, compile, and package.

## YOLOv3 Tiny

The SDK manifest records Apple's model URL and expected source SHA-256:

```text
https://ml-assets.apple.com/coreml/models/Image/ObjectDetection/YOLOv3Tiny/YOLOv3TinyInt8LUT.mlmodel
cde8af2528d6eca1d1580fdd0f0147cb6613d40ba962656b5f683c65f571870e
```

Download the model to a host-owned directory, verify that hash, and compile it
for the host app:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
mkdir -p HostModels build/CompiledModels
curl -L \
  https://ml-assets.apple.com/coreml/models/Image/ObjectDetection/YOLOv3Tiny/YOLOv3TinyInt8LUT.mlmodel \
  -o HostModels/YOLOv3TinyInt8LUT.mlmodel
shasum -a 256 HostModels/YOLOv3TinyInt8LUT.mlmodel
xcrun coremlcompiler compile \
  HostModels/YOLOv3TinyInt8LUT.mlmodel \
  build/CompiledModels \
  --platform macOS \
  --deployment-target 14.0
```

Copy `YOLOv3TinyInt8LUT.mlmodelc` into the host app resources. Review the model
publisher's current terms and include the required YOLO/Darknet notices when
redistributing it; this repository does not bundle that model or its notice.

## Depth Anything V2 Small

Obtain the Float16 Core ML package from Apple's pinned upstream repository:

```text
https://huggingface.co/apple/coreml-depth-anything-v2-small
revision: cfef6f6f2a70783dedc0bfae40cecbc2052285d3
```

The expected payload hashes are in
[`SDK/contour-effects-sdk.json`](../SDK/contour-effects-sdk.json). After
verifying the downloaded package, compile it from its host-owned path:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
mkdir -p build/CompiledModels
xcrun coremlcompiler compile \
  /path/to/DepthAnythingV2SmallF16.mlpackage \
  build/CompiledModels \
  --platform macOS \
  --deployment-target 14.0
```

Copy `DepthAnythingV2SmallF16.mlmodelc` into the host app resources. The Small
model is recorded as Apache-2.0 in the SDK manifest. Confirm the selected
upstream payload and include its license and notices in the host distribution.
Do not silently substitute differently licensed model variants.

Depth Anything returns **relative depth**, not meters. Before constructing a
`MetalEffectFrame`, normalize finite native values with the per-snapshot
P05/P95 rule in [`CONTOUR_EFFECTS_SDK.md`](CONTOUR_EFFECTS_SDK.md), preserve
near=1/far=0, write invalid pixels as negative values, and resample the complete
`518x392` result into a source-aligned `r16Float` texture. Effects must not
consume a padded or native-aspect model texture directly.

## GLIC Metal

GLIC is an optional, separately distributed SDK. Build a matched binary and
resource bundle from the revision recorded by ContourEffects:

```bash
git clone https://github.com/daitomanabe/glic-metal.git
cd glic-metal
git checkout 87f236bbdffb6538294ed7d049f6834f948dadbe
scripts/build_macos_sdk.sh build/GlicMetalSDK
```

Add both generated artifacts to the host:

- `GlicMetal.xcframework`
- `GlicMetalResources.bundle`

Never mix a binary from one GLIC revision with a resource bundle from another.
The host decides which GLIC lanes and preset bank to expose. Copy GLIC's
`LICENSE` and `THIRD_PARTY_NOTICES.md` into the host distribution.

## Official Syphon.framework

Use the regular official Syphon framework from
[Syphon-Framework](https://github.com/Syphon/Syphon-Framework), not Syphon26:

```bash
git clone https://github.com/Syphon/Syphon-Framework.git
cd Syphon-Framework
git checkout 71351d4b484cd2d1917867f7846a5cdca724552d
xcodebuild \
  -project Syphon.xcodeproj \
  -scheme Syphon \
  -configuration Release \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO
```

Then:

1. copy `Syphon.framework` into `MyHost.app/Contents/Frameworks`;
2. add `@executable_path/../Frameworks` to the host runpath;
3. sign `Syphon.framework`;
4. sign the host app;
5. include
   [`ThirdPartyNotices/Syphon-License.txt`](../ThirdPartyNotices/Syphon-License.txt).

Publish the final Metal texture on the same command buffer after the effect
graph, without CPU readback. Syphon is output transport, not an effect
dependency.

The command above was verified with Xcode 26.6 (`17F113`) against upstream
revision `71351d4b484cd2d1917867f7846a5cdca724552d`. With code signing disabled,
the clean build produced:

| Property | Verified value |
| --- | --- |
| Bundle ID | `info.v002.Syphon` |
| Version | `5` |
| Architectures | `arm64`, `x86_64` |
| Binary SHA-256 | `95806399bc0e45f374f3fbda39e060afa06062371bde31ab8859d8d96b99a06d` |

Rebuild the pinned source with the release toolchain, or select that verified
clean-build lane, and record the exact artifact hash shipped by the host.

## Notices

The notice index is
[`ThirdPartyNotices/README.md`](../ThirdPartyNotices/README.md). This repository
bundles only the Syphon license text as a convenience for hosts that choose
Syphon. A host that adds Vision, Core ML models, GLIC, Syphon, or any other
optional integration remains responsible for the agreements and notices that
apply to the exact payload it ships.
