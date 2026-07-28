<!-- SPDX-FileCopyrightText: 2026 Daito Manabe -->
<!-- SPDX-License-Identifier: BSD-3-Clause -->

# ContourEffects SDK license scope

## Licensed under BSD-3-Clause

The following first-party files are covered by the
[BSD 3-Clause License](../LICENSE):

- `.gitignore`;
- `AGENTS.md`;
- `Package.swift`;
- `README.md`;
- `LICENSE`;
- `SDK/ATTRIBUTION.md`;
- `SDK/SCOPE.md`;
- `SDK/contour-effects-sdk.json`;
- files carrying both ContourEffects BSD SPDX headers under
  `Sources/ContourEffectsCore/**`;
- files carrying both ContourEffects BSD SPDX headers under
  `Sources/ContourEffectsMetal/**`;
- files carrying both ContourEffects BSD SPDX headers under
  `Tests/ContourEffectsCoreTests/**`;
- files carrying both ContourEffects BSD SPDX headers under
  `Tests/ContourEffectsMetalTests/**`;
- files carrying both ContourEffects BSD SPDX headers under
  `Examples/MinimalContourEffectsHost/**`, excluding generated `.build/**`;
- files carrying both ContourEffects BSD SPDX headers under
  `Examples/ContourEffectsExamples/**`, excluding generated `.build/**`;
- `docs/CONTOUR_EFFECTS_API.md`;
- `docs/CONTOUR_EFFECTS_SDK.md`;
- `docs/CONTOUR_EFFECTS_THIRD_PARTY.md`;
- `scripts/verify_contour_effects_sdk.sh`; and
- `ThirdPartyNotices/README.md`.

A future file under one of the SDK roots is outside this grant until it carries
both SPDX headers and passes the SDK license and provenance verification.

## Not licensed by this grant

The following material is not relicensed by the ContourEffects BSD grant:

- `ThirdPartyNotices/Syphon-License.txt`, which remains Syphon's license text;
- optional Apple frameworks, models, GLIC, Syphon binaries, or their resources;
- user-imported LUTs, models, media, presets, logos, and 3D assets; and
- generated `.build/**`, `.swiftpm/**`, DerivedData, `.doccarchive`, captures,
  distributions, artifacts, and temporary files.

Nothing in the root `LICENSE` changes or replaces a third party's license. A host
that downloads or redistributes an optional dependency must review and include
that component's own required notices.
