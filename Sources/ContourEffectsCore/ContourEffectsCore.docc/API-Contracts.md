# API契約の全体像
<!-- SPDX-FileCopyrightText: 2026 Daito Manabe -->
<!-- SPDX-License-Identifier: BSD-3-Clause -->

ContourEffectsCoreをホストへ組み込む時の、発見、互換性確認、フレーム入力、状態保存の境界を整理します。

## Coreが担当すること

CoreはFoundationだけを使う値型中心のmoduleです。次の情報をMetal描画や解析backendから分離します。

| 契約 | 主な型 | 用途 |
| --- | --- | --- |
| 発見 | ``EffectDescriptor`` | ID、分類、入力、parameter、依存関係を生成前に列挙 |
| 互換性 | ``HostCapabilities`` | 現在のホストで実行できるかを事前判定 |
| 状態 | ``EffectStateSnapshot`` | presetと将来parameterをlosslessに保存 |
| 時刻 | ``EffectFrameTiming`` | 入力sequence、capture PTS、render時刻を共有 |
| 解析 | ``EffectPoint``ほか | provider固有objectを持ち込まず結果だけを共有 |
| ライブ入力 | ``EffectAudioFeatures``、``EffectPerformanceMacros`` | OSCやaudio engineに依存しない値を共有 |
| 任意依存 | ``SDKDependencyDescriptor`` | install方法とlicenseをUIやmanifestへ提示 |

Coreはeffect instanceを生成せず、cameraを開始せず、解析requestを実行しません。これらのlifecycleはホストが所有します。

## 1. 発見

エフェクトcatalogは、instanceを作る前に``EffectDescriptor``を返します。ホストはdescriptorから次を構築できます。

- effect browserとcategory filter
- parameter UI、OSC/MIDI mapping
- 必須inputと任意inputの解析plan
- 必須dependencyのinstall診断
- preset schemaと互換性表示

descriptorをcatalogへ登録する前に``EffectDescriptor/validate()``を呼びます。空ID、重複parameter、不正なdefault、必須と任意の重複はerrorになります。

## 2. 互換性確認

``HostCapabilities``は、その時点でホストが提供できる入力と依存関係の集合です。

```swift
let capabilities = HostCapabilities(
    availableInputs: [
        .composedColor,
        .rawCameraColor,
        .personMask,
        .audio,
        .performanceMacros,
    ],
    availableDependencies: [.appleVision]
)

let report = capabilities.compatibility(with: descriptor)
if !report.canRun {
    // instance生成前に不足を解決するか、effectを無効にします。
}
```

``EffectCompatibilityReport``は不足理由を分けて保持します。

- ``EffectCompatibilityReport/unsupportedAPIVersion``
- ``EffectCompatibilityReport/missingInputs``
- ``EffectCompatibilityReport/missingRequiredDependencies``
- ``EffectCompatibilityReport/missingOptionalDependencies``

任意dependencyの不足は`canRun`を`false`にしません。エフェクト側は、その機能を使わないfallbackを用意します。

## 3. フレームごとの入力

Coreが定義するframe-level dataは、capture objectやframework objectではなく、コピー可能な値です。

- ``EffectFrameTiming``は入力sequenceと時刻を関連付ける。
- 解析座標は左上原点のsource UVに正規化する。
- landmark配列はjoint順序を固定し、欠損点に``EffectPoint/missing``を使う。
- detection IDは同一source generation内のtrackを識別する。
- 音声とmacroは毎frameのsnapshotとして渡す。

Metal hostがこれらをどのtextureやcommand bufferと組み合わせるかは`ContourEffectsMetal`のframe contractで定義します。

## 4. 状態保存

``EffectStateSnapshot``は1 effect instanceの状態だけを保持します。

```swift
let state = EffectStateSnapshot(
    effectIdentifier: descriptor.id,
    schemaVersion: descriptor.stateSchemaVersion,
    values: [
        "enabled": .bool(true),
        "mix": .number(0.75),
        "palette": .string("tokyo"),
    ]
)

let data = try JSONEncoder().encode(state)
```

``EffectValue``はJSON互換の動的な値です。古いhostは理解できないkeyも保持し、再保存時に捨てない設計にします。

## 5. API version

``ContourEffectsSDK/apiVersion``はCore APIのversionです。``EffectAPIVersion/supports(_:)``はmajorが等しく、host minorがeffect minor以上の時だけ`true`になります。

state schemaはAPI versionとは別です。

- API version: hostとeffect codeの契約
- state schema version: 1 effectの保存値の形式

一方を上げたからといって、もう一方を自動的に上げないでください。

## 実装時の順序

1. descriptorを取得する。
2. descriptorを検証する。
3. host capabilitiesと照合する。
4. 必須解析と任意解析をplanする。
5. effect instanceを生成する。
6. frame dataをimmutable snapshotとして渡す。
7. stateをeffect IDとschema version付きで保存する。

@Links(visualStyle: compactGrid) {
    - <doc:Descriptors-and-Compatibility>
    - <doc:State-and-Versioning>
    - <doc:Analysis-Data-ABI>
    - <doc:Audio-and-Macros>
}
