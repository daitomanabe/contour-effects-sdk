# MetalEffectFrame and analysis textures
<!-- SPDX-FileCopyrightText: 2026 Daito Manabe -->
<!-- SPDX-License-Identifier: BSD-3-Clause -->

``MetalEffectFrame``は1 output frameで共有する映像、解析、live control、時刻のviewです。

## Source and raw camera

``MetalEffectFrame/source``は現在までの合成結果です。
``MetalEffectFrame/rawCamera``はfeedbackやpost effectを含まないcamera frameです。

raw cameraはsourceと同じ次の条件を満たします。

- crop、orientation、mirror
- width／height、pixel format、device
- `inputSequence`が表すcapture identity

mask内だけを処理するeffectは、mask外へraw cameraまたはsourceを合成します。raw cameraを
過去のeffect outputから生成するとfeedbackが起きるため、capture側から分離して渡します。

## Analysis texture ABI

``MetalAnalysisTextures``はproviderごとに再計算せず、同じsnapshotを全effectへ共有します。

| Property | Pixel format | Value |
| --- | --- | --- |
| `edge` | `r8Unorm` | edge magnitude `0...1` |
| `opticalFlow` | `rg16Float` | source UV displacement／input frame、+X右、+Y下 |
| `personMask` | `r8Unorm` | person membership `0...1` |
| `silhouetteContour` | `r8Unorm` | boundary coverage `0...1` |
| `sceneMask` | `r8Unorm` | subject membership `0...1` |
| `depth` | `r16Float` | near=1、far=0、negative=invalid |

textureは2D、single-sample、`.shaderRead`、prepared device上に置きます。sourceより
低解像度でも、同じaspect ratioと全source UV範囲を維持し、letterboxを含めません。

## Value payloads

frameはCoreの値型も持ちます。

- `featurePoints`
- `handLandmarks`
- `bodyLandmarks`
- `detections`
- `audio`
- `macros`
- `timing`

音声とmacroは`EffectAudioFeatures.clamped(maximumBandCount:)`と
`EffectPerformanceMacros.clamped()`を通してから渡します。

## Availability

``MetalEffectFrame/availableInputs``は実resourceと
``MetalEffectFrame/providedInputs``から計算されます。

- raw camera／analysis texture: non-nilの検証対象resourceだけでavailableになる
- point／landmark／detection provider: 観測0件でも`providedInputs`でavailableを表せる
- audio／macro: 既定でavailable。値が0でもbusは存在する

`providedInputs`へ`.personMask`や`.rawCameraColor`を書いて、存在しないtextureを
availableに見せることはできません。

```swift
let frame = MetalEffectFrame(
    source: source,
    rawCamera: rawCamera,
    analysisTextures: .init(
        edge: edge,
        personMask: personMask,
        depth: depth
    ),
    handLandmarks: [],
    audio: audio,
    macros: macros,
    timing: timing,
    providedInputs: [
        .handLandmarks,
        .audio,
        .performanceMacros,
    ]
)
```

この例ではhand providerは有効だが観測0件です。edge、person mask、depthはtextureの
存在からavailableになります。

## Timing

grainやanimationには`EffectFrameTiming.renderPresentationSeconds`、物理更新には
`deltaSeconds`、解析とsourceのcapture identityには`inputSequence`を使います。
非同期解析も元のsequenceを保持し、synchronization policyに応じてhostが選びます。

@Links(visualStyle: compactGrid) {
    - <doc:Render-Lifecycle>
    - <doc:MetalEffectGraph-Guide>
    - <doc:Writing-a-New-Effect>
}
