<!-- SPDX-FileCopyrightText: 2026 Daito Manabe -->
<!-- SPDX-License-Identifier: BSD-3-Clause -->

# Minimal ContourEffects Host

The current source preview requires macOS 14+ on Apple Silicon (`arm64`).

This is an independent Swift package that imports only:

- `ContourEffectsCore`
- `ContourEffectsMetal`
- Apple's system `Metal.framework`

It does not link GLIC, Syphon, Vision, Core ML, YOLO, or Depth Anything.
Run the real Metal smoke test from the repository root:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcrun swift run --package-path Examples/MinimalContourEffectsHost
```

The program creates a 64×64 Metal frame, applies the SDK color-grade effect on
one command buffer, waits only because this is a command-line smoke test, and
prints the first output pixel.

For descriptor/state, LUT, and analysis-mask integration, continue with the
[`ContourEffectsExamples`](../ContourEffectsExamples) package. The
[API and major-class manual](../../docs/CONTOUR_EFFECTS_API.md) explains the
render lifecycle and links to the Core and Metal DocC catalogs.

ContourEffects SDK is BSD-3-Clause licensed. A redistributed host must include
the complete [`LICENSE`](../../LICENSE) text. See
[`SDK/SCOPE.md`](../../SDK/SCOPE.md) and
[`SDK/ATTRIBUTION.md`](../../SDK/ATTRIBUTION.md) for the exact boundary and a
copy-ready credit.
