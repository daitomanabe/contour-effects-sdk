<!-- SPDX-FileCopyrightText: 2026 Daito Manabe -->
<!-- SPDX-License-Identifier: BSD-3-Clause -->

# ContourEffects SDK

## Status

`ContourEffects` is the reusable Swift/Metal SDK extracted from ContourFlow.
The current source preview supports macOS 14+ on Apple Silicon (`arm64`); it is
not an Intel build or a tagged public binary release:

- API contract: `1.0`
- Swift Package products: `ContourEffectsCore`, `ContourEffectsMetal`
- first migrated effect:
  `ws.daito.contour-effects.color.final-grade`
- first-party license: `BSD-3-Clause`
- copyright: `Copyright (c) 2026 Daito Manabe.`

Commercial use, modification, and redistribution are permitted. Source and
binary redistribution must retain the required copyright and complete license
notice. Read [`LICENSE`](../LICENSE), the closed file whitelist in
[`SDK/SCOPE.md`](../SDK/SCOPE.md), and the copy-ready redistribution guide in
[`SDK/ATTRIBUTION.md`](../SDK/ATTRIBUTION.md).

Optional frameworks, models, user media, LUT payloads, logos, and other
third-party material are not bundled by this repository and retain their own
licenses.

## Documentation map

- Start here: this installation and integration guide.
- Public symbols and major-class guides:
  [CONTOUR_EFFECTS_API.md](CONTOUR_EFFECTS_API.md).
- Executable recipes:
  [`Examples/ContourEffectsExamples`](../Examples/ContourEffectsExamples).
- Optional Vision, Core ML, model, GLIC, and Syphon adapters:
  [CONTOUR_EFFECTS_THIRD_PARTY.md](CONTOUR_EFFECTS_THIRD_PARTY.md).
- License boundary and redistribution:
  [`SDK/SCOPE.md`](../SDK/SCOPE.md) and
  [`SDK/ATTRIBUTION.md`](../SDK/ATTRIBUTION.md).

## Install in three steps

### 1. Add the local package

In Xcode use **File > Add Package Dependencies > Add Local** and choose this
repository. Select both library products:

- `ContourEffectsCore`
- `ContourEffectsMetal`

For a `Package.swift` host:

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

The explicit local alias keeps the dependency independent of the checkout
folder name. This repository does not yet have a Git remote or release tag, so
local path installation is the only supported reproducible route. Add a remote
URL example only after that repository and tag actually exist.

### 2. Import and construct an effect

```swift
import ContourEffectsCore
import ContourEffectsMetal

let effect = ColorGradeEffect()
let graph = MetalEffectGraph(effects: [effect])
try graph.prepare(
    context: MetalEffectHostContext(
        device: device,
        workingPixelFormat: .rgba16Float,
        workingColorSpace: .displaySRGB,
        alphaMode: .straight
    )
)
try graph.resize(width: width, height: height)
```

### 3. Encode on the host render queue

```swift
let frame = MetalEffectFrame(
    source: composedTexture,
    rawCamera: cameraTexture,
    analysisTextures: sharedAnalysisTextures,
    audio: audioFeatures,
    macros: performanceMacros,
    timing: frameTiming,
    providedInputs: [.audio, .performanceMacros]
)

try graph.encode(
    frame: frame,
    to: outputTexture,
    commandBuffer: commandBuffer
)
```

Run the independent working example:

```bash
./scripts/verify_contour_effects_sdk.sh
```

The verifier runs the minimal real-Metal frame and every executable declared in
the manifest's `ContourEffectsExamples` suite: catalog/state, 3D LUT,
analysis-mask, audio/macro, graph lifecycle, edge/flow, Film Look, and live
inputs. None of them links GLIC, Syphon, Vision, Core ML, YOLO, or Depth
Anything.

## Redistribution credit

When shipping a product that contains the SDK, include the complete
[`LICENSE`](../LICENSE) text in its About/Credits/Licenses view,
distributed documentation, or product bundle. A convenient visible credit is:

```text
ContourEffects SDK
Copyright (c) 2026 Daito Manabe.
Licensed under the BSD 3-Clause License.
```

The short credit helps identify the SDK, but does not replace the complete
license notice required for binary redistribution.

## Product boundary

| Product | Purpose | Required frameworks |
| --- | --- | --- |
| `ContourEffectsCore` | descriptors, state, timing, audio/macros, analysis data contracts, dependency metadata | Foundation |
| `ContourEffectsMetal` | render contract, same-command-buffer graph, LUT parser/texture, Final Color Grade / Film Finish | Foundation, Metal |

Apple Vision, Core ML, YOLO, Depth Anything V2, GLIC Metal, and Syphon are
**optional host capabilities**. The two SDK products do not link or bundle them
into a consumer target, and this standalone repository does not include model,
framework, or application payloads. Host-side installation is documented in
[CONTOUR_EFFECTS_THIRD_PARTY.md](CONTOUR_EFFECTS_THIRD_PARTY.md).

## Render contract

- Before instantiation, call `descriptor.validate()`, check
  `HostCapabilities.compatibility(with:)`, and reject a descriptor whose
  `canRun` is false.
- Instantiate the effect, call `prepare(context:)`, then
  `resize(width:height:)`, before `encode`.
- Call all effect methods, mutable configuration, state operations, and
  `setLUT` on one serial render queue.
- Supply one uncommitted command buffer. Effects encode into it and never call
  `commit`, wait for GPU completion, or perform CPU readback.
- The prepared device, source, destination, optional raw camera, analysis
  textures, LUT, and command-buffer queue must all use the same `MTLDevice`.
- Input and output must be distinct 2D, single-sample textures on the same Metal
  device and use the host's working pixel format.
- `source` needs `.shaderRead`; `destination` needs `.renderTarget`. Every
  effect defines every destination pixel. A masked effect composites
  `source`/`rawCamera` outside the mask instead of leaving black or undefined
  pixels.
- Resize outside the render hot path. `encode` throws `resizeRequired` instead
  of allocating.
- If `prepare` or `resize` throws, discard the graph/effect instances. If an
  effect throws during `encode`, discard that partially encoded command buffer
  instead of committing it.
- `source` is the current composed frame. Keep `rawCamera` separate so a masked
  effect can restore the camera outside its area without reading its own output
  and creating feedback. It must use the same crop, orientation, dimensions,
  color contract, and capture identity as the source represented by
  `inputSequence`.
- Run each enabled analysis provider at most once for each input frame it
  selects. Low-cadence asynchronous providers may reuse their newest valid
  snapshot across multiple render frames. All effects share that snapshot's
  `MetalAnalysisTextures` and landmark/detection arrays.
- Provider availability is explicit. An available detector may correctly return
  zero observations; use `providedInputs` to distinguish that from a missing
  provider.
- Audio and performance macro buses are available by default even when every
  value is zero.
- Persist `EffectStateSnapshot` by identifier and schema version. Unknown values
  are preserved so a newer host does not lose future parameters.
- Call `reset()` after a source change, timeline seek, dropped-sequence
  discontinuity, or explicit temporal reset.

## Analysis ABI 1.0

All coordinates use top-left-origin source UV: `(0,0)` is upper-left and
`(1,1)` is lower-right. Valid points, rectangles, confidence, masks, audio, and
macros are finite and normalized to `0...1`. A missing fixed-order landmark is
exactly `EffectPoint.missing` (`x=-1`, `y=-1`, `confidence=0`) and reports
`isValid == false`.

Detection IDs remain stable until track loss and are not reused within one
source generation. Detection velocity is normalized source displacement divided
by the change in `inputSequence`; +X is right and +Y is down.

Analysis textures may be lower resolution than the source, but must keep the
same aspect ratio, use normalized source UV without padding, be 2D,
single-sample, `.shaderRead`, and use the prepared device:

| Input | Pixel format | Channels |
| --- | --- | --- |
| edge | `r8Unorm` | R = edge magnitude, `0...1` |
| optical flow | `rg16Float` | RG = source-normalized UV displacement per input frame; +X right, +Y down |
| person mask | `r8Unorm` | R = membership, `0...1` |
| silhouette contour | `r8Unorm` | R = boundary coverage, `0...1` |
| scene mask | `r8Unorm` | R = foreground/subject membership, `0...1` |
| depth | `r16Float` | R = normalized relative depth; near=1, far=0, negative=invalid |

Every hand landmark set has exactly 21 points in `EffectHandJoint.rawValue`
order. Every body set has exactly 19 points in `EffectBodyJoint.rawValue` order.
Keep the array length fixed and insert `EffectPoint.missing` for an unobserved
joint. A landmark-set ID stays stable while the provider tracks the same
subject.

Depth providers must adapt native output before constructing
`MetalEffectFrame`:

1. Determine finite per-snapshot percentiles `P05` and `P95`.
2. If the provider's larger raw value means nearer, write
   `saturate((raw - P05) / (P95 - P05))`. If smaller means nearer (for example
   metric camera depth), write
   `1 - saturate((raw - P05) / (P95 - P05))`.
3. Write a negative value for invalid samples or a degenerate percentile range.
4. Resample the full normalized provider extent into a source-aligned texture
   with the source aspect ratio and no padding. For Depth Anything V2's native
   `518x392` output, undo any host letterbox/crop first; if the full camera was
   resized non-uniformly into the model, resize the full output back to the
   source-aligned 16:9 field.

ABI 1.0 does not require temporal smoothing. An effect may smooth depth
internally, but the host snapshot supplied here must retain its capture identity.

`providedInputs` can declare audio/macros and an empty point/landmark/detection
provider. It cannot fabricate raw-camera or analysis-texture availability; those
inputs become available only when their validated Metal texture is non-nil.

For `.analysisMatchedFrame`, the host supplies analysis derived from the same
`inputSequence`. For `.latestLowLatency`, the host may supply its newest valid
snapshot and remains responsible for staleness limits.

## Color and LUT contract

`ColorGradeEffect` accepts and writes `rgba16Float` in display-referred sRGB /
Rec.709 primaries with straight alpha. It rejects a linear or premultiplied host
context. It is intentionally a **display-referred final pass**: RGB is clamped
to `0...1`, while input alpha is preserved. Put HDR bloom/emission operations
before it.

Only 3D `.cube` LUTs of size `2...64` are accepted. The parser validates domain,
finite Float16-representable samples, and exact sample count before allocating a
`rgba16Float` 3D texture. A `.cube` file carries no reliable color-space
metadata, so select the contract explicitly:

- `displayRGB`: LUT domain input and LUT output are display-referred sRGB.
- `linearSRGB`: the shader converts display sRGB to linear sRGB before lookup,
  treats LUT output as linear sRGB, then converts it back to display sRGB.

User-imported LUT redistribution rights remain the responsibility of the host
application and its operator.

LUT parsing and texture upload happen outside the frame path. The generic
parameter setter intentionally rejects the `fileReference` parameter: resolve a
stable LUT identifier in the host, construct `MetalLUT3D` on the prepared
device, then call `ColorGradeEffect.setLUT(_:)`. Restoring state alone does not
load a file. Supply `renderPresentationSeconds` so film grain advances.

## Parameters, state, and API compatibility

- `.float` / `.integer` values are finite and range-checked.
- `.boolean` / `.trigger` use `EffectValue.bool`.
- `.enumeration` declares at least one choice, every choice ID is unique, and
  the value uses the same storage type as its descriptor default and matches a
  declared choice ID.
- `.color` uses 3 or 4 finite numbers; `.vector2` uses 2 finite numbers.
- `.fileReference` is a stable asset identifier resolved by the host, not an
  arbitrary file read inside the render path.

The generic setter throws for wrong types/ranges instead of silently succeeding.
API major versions must match; a host API minor version can run an effect whose
minor version is equal or older. `HostCapabilities.compatibility(with:)`
reports an unsupported API before instantiation.

`restoreState` rejects the wrong `effectIdentifier`. For a matching identifier,
known values are applied and unknown values are retained; a newer state schema
can therefore round-trip through the current Final Color Grade effect without
losing data. Migration from an older schema is effect-specific and must happen
inside that effect before applying its values. `reset()` clears temporal
simulation/history only; it does not clear the current parameter snapshot.

## Catalog boundary

The public effect surface is the set of entries returned by
`ContourEffectsMetalCatalog`. The current preview exposes Final Color Grade /
Film Finish. Host-only effects and arbitrary presets are not implicitly part of
the SDK API.

The machine-readable distribution and dependency state is
[`SDK/contour-effects-sdk.json`](../SDK/contour-effects-sdk.json).
