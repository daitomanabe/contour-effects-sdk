<!-- SPDX-FileCopyrightText: 2026 Daito Manabe -->
<!-- SPDX-License-Identifier: BSD-3-Clause -->

# ContourEffects SDK agent rules

## Git

- Commit every coherent change after the smallest relevant validation.
- Keep commits narrow. Do not mix API changes, documentation, generated output,
  or unrelated refactors.
- Do not amend, squash, reset, push, or create a remote unless explicitly
  requested.
- Review `git diff --check` and `git status --short` before committing.

## Validation

- Run `swift test` for Core or Metal source changes.
- Run `./scripts/verify_contour_effects_sdk.sh` for public API, rendering,
  examples, state, manifest, licensing, or lifecycle changes.
- Keep every executable example headless, deterministic, and self-checking.

## SDK boundary

- `ContourEffectsCore` remains Foundation-only.
- `ContourEffectsMetal` remains Foundation + Metal only.
- Vision, Core ML, YOLO, Depth Anything, GLIC, and Syphon are optional host
  capabilities. Do not link, bundle, or download them from SDK targets.
- Preserve stable public effect and parameter identifiers.
- Preserve unknown `EffectStateSnapshot` keys and schema versions.

## Metal lifecycle

- Use `prepare -> resize -> encode` on one serial render queue.
- Effects only encode into the host's uncommitted command buffer. They do not
  commit, wait, perform CPU readback, compile shaders, or allocate textures in
  the frame path.
- Source and destination are distinct. Masked effects define every output pixel
  and preserve source or raw camera outside the mask.

## Generated files

- Do not commit `.build/`, `.swiftpm/`, DerivedData, `.doccarchive`, captures,
  artifacts, or `.DS_Store`.
