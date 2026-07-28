<!-- SPDX-FileCopyrightText: 2026 Daito Manabe -->
<!-- SPDX-License-Identifier: BSD-3-Clause -->

# ContourEffects executable examples

The current source preview requires macOS 14+ on Apple Silicon (`arm64`).

These headless examples exercise eight integration surfaces that are intentionally
outside the minimal first-pixel host:

- `ContourEffectsCatalogStateExample`: descriptor discovery, capability and
  dependency reporting, generic parameter mutation, and forward-compatible JSON
  state round-tripping.
- `ContourEffectsLUTRenderExample`: an authored in-source 2×2×2 `.cube` LUT,
  `MetalLUT3D`, same-command-buffer rendering, and deterministic pixel checks.
- `ContourEffectsAnalysisMaskExample`: an example-local `MetalEffectInstance`
  that consumes a synthetic person mask, processes the subject, and restores
  the separate raw camera outside the mask.
- `ContourEffectsAudioMacroReactiveExample`: a visible spatial and color
  response driven by normalized audio features and the Energy, Motion,
  Audio Reactive, and Color semantic macros, including missing-provider
  rejection.
- `ContourEffectsGraphLifecycleExample`: two-stage composition, effect
  replacement, empty-graph pass-through, resize checks, and in-place rejection.
- `ContourEffectsEdgeFlowWarpExample`: edge-gated warping with a quarter-size
  optical-flow texture, plus pixel-format and aspect-ratio failure checks.
- `ContourEffectsColorLookGalleryExample`: deterministic rendering and
  comparison of every built-in `ColorGradeLook`.
- `ContourEffectsLiveInputsExample`: audio/macro normalization, frame timing,
  hand/body landmark ordering, detections, and zero-observation provider
  availability.

The package imports only `ContourEffectsCore`, `ContourEffectsMetal`, Foundation,
and Metal. It does not use ContourFlow source, models, assets, GLIC, Syphon,
Vision, or Core ML.

## Build

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcrun swift build \
  --package-path Examples/ContourEffectsExamples
```

## Run the self-checks

```bash
for example in \
  ContourEffectsCatalogStateExample \
  ContourEffectsLUTRenderExample \
  ContourEffectsAnalysisMaskExample \
  ContourEffectsAudioMacroReactiveExample \
  ContourEffectsGraphLifecycleExample \
  ContourEffectsEdgeFlowWarpExample \
  ContourEffectsColorLookGalleryExample \
  ContourEffectsLiveInputsExample
do
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
    xcrun swift run \
    --package-path Examples/ContourEffectsExamples \
    "$example" --self-check
done
```

Every executable prints a stable JSON report and exits non-zero when a contract
check fails. Shared GPU texture and report helpers live in `ExampleSupport`;
effect-specific behavior stays in the corresponding executable target.

The [API and major-class manual](../../docs/CONTOUR_EFFECTS_API.md) connects
each example to the corresponding Core and Metal DocC guide.

These files use the ContourEffects
[BSD-3-Clause license](../../LICENSE). See the repository
[license scope](../../SDK/SCOPE.md) and
[redistribution guide](../../SDK/ATTRIBUTION.md).
