# 任意依存関係のmetadata
<!-- SPDX-FileCopyrightText: 2026 Daito Manabe -->
<!-- SPDX-License-Identifier: BSD-3-Clause -->

解析modelや外部SDKをCoreへlinkせず、必要なinstall情報だけを機械可読に扱います。

## Dependency registry

``ContourEffectsDependencies/all``は``SDKDependencyDescriptor``の一覧です。

```swift
for dependency in ContourEffectsDependencies.all {
    print(dependency.displayName)
    print(dependency.distribution.rawValue)
    print(dependency.license)
    print(dependency.installSummary)
}
```

特定IDは``ContourEffectsDependencies/descriptor(for:)``で取得できます。

```swift
let syphon = ContourEffectsDependencies.descriptor(for: .syphon)
```

registryと``ContourEffectsDependencyID``は一緒に管理されます。既知IDにdescriptorがない場合、`descriptor(for:)`はfail-fastします。

## 現在のdependency IDs

| ID | 役割 | Distribution |
| --- | --- | --- |
| ``ContourEffectsDependencyID/appleVision`` | person、hand、body、scene解析 | ``SDKDependencyDistribution/systemFramework`` |
| ``ContourEffectsDependencyID/appleCoreML`` | on-device model inference | ``SDKDependencyDistribution/systemFramework`` |
| ``ContourEffectsDependencyID/yoloV3TinyCoreML`` | object detection | ``SDKDependencyDistribution/modelResource`` |
| ``ContourEffectsDependencyID/depthAnythingV2SmallCoreML`` | relative depth | ``SDKDependencyDistribution/modelResource`` |
| ``ContourEffectsDependencyID/glicMetal`` | optional glitch lanes | ``SDKDependencyDistribution/xcframeworkAndResources`` |
| ``ContourEffectsDependencyID/syphon`` | final texture sharing | ``SDKDependencyDistribution/framework`` |

metadataへ名前があることは、そのframeworkやmodelがCoreへlink、download、bundleされることを意味しません。

## Descriptorの内容

``SDKDependencyDescriptor``は次を保持します。

- stable ``SDKDependencyDescriptor/id``
- UI用``SDKDependencyDescriptor/displayName``
- effectに対する役割
- ``SDKDependencyDescriptor/distribution``
- 必須か任意か
- license名
- sourceまたは公式documentationのURL
- host向けinstall summary

この情報はdependency browser、missing capability UI、distribution manifestに利用できます。実際のartifact hashや署名状態など、release固有情報はhost側のmanifestで管理します。

## Effect descriptorへ宣言する

``EffectDescriptor/requiredDependencies``はeffectの成立に必須、``EffectDescriptor/optionalDependencies``はfallback可能な機能です。

```swift
let descriptor = EffectDescriptor(
    id: "com.example.vj.person-prism",
    displayName: "Person Prism",
    category: .analysis,
    requiredInputs: [.composedColor, .personMask],
    requiredDependencies: [.appleVision],
    optionalDependencies: [.syphon]
)

try descriptor.validate()
```

同じdependencyを必須と任意の両方へ入れると``EffectDescriptor/validate()``が失敗します。

## Hostへ能力を登録する

hostが実際に初期化できたdependencyだけを``HostCapabilities/availableDependencies``へ入れます。

```swift
let host = HostCapabilities(
    availableInputs: [.composedColor, .personMask],
    availableDependencies: [.appleVision]
)

let report = host.compatibility(with: descriptor)
```

install済みでもmodel loadやframework初期化に失敗した場合はavailableにしません。fileの存在だけを能力判定に使わないでください。

## License boundary

``SDKDependencyDescriptor/license``は第三者componentのlicense表示です。ContourEffectsのBSD-3-Clauseが第三者componentを再licenseすることはありません。

hostが任意componentを配布する場合は、それぞれのnotice、artifact、署名、model licenseを別に確認します。Core/Metalだけを使うhostは、使わないcomponentを追加する必要はありません。

## 設計上の注意

- dependency IDをparameterやeffect IDの代用にしない。
- runtime objectを``SDKDependencyDescriptor``へ格納しない。
- secret、local absolute path、credentialをmetadataへ入れない。
- optional dependencyがない時の視覚fallbackをeffect側で明示する。
- license名だけでなく、配布時は正式なlicense本文とnoticeを同梱する。

@Links(visualStyle: compactGrid) {
    - <doc:Descriptors-and-Compatibility>
    - <doc:API-Contracts>
    - <doc:Analysis-Data-ABI>
}
