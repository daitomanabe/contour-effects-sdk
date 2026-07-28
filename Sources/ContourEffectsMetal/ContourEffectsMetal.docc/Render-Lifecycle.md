# Render lifecycle
<!-- SPDX-FileCopyrightText: 2026 Daito Manabe -->
<!-- SPDX-License-Identifier: BSD-3-Clause -->

Effect graphの生成から1 frameのencode、reset、再構成までの順序を定義します。

## 1. Discover and preflight

```swift
for descriptor in ContourEffectsMetalCatalog.descriptors {
    try descriptor.validate()
    let report = hostCapabilities.compatibility(with: descriptor)
    guard report.canRun else { continue }
}
```

`HostCapabilities`の既定値は`.composedColor`だけです。ホストが常時用意する
audio／macro busも、preflightでは`.audio`と`.performanceMacros`を明示します。

## 2. Construct

```swift
guard let effect = ContourEffectsMetalCatalog.makeEffect(
    identifier: ColorGradeEffect.identifier
) else {
    return
}
let graph = MetalEffectGraph(effects: [effect])
```

具体的な型が必要な場合は``ColorGradeEffect``を直接生成できます。asset parse、
LUT upload、state migrationはframe pathの外で済ませます。

## 3. Prepare

```swift
let context = MetalEffectHostContext(
    device: device,
    workingPixelFormat: .rgba16Float,
    workingColorSpace: .displaySRGB,
    alphaMode: .straight
)
try graph.prepare(context: context)
```

``MetalEffectGraph/prepare(context:)``は各effectのpipelineを同じdeviceへ準備します。
失敗したgraphは破棄して作り直します。

## 4. Resize

```swift
try graph.resize(width: outputWidth, height: outputHeight)
```

drawable、capture crop、output解像度が変わった時だけ呼びます。allocationを
frame encodeへ持ち込まないため、サイズが合わないframeは
``MetalEffectError/resizeRequired(expectedWidth:expectedHeight:)``で失敗します。

## 5. Encode

```swift
let frame = MetalEffectFrame(
    source: composedTexture,
    rawCamera: rawCameraTexture,
    analysisTextures: analysis,
    featurePoints: featurePoints,
    handLandmarks: hands,
    bodyLandmarks: bodies,
    detections: detections,
    audio: audio.clamped(),
    macros: macros.clamped(),
    timing: timing,
    providedInputs: [
        .featurePoints,
        .handLandmarks,
        .bodyLandmarks,
        .objectDetections,
        .audio,
        .performanceMacros,
    ]
)

try graph.encode(
    frame: frame,
    to: outputTexture,
    commandBuffer: commandBuffer
)
commandBuffer.commit()
```

Effect graphは同じ未commit command bufferへ全passをencodeします。ホストだけが
commit、completion handler、in-flight semaphore、presentを管理します。

## 6. Reset and replace

``MetalEffectGraph/reset()``を次の場合に呼びます。

- camera／input sourceの変更
- timeline seek
- capture generationの変更
- sequence discontinuity
- operatorによる明示reset

``MetalEffectGraph/replaceEffects(_:)``は準備済みcontextと現在sizeを新しいeffectへ
適用します。preset切替をrender queue上で行い、encode中のgraphを別queueから
変更しません。

## Failure policy

| Failure | Recovery |
| --- | --- |
| descriptor／compatibility | instanceを作らずUIへ不足を表示 |
| `prepare`／`resize` | graphを破棄して安全な構成から再生成 |
| `encode` | command bufferをcommitせず、そのframeを破棄 |
| LUT parse／upload | LUTなしへfallbackし、元fileは変更しない |
| analysis unavailable | 必須ならeffectをskip、任意ならfallback |

@Links(visualStyle: compactGrid) {
    - <doc:MetalEffectInstance-Guide>
    - <doc:MetalEffectGraph-Guide>
    - <doc:MetalEffectFrame-Guide>
}
