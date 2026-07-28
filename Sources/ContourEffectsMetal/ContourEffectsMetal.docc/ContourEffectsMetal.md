# ``ContourEffectsMetal``
<!-- SPDX-FileCopyrightText: 2026 Daito Manabe -->
<!-- SPDX-License-Identifier: BSD-3-Clause -->

Metal textureを同じcommand buffer上で処理し、解析結果、状態、ライブ入力を
再利用可能なeffectへ渡すための描画APIです。

## Overview

ContourEffectsMetalは次の境界を提供します。

- ``MetalEffectInstance``によるeffect共通lifecycle
- ``MetalEffectGraph``によるserial compositionとping-pong texture管理
- ``MetalEffectFrame``によるsource、raw camera、解析、音声、macro、時刻の共有
- ``MetalAnalysisTextures``によるedge、flow、mask、contour、depthのGPU ABI
- ``ContourEffectsMetalCatalog``によるeffect discoveryと生成
- ``ColorGradeEffect``によるFinal Color Grade / Film Finish
- ``CubeLUT``と``MetalLUT3D``による3D LUTの検証とdevice upload

Core/Metal製品だけではVision、Core ML、YOLO、Depth Anything、GLIC、Syphonを
linkしません。ホストが必要なproviderだけを実行し、同一frameの解析snapshotを
全effectへ共有します。

@Links(visualStyle: detailedGrid) {
    - <doc:Render-Lifecycle>
    - <doc:MetalEffectInstance-Guide>
    - <doc:MetalEffectGraph-Guide>
    - <doc:MetalEffectFrame-Guide>
    - <doc:ColorGradeEffect-Guide>
    - <doc:CubeLUT-and-MetalLUT3D>
    - <doc:Writing-a-New-Effect>
}

## 最小のrender graph

```swift
import ContourEffectsCore
import ContourEffectsMetal
import Metal

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

let frame = MetalEffectFrame(
    source: sourceTexture,
    rawCamera: cameraTexture,
    timing: timing
)

try graph.encode(
    frame: frame,
    to: destinationTexture,
    commandBuffer: commandBuffer
)
commandBuffer.commit()
```

Effectはcommand bufferをcommitせず、GPU完了を待たず、CPU readbackを行いません。
commitとframe pacingはホストが所有します。

## Host contract

1. 全mutable APIを1本のserial render queueから呼ぶ。
2. descriptorを検証し、host capabilityと照合してからinstanceを作る。
3. `prepare`、`resize`を終えてから`encode`する。
4. sourceとdestinationを別textureにし、同じdevice／pixel formatを使う。
5. raw cameraを合成済みsourceと分け、mask外を黒やfeedbackにしない。
6. 解析providerは入力frameごとに最大1回実行し、結果を全effectへ共有する。
7. source変更、seek、sequence discontinuityで`reset`する。
8. encode失敗時は、途中までencodeしたcommand bufferをcommitしない。

## Topics

### Hostとframe

- ``MetalEffectHostContext``
- ``MetalWorkingColorSpace``
- ``MetalAlphaMode``
- ``MetalEffectFrame``
- ``MetalAnalysisTextures``

### Effectとgraph

- ``MetalEffectInstance``
- ``MetalEffectGraph``
- ``MetalEffectError``
- ``ContourEffectsMetalCatalog``

### Final color

- ``ColorGradeEffect``
- ``ColorGradeConfiguration``
- ``ColorGradeLook``
- ``LUTInputSpace``
- ``CubeLUT``
- ``MetalLUT3D``
- ``CubeLUTError``
