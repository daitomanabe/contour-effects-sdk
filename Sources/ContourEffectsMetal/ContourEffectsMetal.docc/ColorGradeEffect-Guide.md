# ColorGradeEffect guide
<!-- SPDX-FileCopyrightText: 2026 Daito Manabe -->
<!-- SPDX-License-Identifier: BSD-3-Clause -->

``ColorGradeEffect``は、effect chainの最後に置くdisplay-referred finishing passです。

## Required context

- pixel format: `rgba16Float`
- color space: ``MetalWorkingColorSpace/displaySRGB``
- alpha: ``MetalAlphaMode/straight``

RGBは`0...1`へclampし、source alphaは維持します。HDR bloom、emission、linear-light
operationはColor Gradeより前へ置きます。

## Starting looks

```swift
var configuration = ColorGradeConfiguration()
configuration.applyLook(.cinema)
let effect = ColorGradeEffect(configuration: configuration)
```

``ColorGradeConfiguration/applyLook(_:)``はgrading control一式をlookへ更新し、
enabledとLUT設定は保持します。`configuration.look = .cinema`とcaseだけ代入しても
control値は変わらないため、starting lookには`applyLook`を使います。

## Parameters

| ID | Range／type |
| --- | --- |
| `enabled` | boolean |
| `look` | ``ColorGradeLook``のnumeric raw value |
| `exposure` | `-3...3` |
| `brightness` | `-0.5...0.5` |
| `contrast` | `0.5...2` |
| `saturation` | `0...2` |
| `temperature` / `tint` | `-1...1` |
| `gamma` | `0.5...2` |
| `blackLift` | `0...0.5` |
| `highlightRolloff` / `filmCurve` / `grain` / `vignette` | `0...1` |
| `lut` | host-resolved file reference ID |
| `lutMix` | `0...1` |
| `lutInputSpace` | ``LUTInputSpace``のnumeric raw value |

```swift
try effect.setParameterValue(
    .number(1.15),
    identifier: "contrast"
)
```

``ColorGradeConfiguration/sanitize()``は外部値を安全範囲へclampします。
``ColorGradeConfiguration/isIdentity``はeffectが視覚的にneutralかを判定します。

## LUT

```swift
let cube = try CubeLUT.load(from: lutURL)
let metalLUT = try MetalLUT3D(
    identifier: stableAssetID,
    cube: cube,
    device: device
)

effect.setLUT(metalLUT)
effect.configuration.lutMix = 1
effect.configuration.lutInputSpace = .displayRGB
```

LUT parseとuploadはframe pathの外で行います。``ColorGradeEffect/setLUT(_:)``へ`nil`を
渡すと`lutMix`も0になります。

stateに保存された`lutIdentifier`だけではfileを読みません。host asset resolverが
同じIDの``MetalLUT3D``を復元し、`setLUT`でattachした時だけLUTが有効になります。

## Grain time

grainを時間変化させるには`EffectFrameTiming.renderPresentationSeconds`を毎frame
供給します。値が常に0ならgrain patternも固定されます。

## State

``ColorGradeEffect/snapshotState()``は未知keyとschema versionを保持します。
``ColorGradeEffect/restoreState(_:)``は別effect IDを拒否し、既知parameterを
configurationへ適用します。`reset()`はstatelessなためparameterを変更しません。

@Links(visualStyle: compactGrid) {
    - <doc:CubeLUT-and-MetalLUT3D>
    - <doc:MetalEffectGraph-Guide>
    - <doc:Render-Lifecycle>
}
