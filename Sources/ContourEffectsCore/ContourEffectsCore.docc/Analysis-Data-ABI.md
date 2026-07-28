# 解析データABI
<!-- SPDX-FileCopyrightText: 2026 Daito Manabe -->
<!-- SPDX-License-Identifier: BSD-3-Clause -->

VisionやCore MLなどprovider固有のobjectをrender側へ渡さず、正規化した値型へ変換するためのABIです。

## 共通座標

解析座標はsource映像のUVへ正規化します。

- 原点: 左上
- X: 右方向が正
- Y: 下方向が正
- 可視範囲: `0...1`

解析前のcamera orientation、crop、mirrorをproviderごとに別管理せず、hostが同じsource座標へ揃えます。

## Point

``EffectPoint``は位置とconfidenceを持ちます。

```swift
let point = EffectPoint(x: 0.25, y: 0.4, confidence: 0.92)
guard point.isValid else { return }
```

``EffectPoint/isValid``はX、Y、confidenceがfiniteかつ`0...1`の場合だけ`true`です。固定順序のlandmarkでjointが見つからない時は``EffectPoint/missing``を使い、配列長を変えません。

## Rectangle

``EffectRect``は左上のX/Yとwidth/heightをsource UVで表します。

```swift
let box = EffectRect(x: 0.1, y: 0.15, width: 0.3, height: 0.6)
```

型自体は値域をclampしません。ホストはfiniteな値を供給し、rectangleを`0...1`内へ収めます。

## Landmark set

``EffectLandmarkSet``はtracked subjectのstable IDと固定順序のpoint配列です。

### Hand

handは``EffectHandJoint``の`rawValue`順で21点です。wristから始まり、thumb、index、middle、ring、littleの各jointが続きます。

```swift
var hand = [EffectPoint](
    repeating: .missing,
    count: EffectHandJoint.allCases.count
)
hand[EffectHandJoint.indexTip.rawValue] =
    EffectPoint(x: 0.62, y: 0.28, confidence: 0.9)

let landmarks = EffectLandmarkSet(id: "hand-left-0", points: hand)
```

### Body

bodyは``EffectBodyJoint``の`rawValue`順で19点です。root、顔、肩、肘、手首、hip、knee、ankleを含みます。

配列要素数とjoint orderはABIです。providerが返す順序をそのまま渡さず、hostでこの順序へ変換します。

## Object detection

``EffectObjectDetection``はtrack ID、label、confidence、bounding box、velocityを持ちます。

```swift
let detection = EffectObjectDetection(
    id: 42,
    label: "person",
    confidence: 0.88,
    boundingBox: box,
    velocityX: 0.012,
    velocityY: -0.004
)
```

IDは同一source generation内でtrackが続く間stableにし、track loss後に同じIDを再利用しません。

velocityは、source UV上の変位をinput-sequence deltaで割った値です。

- `velocityX > 0`: 右へ移動
- `velocityY > 0`: 下へ移動

frameが複数skipされた場合もsequence差で割り、1 input frameあたりの移動量へ揃えます。

## Timingとの対応

``EffectFrameTiming/inputSequence``は解析元capture frameを識別します。providerが非同期でも、結果に元sequenceを保持します。

``EffectSynchronizationPolicy/latestLowLatency``では、hostがstale limit内の最新snapshotを選べます。``EffectSynchronizationPolicy/analysisMatchedFrame``では、sourceと同じsequenceの解析結果を使います。

`inputSequence == 0`は、hostがcapture frameを識別できないことを表します。

## Provider availability

観測配列が空であることは正常な解析結果です。

- provider unavailable: 能力またはframe inputが提供されていない
- provider available、観測0件: 解析は完了したが対象がいない
- provider available、観測あり: 値配列を利用できる

``HostCapabilities``はホスト全体の能力を表します。frame単位のavailabilityはrender contract側で明示し、配列の件数だけから推測しません。

## Validation checklist

- 全floatがfinite
- pointとconfidenceが`0...1`
- rectangleがsource UV内
- hand 21点、body 19点の固定順序
- missing jointは``EffectPoint/missing``
- track IDはgeneration内でstable
- velocityはsequence deltaで正規化
- analysis source sequenceと時刻を保持

@Links(visualStyle: compactGrid) {
    - <doc:API-Contracts>
    - <doc:Descriptors-and-Compatibility>
    - <doc:Audio-and-Macros>
}
