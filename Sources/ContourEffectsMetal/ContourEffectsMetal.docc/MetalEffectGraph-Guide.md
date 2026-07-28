# MetalEffectGraph guide
<!-- SPDX-FileCopyrightText: 2026 Daito Manabe -->
<!-- SPDX-License-Identifier: BSD-3-Clause -->

``MetalEffectGraph``は、複数effectを1本のcommand bufferへ順番にencodeする
host-side composition objectです。

## What the graph owns

- ordered ``MetalEffectGraph/effects`` array
- prepared ``MetalEffectHostContext``
- 現在のwidth／height
- 中間pass用の2枚のprivate ping-pong texture

ping-pong textureのpixel formatは
``MetalEffectHostContext/workingPixelFormat``と一致します。

source、destination、command buffer、analysis snapshotは所有しません。

## Setup

```swift
let grade = ColorGradeEffect()
let graph = MetalEffectGraph(effects: [grade])

try graph.prepare(
    context: MetalEffectHostContext(device: device)
)
try graph.resize(width: 1920, height: 1080)
```

必ず`prepare`の後に`resize`を呼びます。effectは`prepare`で確定したdeviceやpixel
formatを使って、`resize`時にsize依存resourceを作成できます。

## Encode

```swift
try graph.encode(
    frame: frame,
    to: destination,
    commandBuffer: commandBuffer
)
```

各passの出力は次passの`source`になります。最後のeffectだけがdestinationへ直接書き、
中間passはscratch textureを交互に使います。

effectが0件の場合、graphはsourceをdestinationへblitしてpassthroughします。sourceと
destinationを同じtextureにはできません。

## Replace effects

```swift
try graph.replaceEffects([
    firstEffect,
    finalColorGrade,
])
```

graphが準備済みなら、新しいeffectにも現在contextとsizeを適用します。replaceは
render queue上のframe境界で行います。

## Resource validation

graphはencode前に次を検証します。

- source／destination／command queueのdevice
- working pixel format
- source／destination sizeとusage
- raw cameraのsize、format、usage
- analysis textureのdevice、format、2D、sample count、aspect ratio
- effectごとのrequired input

利用可能な解析結果が0件でもprovider自体が有効な場合は、
``MetalEffectFrame/providedInputs``へprovider flagを入れます。

## Error recovery

`prepare`または`resize`中にいずれかのeffectが失敗すると、graphはprepared contextと
scratchを無効化します。そのgraphを継続利用せず、原因を修正して新しいgraphを作ります。

`encode`で失敗した場合は、command bufferへ一部passが入っている可能性があります。
そのbufferをcommitせずframeごと破棄します。

@Links(visualStyle: compactGrid) {
    - <doc:Render-Lifecycle>
    - <doc:MetalEffectFrame-Guide>
    - <doc:MetalEffectInstance-Guide>
}
