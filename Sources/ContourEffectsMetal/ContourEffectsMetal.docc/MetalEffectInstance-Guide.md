# MetalEffectInstance guide
<!-- SPDX-FileCopyrightText: 2026 Daito Manabe -->
<!-- SPDX-License-Identifier: BSD-3-Clause -->

``MetalEffectInstance``は、同期的でCPU readbackを行わないMetal effectの共通契約です。

## Ownership

- instance、configuration、GPU pipeline、historyはeffectが所有する。
- device、command queue、command buffer、input/output textureはホストが所有する。
- 全methodは同じserial render queueから呼ぶ。
- instanceを複数queueから同時に操作しない。

## Required methods

| API | 責務 |
| --- | --- |
| `descriptor` | instance生成前にも取得できる安定したmetadataとparameter schema |
| `prepare(context:)` | pipeline／device-bound resourceを準備 |
| `resize(width:height:)` | output-size依存resourceをframe外で準備 |
| `encode(frame:to:commandBuffer:)` | destination全pixelを定義するGPU workをencode |
| `reset()` | temporal historyだけを初期化 |
| `snapshotState()` | ID／schema付きの将来互換stateを返す |
| `restoreState(_:)` | 対象IDを確認し、既知値を適用、未知値を保持 |
| `setParameterValue(_:identifier:)` | descriptor validationを通して値を適用 |

``MetalEffectInstance/parameterValue(identifier:)``と
``MetalEffectInstance/setParameterValue(_:identifier:)``にはdefault実装があります。

## Parameter update

```swift
try effect.setParameterValue(
    .number(1.2),
    identifier: "contrast"
)
```

呼び出し側は常に`setParameterValue`を使います。
`setStateParameterValue(_:identifier:)`はdefault実装用の低レベルhelperであり、
effect固有処理を迂回する可能性があります。たとえばColor Gradeの`look`は、
effect固有setterを通して初めてstarting look一式が適用されます。

`fileReference` parameterはgeneric setterからassetを読みません。ホストがstable
asset IDを解決し、型付きresource APIへ渡します。Color Gradeでは
``ColorGradeEffect/setLUT(_:)``を使います。

## Encode invariants

- sourceとdestinationは別object
- 2D、single-sample、同じdevice／pixel format／size
- source usageに`.shaderRead`
- destination usageに`.renderTarget`
- effectはdestination全pixelを上書き
- mask外はsourceまたはraw cameraを合成し、undefined／blackにしない
- command bufferをcommit／waitしない
- frame pathでfile I/O、shader compile、texture allocationをしない

直接`effect.encode`を呼ぶより、``MetalEffectGraph``を通す方が安全です。graphは
raw camera、analysis texture、device、aspect ratioを含むframe resource validationを
まとめて実行します。

## State and reset

`reset()`はparameterをdefaultへ戻しません。simulation、feedback、temporal cacheだけを
消します。parameterの初期化は新しいconfiguration／instance、または明示stateで行います。

unknown state keyはsnapshotへ保持し、新しいhostへ戻した時に消えないようにします。

@Links(visualStyle: compactGrid) {
    - <doc:Writing-a-New-Effect>
    - <doc:MetalEffectGraph-Guide>
    - <doc:Render-Lifecycle>
}
