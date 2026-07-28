# Writing a new effect
<!-- SPDX-FileCopyrightText: 2026 Daito Manabe -->
<!-- SPDX-License-Identifier: BSD-3-Clause -->

新しい``MetalEffectInstance``を作り、host analysisを重複実行せずcatalogへ追加する手順です。

## 1. Stable descriptor

effect IDとparameter IDはpreset／automationの永続keyです。公開後は変更しません。

```swift
static let identifier: EffectIdentifier =
    "com.example.contour-effects.utility.copy"

static let effectDescriptor = EffectDescriptor(
    id: identifier,
    displayName: "Copy",
    category: .utility,
    requiredInputs: [.composedColor]
)
```

catalog登録前に`try effectDescriptor.validate()`をtestします。

## 2. Implement the lifecycle

最小のcopy effectは次の形です。

```swift
import ContourEffectsCore
import ContourEffectsMetal
import Metal

final class CopyEffect: MetalEffectInstance {
    static let identifier: EffectIdentifier =
        "com.example.contour-effects.utility.copy"

    static let effectDescriptor = EffectDescriptor(
        id: identifier,
        displayName: "Copy",
        category: .utility,
        requiredInputs: [.composedColor]
    )
    let descriptor = effectDescriptor

    private var preparedDevice: MTLDevice?
    private var workingPixelFormat: MTLPixelFormat?
    private var renderWidth = 0
    private var renderHeight = 0
    private var preservedSchemaVersion =
        CopyEffect.effectDescriptor.stateSchemaVersion
    private var preservedStateValues: [String: EffectValue] = [:]

    func prepare(context: MetalEffectHostContext) throws {
        preparedDevice = context.device
        workingPixelFormat = context.workingPixelFormat
        renderWidth = 0
        renderHeight = 0
    }

    func resize(width: Int, height: Int) throws {
        guard preparedDevice != nil else {
            throw MetalEffectError.notPrepared
        }
        guard width > 0, height > 0 else {
            throw MetalEffectError.incompatibleDestination
        }
        renderWidth = width
        renderHeight = height
    }

    func encode(
        frame: MetalEffectFrame,
        to destination: MTLTexture,
        commandBuffer: MTLCommandBuffer
    ) throws {
        guard let preparedDevice, let workingPixelFormat else {
            throw MetalEffectError.notPrepared
        }
        try frame.validate(requiredInputs: descriptor.requiredInputs)
        guard renderWidth == frame.source.width,
              renderHeight == frame.source.height
        else {
            throw MetalEffectError.resizeRequired(
                expectedWidth: frame.source.width,
                expectedHeight: frame.source.height
            )
        }

        let source = frame.source
        guard source.width > 0,
              source.height > 0,
              source.textureType == .type2D,
              source.sampleCount == 1,
              source.pixelFormat == workingPixelFormat,
              source.usage.contains(.shaderRead),
              source.device === preparedDevice,
              source.device === commandBuffer.commandQueue.device
        else {
            throw MetalEffectError.incompatibleSource
        }
        guard source !== destination,
              destination.width == source.width,
              destination.height == source.height,
              destination.textureType == .type2D,
              destination.sampleCount == 1,
              destination.pixelFormat == workingPixelFormat,
              destination.device === preparedDevice,
              destination.usage.contains(.renderTarget)
        else {
            throw MetalEffectError.incompatibleDestination
        }
        guard let encoder = commandBuffer.makeBlitCommandEncoder() else {
            throw MetalEffectError.incompatibleDestination
        }
        encoder.copy(
            from: source,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: .init(x: 0, y: 0, z: 0),
            sourceSize: .init(
                width: source.width,
                height: source.height,
                depth: 1
            ),
            to: destination,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: .init(x: 0, y: 0, z: 0)
        )
        encoder.endEncoding()
    }

    func reset() {}

    func snapshotState() -> EffectStateSnapshot {
        EffectStateSnapshot(
            effectIdentifier: Self.identifier,
            schemaVersion: preservedSchemaVersion,
            values: preservedStateValues
        )
    }

    func restoreState(_ state: EffectStateSnapshot) throws {
        guard state.effectIdentifier == Self.identifier else {
            throw MetalEffectError.invalidState("wrong effect identifier")
        }
        preservedSchemaVersion = state.schemaVersion
        preservedStateValues = state.values
    }
}
```

このcopy effectも、prepared device、pixel format、sizeをinstanceへ保持し、直接
`encode`された場合のtexture ABIを検証し、destination全pixelを定義します。parameterを
持つeffectでは、既知keyを検証・適用した後も未知keyと受信schema versionを保持します。

通常は``MetalEffectGraph``経由で呼び、graph全体のraw camera／analysis resource
validationも利用します。

## 3. Declare analysis inputs

```swift
let descriptor = EffectDescriptor(
    id: "com.example.contour-effects.analysis.subject",
    displayName: "Subject",
    category: .analysis,
    requiredInputs: [
        .composedColor,
        .rawCameraColor,
        .personMask,
    ],
    optionalInputs: [
        .edge,
        .opticalFlow,
        .audio,
    ]
)
```

providerをeffect内で起動しません。hostは必要な解析をinput frameごとに最大1回実行し、
結果を``MetalAnalysisTextures``またはCore value payloadへ変換して共有します。

mask外はraw camera／sourceを明示合成します。destinationを未定義、透明、黒のままに
しないでください。

## 4. Parameters and state

- descriptorのkind／range／defaultを正しく宣言する。
- `setParameterValue`でvalidationし、render queue上のconfigurationへ反映する。
- `snapshotState`で未知keyを保持する。
- `restoreState`でeffect IDとschemaを確認する。
- file referenceはhost asset resolverから型付きresourceへ変換する。
- `reset`でparameterを消さずtemporal historyだけを消す。

## 5. Register and test

production SDK effectを公開する時は``ContourEffectsMetalCatalog/descriptors``と
``ContourEffectsMetalCatalog/makeEffect(identifier:)``へ同時に登録します。

最低限のtest:

1. descriptor validation
2. catalogからの生成
3. required input不足
4. texture ABIとdevice mismatch
5. real Metal frame encode
6. alphaとmask外合成
7. state JSON round tripと未知key保持
8. resize／reset／source discontinuity
9. optional dependencyなしのfallback
10. frame pathにallocation／compile／readbackがないこと

synthetic person maskを使う完全な実行例は
`Examples/ContourEffectsExamples/ContourEffectsAnalysisMaskExample`を参照してください。

@Links(visualStyle: compactGrid) {
    - <doc:MetalEffectInstance-Guide>
    - <doc:MetalEffectFrame-Guide>
    - <doc:MetalEffectGraph-Guide>
}
