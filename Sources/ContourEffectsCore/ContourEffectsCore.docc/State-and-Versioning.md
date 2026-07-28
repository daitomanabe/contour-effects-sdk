# 状態保存とversioning
<!-- SPDX-FileCopyrightText: 2026 Daito Manabe -->
<!-- SPDX-License-Identifier: BSD-3-Clause -->

``EffectStateSnapshot``を使い、presetを将来のparameter追加に耐える形で保存します。

## 2種類のversion

ContourEffectsには目的が異なる2種類のversionがあります。

### API version

``EffectAPIVersion``はhostとeffect codeの公開契約です。

```swift
let hostVersion = ContourEffectsSDK.apiVersion
let canLoad = hostVersion.supports(effectDescriptor.apiVersion)
```

``EffectAPIVersion/supports(_:)``はmajorが一致し、host minorがeffect minor以上の場合に`true`です。互換性確認には通常、``HostCapabilities/compatibility(with:)``を使います。

### State schema version

``EffectDescriptor/stateSchemaVersion``と``EffectStateSnapshot/schemaVersion``は、1 effectの保存値の形式を表します。parameterのrename、分割、単位変更など、migrationが必要な時に更新します。

APIを変えずにstate schemaだけを更新することも、その逆も可能です。

## EffectValue

``EffectValue``はJSONでround tripできる動的な値です。`.number`にはJSONが扱える
finiteな`Double`だけを保存します。`NaN`と正負のinfinityは保存しません。

- ``EffectValue/null``
- ``EffectValue/bool(_:)``
- ``EffectValue/number(_:)``
- ``EffectValue/string(_:)``
- ``EffectValue/array(_:)``
- ``EffectValue/object(_:)``

```swift
let values: [String: EffectValue] = [
    "enabled": .bool(true),
    "amount": .number(0.65),
    "palette": .string("magma"),
    "center": .array([.number(0.5), .number(0.5)]),
]
```

``EffectValue/boolValue``、``EffectValue/numberValue``、``EffectValue/stringValue``は型が一致した場合だけ値を返します。暗黙の型変換は行いません。

## Snapshotを保存する

```swift
let snapshot = EffectStateSnapshot(
    effectIdentifier: descriptor.id,
    schemaVersion: descriptor.stateSchemaVersion,
    values: values
)

let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]
let data = try encoder.encode(snapshot)
```

preset全体は複数のsnapshotとhost側のrouting情報を組み合わせて構成できます。Coreはpreset file layoutを固定せず、1 effectのstate境界だけを定義します。

## 復元手順

1. `effectIdentifier`で対象effectを解決する。
2. API compatibilityを確認する。
3. `schemaVersion`を確認する。
4. 必要なmigrationを古いversionから順番に適用する。
5. 各既知parameterをdescriptorで検証する。
6. 未知keyを別領域に保持する。
7. 次回保存時に未知keyを既知keyと再統合する。

effect IDが違うsnapshotを別effectへ適用しません。

## 未知値を保持する理由

新しいeffectがparameterを追加した後でpresetを古いhostが開くことがあります。古いhostが未知keyを削除すると、新しいhostへ戻った時に設定が失われます。

``EffectValue``はこのround tripを可能にします。古いhostは理解できる値だけをUIへ出し、理解できない値もsnapshot内には残します。

## Parameterとの対応

snapshotのkeyは``EffectParameterDescriptor/identifier``と一致させます。

```swift
for parameter in descriptor.parameters {
    if let value = snapshot.values[parameter.identifier] {
        try parameter.validate(value: value)
    }
}
```

`fileReference`には移動可能なasset IDを保存します。絶対path、security-scoped bookmark、実textureはhostのasset layerで管理します。

## Migrationの原則

- migrationは決定論的にする。
- 元snapshotを破壊する前に新しいdictionaryを作る。
- 未知keyを削除しない。
- schema versionを黙って下げない。
- migrationに失敗したら一部だけ適用せず、元stateを保持する。
- default追加だけなら古いsnapshotへkeyを書き込まず、読込時にdescriptor defaultを使う方法も検討する。

@Links(visualStyle: compactGrid) {
    - <doc:API-Contracts>
    - <doc:Descriptors-and-Compatibility>
    - <doc:Audio-and-Macros>
}
