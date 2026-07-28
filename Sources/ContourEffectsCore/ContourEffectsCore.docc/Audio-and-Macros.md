# AudioとPerformance Macros
<!-- SPDX-FileCopyrightText: 2026 Daito Manabe -->
<!-- SPDX-License-Identifier: BSD-3-Clause -->

入力transportから独立した音響featureと、8つのsemantic macroをeffectへ渡します。

## Audio transportを分離する

``EffectAudioFeatures``はOSC、system audio、host内部解析のどれからでも生成できます。``EffectAudioSource``は現在値の出所を示します。

- ``EffectAudioSource/none``: 有効なsourceなし
- ``EffectAudioSource/host``: hostが直接供給
- ``EffectAudioSource/system``: system audio input
- ``EffectAudioSource/osc``: OSCなど外部transport

Coreはport、socket、audio deviceを開始しません。

## Audio snapshot

```swift
let audio = EffectAudioFeatures(
    source: .osc,
    isLive: true,
    volume: 0.72,
    low: 0.81,
    mid: 0.48,
    high: 0.35,
    beat: 1,
    attack: 0.9,
    spectrum: fftBands,
    timestamp: currentTime
).clamped()
```

``EffectAudioFeatures/clamped(maximumBandCount:)``はvolume、low、mid、high、beat、attack、spectrumをfiniteな`0...1`へ制限し、band数を既定で最大128にします。NaNやinfinityは0になります。

``EffectAudioFeatures/zero``は安全な無音値です。

### Freshness

``EffectAudioFeatures/isLive``と``EffectAudioFeatures/timestamp``を使ってstaleな入力を判定するのはホストです。値が最後に非0だったことだけでliveと判断しません。

transportが途切れた場合は、ホストのpolicyに従ってsmoothに``EffectAudioFeatures/zero``へ戻します。

## 8つのsemantic macro

``EffectPerformanceMacros``はeffect固有parameterを直接操作するのではなく、異なるeffect間で意味を揃えた8 controlです。

| Macro | 意味 |
| --- | --- |
| `energy` | emission、scale、brightness、生成量など全体の勢い |
| `motion` | velocity、rotation、camera、deformationなど動きの大きさ |
| `density` | particle、line、objectなど情報量 |
| `audioReactive` | audio modulation、beat、attackへの反応強度 |
| `color` | hue、saturation、palette、temperature |
| `glitch` | split、compression、noiseなど破壊量 |
| `feedback` | trail、decay、recursive accumulation |
| `texture` | grain、blur、edge、CRTなど表面の質感 |

```swift
let macros = EffectPerformanceMacros(
    energy: 0.8,
    motion: 0.6,
    density: 0.45,
    audioReactive: 1,
    color: 0.3,
    glitch: 0,
    feedback: 0.2,
    texture: 0.5
).clamped()
```

``EffectPerformanceMacros/clamped()``は全macroをfiniteな`0...1`へ制限します。``EffectPerformanceMacros/zero``はneutralな初期値です。

## Effect側のmapping

macro値を全parameterへ同じ係数で掛けるのではなく、descriptorとeffectの視覚的意味に合わせてmappingします。

```swift
let effectiveDensity =
    baseDensity * (0.5 + Double(macros.density))
let motionGain =
    baseMotion * Double(macros.motion)
```

実装時は次を守ります。

1. macroが0でも意図したbase lookを保持する。
2. macroが上がると何が変わるかをeffect manualへ記載する。
3. brightnessだけではなく、motionやtopologyを対応するmacroへ接続する。
4. parameterの保存値は変更せず、frameごとのeffective valueを計算する。
5. `.clamped()`後のsnapshotを描画queueへ渡す。

## Audioとmacroを組み合わせる

`audioReactive`は音量そのものではなく、effect内部の音反応量を調整するsemantic controlです。

```swift
let audioAmount =
    audio.volume * macros.audioReactive
let transient =
    max(audio.beat, audio.attack) * macros.audioReactive
```

`volume == 0`の時にeffect output全体のalphaを0へ落とすとは限りません。通常はdryなbase lookを残し、音が強い時にmotion、deformation、spawn、mixなどを増やします。

## Availability

descriptorが`.audio`や`.performanceMacros`を必須inputにするかはeffectのfallback方針で決めます。

- 音なしでも動く: `optionalInputs`
- 音がなければ意味が成立しない: `requiredInputs`

zero値とinput unavailableは別の状態です。availabilityはhost contractで明示します。

@Links(visualStyle: compactGrid) {
    - <doc:API-Contracts>
    - <doc:Descriptors-and-Compatibility>
    - <doc:Analysis-Data-ABI>
}
