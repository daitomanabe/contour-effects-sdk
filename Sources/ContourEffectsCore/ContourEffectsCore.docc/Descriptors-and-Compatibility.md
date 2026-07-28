# Descriptorと互換性
<!-- SPDX-FileCopyrightText: 2026 Daito Manabe -->
<!-- SPDX-License-Identifier: BSD-3-Clause -->

``EffectDescriptor``を、UI metadataではなく実行前contractとして扱う方法を説明します。

## 安定した識別子

``EffectIdentifier``はeffect state、catalog、automationの結合点です。公開後は表示名を変更してもIDを変更しません。

```swift
let identifier: EffectIdentifier =
    "com.example.contour-effects.color.soft-print"
```

parameterの``EffectParameterDescriptor/identifier``も同様に、保存値とcontrol mappingのkeyになります。ラベルの翻訳や改善では``EffectParameterDescriptor/displayName``だけを変更します。

## Descriptorを構築する

```swift
let mix = EffectParameterDescriptor(
    identifier: "mix",
    displayName: "Mix",
    kind: .float,
    defaultValue: .number(1),
    minimum: 0,
    maximum: 1,
    unit: "%",
    smoothingTime: 0.08,
    isAutomatable: true,
    midiAssignable: true,
    oscAddress: "/effect/mix"
)

let descriptor = EffectDescriptor(
    id: "com.example.contour-effects.color.soft-print",
    displayName: "Soft Print",
    apiVersion: .v1,
    stateSchemaVersion: 1,
    category: .color,
    executionModel: .stateless,
    requiredInputs: [.composedColor],
    optionalInputs: [.audio],
    synchronizationPolicy: .latestLowLatency,
    parameters: [mix],
    requiredDependencies: [],
    optionalDependencies: []
)

try descriptor.validate()
```

``EffectCategory``はbrowser上の分類、``EffectExecutionModel``はstateの性質、``EffectSynchronizationPolicy``はanalysisとsourceの合わせ方を表します。

## Parameter validation

値をeffectへ適用する前に``EffectParameterDescriptor/validate(value:)``を呼びます。

```swift
try mix.validate(value: .number(0.5))
```

validationはkindに応じて次を確認します。

| Kind | 検証 |
| --- | --- |
| `float` | finite numberとmin/max |
| `integer` | finite number、整数、min/max |
| `boolean` / `trigger` | ``EffectValue/bool(_:)`` |
| `enumeration` | defaultと同じstorage型、重複のないchoice ID |
| `color` | finite number 3または4要素 |
| `vector2` | finite number 2要素 |
| `fileReference` | stable string IDまたは`null` |

`fileReference`は任意pathをeffectが直接読む指示ではありません。ホストがasset IDを解決し、適切なresource objectをeffectへ渡します。

## Descriptor validation

``EffectDescriptor/validate()``は次を拒否します。

- 空のeffect ID
- 必須inputと任意inputの重複
- 必須dependencyと任意dependencyの重複
- 空または重複したparameter ID
- 両方が指定された時の非finite、または大小が逆のmin/max
- 宣言範囲外または型不一致のdefault
- choiceが空、またはchoice IDが重複したenumeration

失敗は``EffectDescriptorValidationError``、個別値の失敗は``EffectParameterValidationError``です。catalog作成時のerrorは開発時に修正し、ライブ描画中のfallbackにしません。

## Input requirements

``EffectInputRequirements``は`OptionSet`です。

- `.composedColor`: 現在の合成映像
- `.rawCameraColor`: feedbackを含まないcamera映像
- `.edge` / `.opticalFlow` / `.featurePoints`
- `.personMask` / `.silhouetteContour`
- `.handLandmarks` / `.bodyLandmarks`
- `.sceneMask` / `.objectDetections` / `.depth`
- `.audio` / `.performanceMacros`

effectがなくても動く入力は`optionalInputs`へ置きます。必須にすると、``HostCapabilities``が不足を検出しinstance生成前に止められます。

## Host compatibility

```swift
let host = HostCapabilities(
    availableInputs: [.composedColor, .audio],
    availableDependencies: []
)
let report = host.compatibility(with: descriptor)

if report.canRun {
    // effect instanceを生成できます。
} else {
    print(report.missingInputs.rawValue)
}
```

``EffectCompatibilityReport/canRun``は次の3条件で決まります。

1. ``EffectAPIVersion``がsupport範囲内
2. 必須inputがすべてavailable
3. 必須dependencyがすべてavailable

``EffectCompatibilityReport/missingOptionalDependencies``はdiagnosticやfeature badgeに使います。任意機能だけが欠けている場合は実行できます。

## Availabilityと観測数を分ける

handやobject detectorが正常に動作しても、あるframeでは観測が0件になることがあります。provider availabilityを「配列が空ではないこと」で表現しないでください。

Coreの``HostCapabilities``はhost全体の能力を表します。frameごとのprovider availabilityと観測配列はMetal frame contractで別に扱います。

@Links(visualStyle: compactGrid) {
    - <doc:API-Contracts>
    - <doc:Dependency-Metadata>
    - <doc:State-and-Versioning>
}
