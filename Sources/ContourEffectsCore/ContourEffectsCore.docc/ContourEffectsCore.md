# ``ContourEffectsCore``
<!-- SPDX-FileCopyrightText: 2026 Daito Manabe -->
<!-- SPDX-License-Identifier: BSD-3-Clause -->

エフェクトを発見・検証・保存し、映像解析やライブ入力をホストと共有するための、Metalに依存しない共通契約です。

## Overview

ContourEffectsCoreは、エフェクトの描画実装ではなく、ホストアプリとエフェクトが合意するデータ形式を提供します。主要な役割は次のとおりです。

- ``EffectDescriptor``によるエフェクトとパラメーターの発見
- ``HostCapabilities``による実行前の互換性判定
- ``EffectStateSnapshot``と``EffectValue``による将来互換の状態保存
- ``EffectFrameTiming``による入力フレームと描画フレームの時刻共有
- ``EffectPoint``、``EffectLandmarkSet``、``EffectObjectDetection``による解析結果の交換
- ``EffectAudioFeatures``と``EffectPerformanceMacros``によるライブ制御
- ``ContourEffectsDependencies``による任意依存関係の機械可読な説明

Core自体はVision、Core ML、YOLO、Depth Anything、GLIC、Syphonをリンクしません。ホストは必要な解析器や外部SDKだけを選び、その結果をCoreの値型へ変換します。

@Links(visualStyle: detailedGrid) {
    - <doc:API-Contracts>
    - <doc:Descriptors-and-Compatibility>
    - <doc:State-and-Versioning>
    - <doc:Analysis-Data-ABI>
    - <doc:Audio-and-Macros>
    - <doc:Dependency-Metadata>
}

## 最小の発見と互換性確認

ホストはエフェクトを生成する前にdescriptorを検証し、利用可能な入力と依存関係を照合します。

```swift
import ContourEffectsCore

let descriptor = EffectDescriptor(
    id: "com.example.vj.soft-color",
    displayName: "Soft Color",
    category: .color,
    requiredInputs: [.composedColor]
)

try descriptor.validate()

let host = HostCapabilities(
    availableInputs: [.composedColor, .audio],
    availableDependencies: []
)
let report = host.compatibility(with: descriptor)

guard report.canRun else {
    // missingInputs、missingRequiredDependencies、
    // unsupportedAPIVersionをUIやログへ提示します。
    return
}
```

``EffectCompatibilityReport/canRun``は、API version、必須入力、必須依存がすべて満たされた場合だけ`true`です。任意依存の欠落は``EffectCompatibilityReport/missingOptionalDependencies``へ報告されますが、それだけでは実行を禁止しません。

## ホストが守る境界

1. エフェクトIDとパラメーターIDは保存後に変更しない。
2. descriptorは``EffectDescriptor/validate()``で検証してから公開する。
3. 値を適用する前に``EffectParameterDescriptor/validate(value:)``で型と値域を検証する。
4. 解析座標は左上原点のsource UVへ統一する。
5. 空の検出結果と、解析provider自体が利用できない状態を区別する。
6. 保存時は未知の``EffectValue``を失わず、effect IDとschema versionを保持する。
7. 音声とmacroは``EffectAudioFeatures/clamped(maximumBandCount:)``、``EffectPerformanceMacros/clamped()``で有限な`0...1`へ正規化する。

描画queue、Metal texture、command bufferの契約は`ContourEffectsMetal` moduleが担当します。

## Topics

### SDKとversion

- ``ContourEffectsSDK``
- ``EffectAPIVersion``

### エフェクト記述

- ``EffectIdentifier``
- ``EffectDescriptor``
- ``EffectCategory``
- ``EffectExecutionModel``
- ``EffectSynchronizationPolicy``
- ``EffectInputRequirements``

### パラメーター

- ``EffectParameterDescriptor``
- ``EffectParameterChoice``
- ``EffectParameterValueKind``
- ``EffectParameterValidationError``
- ``EffectDescriptorValidationError``

### 互換性

- ``HostCapabilities``
- ``EffectCompatibilityReport``

### 状態と時刻

- ``EffectValue``
- ``EffectStateSnapshot``
- ``EffectFrameTiming``

### 解析データ

- ``EffectPoint``
- ``EffectRect``
- ``EffectLandmarkSet``
- ``EffectHandJoint``
- ``EffectBodyJoint``
- ``EffectObjectDetection``

### ライブ制御

- ``EffectAudioSource``
- ``EffectAudioFeatures``
- ``EffectPerformanceMacros``

### 任意依存

- ``ContourEffectsDependencyID``
- ``SDKDependencyDistribution``
- ``SDKDependencyDescriptor``
- ``ContourEffectsDependencies``
