# CubeLUT and MetalLUT3D
<!-- SPDX-FileCopyrightText: 2026 Daito Manabe -->
<!-- SPDX-License-Identifier: BSD-3-Clause -->

`.cube` fileを検証済みのCPU valueへ変換し、特定device用の3D Metal textureへuploadします。

## Parse or load

```swift
let fromFile = try CubeLUT.load(from: url)
let fromText = try CubeLUT.parse(cubeText)
```

``CubeLUT``が受け付ける形式:

- `LUT_3D_SIZE 2...64`
- optional `TITLE`
- optional `DOMAIN_MIN`／`DOMAIN_MAX`
- redが最も速く変化し、次にgreen、blueとなる標準3D sample order
- finiteで`Float16`表現可能なRGB sample
- size³と完全に一致するsample数

1D LUTは``CubeLUTError/unsupportedOneDimensional``です。

## Upload

```swift
let lut = try MetalLUT3D(
    identifier: "com.example.look.warm-v2",
    cube: fromFile,
    device: device
)
```

``MetalLUT3D``はidentifier、`rgba16Float` 3D texture、domainを保持します。
identifierには絶対pathではなく、host asset libraryで安定したIDを使います。

既に3D textureを管理しているhostは、検証付きinitializerも使えます。

```swift
let lut = try MetalLUT3D(
    identifier: stableID,
    texture: texture,
    domainMinimum: SIMD3(repeating: 0),
    domainMaximum: SIMD3(repeating: 1)
)
```

textureはcubic、size 2以上、`rgba16Float`、`.shaderRead`である必要があります。

## Input color space

`.cube`自体には信頼できるcolor-space metadataがありません。host UIまたはasset
metadataで``LUTInputSpace``を選びます。

- ``LUTInputSpace/displayRGB``: input/outputともdisplay-referred sRGB
- ``LUTInputSpace/linearSRGB``: lookup前にlinearへ変換し、LUT outputをlinearとして
  display sRGBへ戻す

誤ったinput spaceを選ぶとcontrastと中間色が変わります。LUTの配布元が示す想定空間を
asset metadataとして保存します。

## Asset lifecycle

1. security-scoped URLなどhost固有方法でfileへaccessする。
2. frame path外で``CubeLUT/load(from:)``する。
3. prepared deviceで``MetalLUT3D``を生成する。
4. render queue上で``ColorGradeEffect/setLUT(_:)``する。
5. stateにはstable identifier、mix、input spaceだけを保存する。
6. source変更やdevice変更では新deviceへ再uploadする。

User-imported LUTのlicenseと再配布権はhost／operatorの責任です。

## Failures

``CubeLUTError``はfile unreadable、size、domain、sample、count、texture allocationを
区別します。無効なLUTを部分適用せず、以前の有効LUTを保持するかLUTなしへfallbackします。

@Links(visualStyle: compactGrid) {
    - <doc:ColorGradeEffect-Guide>
    - <doc:Render-Lifecycle>
}
