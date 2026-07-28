<!-- SPDX-FileCopyrightText: 2026 Daito Manabe -->
<!-- SPDX-License-Identifier: BSD-3-Clause -->

# Third-Party Notices Index

`ContourEffectsCore` and `ContourEffectsMetal` link only Apple Foundation and
Metal. They do not bundle a third-party binary, model, resource bank, or host
application asset.

The first-party ContourEffects SDK license is [`LICENSE`](../LICENSE). Its exact
scope and redistribution
instructions are in [`SDK/SCOPE.md`](../SDK/SCOPE.md) and
[`SDK/ATTRIBUTION.md`](../SDK/ATTRIBUTION.md). Those files do not replace any
third-party terms.

| Optional host integration | Bundled by this repository | Notice responsibility |
| --- | ---: | --- |
| Apple Vision / Core ML | No | The host follows the applicable Apple SDK agreements |
| YOLOv3 Tiny / Depth Anything V2 Small | No | The host obtains and ships the license/notices for the exact model payload |
| GLIC Metal | No | The host copies GLIC's `LICENSE` and `THIRD_PARTY_NOTICES.md` |
| Official Syphon.framework | No | The host includes [`Syphon-License.txt`](Syphon-License.txt) when it embeds Syphon |

`Syphon-License.txt` is the only third-party license text stored here. Its
presence does not mean that `Syphon.framework` is linked or bundled by the SDK.

See
[`docs/CONTOUR_EFFECTS_THIRD_PARTY.md`](../docs/CONTOUR_EFFECTS_THIRD_PARTY.md)
for pinned upstream sources, installation steps, runtime ownership, and the
analysis-texture integration contract.
