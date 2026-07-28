// SPDX-FileCopyrightText: 2026 Daito Manabe
// SPDX-License-Identifier: BSD-3-Clause

import ContourEffectsCore
import ContourEffectsMetal
import ExampleSupport
import Foundation
import Metal

private struct ColorLookResult: Codable {
    var identifier: String
    var rawValue: UInt32
    var output: [Float]
    var identityConfiguration: Bool
    var alphaPreserved: Bool
}

private struct ColorLookGalleryReport: Codable {
    var selfCheck: Bool
    var device: String
    var source: [Float]
    var lookCount: Int
    var distinctOutputCount: Int
    var allLookMetadataRetained: Bool
    var monochromeChannelsConverged: Bool
    var results: [ColorLookResult]
}

@main
private enum ColorLookGalleryExample {
    static func main() throws {
        let harness = try MetalExampleHarness()
        let width = 16
        let height = 16
        let usage: MTLTextureUsage = [.shaderRead, .renderTarget]
        let source = try harness.makeTexture(
            pixelFormat: .rgba16Float,
            width: width,
            height: height,
            usage: usage,
            label: "Color Look Gallery Source"
        )
        let destination = try harness.makeTexture(
            pixelFormat: .rgba16Float,
            width: width,
            height: height,
            usage: usage,
            label: "Color Look Gallery Destination"
        )
        let sourceColor: [Float] = [0.23, 0.47, 0.71, 0.64]
        try harness.fillRGBA16(
            source,
            color: SIMD4(
                sourceColor[0],
                sourceColor[1],
                sourceColor[2],
                sourceColor[3]
            )
        )

        let graph = MetalEffectGraph()
        try graph.prepare(
            context: MetalEffectHostContext(device: harness.device)
        )
        try graph.resize(width: width, height: height)

        var results: [ColorLookResult] = []
        var allLookMetadataRetained = true
        for look in ColorGradeLook.allCases {
            var retainedMetadataConfiguration = ColorGradeConfiguration()
            retainedMetadataConfiguration.lutIdentifier =
                "example.gallery.external-lut"
            retainedMetadataConfiguration.lutMix = 0.37
            retainedMetadataConfiguration.lutInputSpace = .linearSRGB
            retainedMetadataConfiguration.applyLook(look)
            allLookMetadataRetained =
                allLookMetadataRetained
                && retainedMetadataConfiguration.lutIdentifier
                    == "example.gallery.external-lut"
                && abs(retainedMetadataConfiguration.lutMix - 0.37)
                    < 0.000_001
                && retainedMetadataConfiguration.lutInputSpace == .linearSRGB

            var configuration = ColorGradeConfiguration()
            configuration.applyLook(look)
            let identityConfiguration = configuration.isIdentity
            let effect = ColorGradeEffect(configuration: configuration)
            try graph.replaceEffects([effect])

            let commandBuffer = try harness.makeCommandBuffer(
                label: "Color Look Gallery \(look)"
            )
            try graph.encode(
                frame: MetalEffectFrame(
                    source: source,
                    timing: EffectFrameTiming(
                        frameIndex: UInt64(look.rawValue),
                        inputSequence: 1,
                        hostTimeNanoseconds: 1_000_000_000,
                        deltaSeconds: 1.0 / 60.0,
                        inputPresentationSeconds: 1,
                        renderPresentationSeconds: 1
                    )
                ),
                to: destination,
                commandBuffer: commandBuffer
            )
            try harness.commitAndWait(commandBuffer)

            let output = try harness.readRGBA16(
                destination,
                x: width / 2,
                y: height / 2
            )
            let alphaPreserved = abs(output[3] - sourceColor[3]) < 0.002
            try exampleRequire(
                output.allSatisfy(\.isFinite),
                "\(look) produced a non-finite component."
            )
            try exampleRequire(
                alphaPreserved,
                "\(look) changed source alpha."
            )
            if look == .neutral {
                try exampleRequire(
                    identityConfiguration,
                    "The neutral look is not an identity configuration."
                )
                try exampleRequire(
                    maximumAbsoluteError(output, sourceColor) < 0.015,
                    "The neutral look changed the source."
                )
            } else {
                try exampleRequire(
                    !identityConfiguration,
                    "\(look) unexpectedly reports an identity configuration."
                )
            }

            results.append(
                ColorLookResult(
                    identifier: String(describing: look),
                    rawValue: look.rawValue,
                    output: output,
                    identityConfiguration: identityConfiguration,
                    alphaPreserved: alphaPreserved
                )
            )
        }

        let outputKeys = results.map { result in
            result.output.prefix(3)
                .map { String(format: "%.3f", $0) }
                .joined(separator: ",")
        }
        let distinctOutputCount = Set(outputKeys).count
        let monochrome = try result(for: .monochrome, in: results)
        let monochromeChannelsConverged =
            abs(monochrome.output[0] - monochrome.output[1]) < 0.003
            && abs(monochrome.output[1] - monochrome.output[2]) < 0.003

        try exampleRequire(
            results.count == ColorGradeLook.allCases.count,
            "Not every ColorGradeLook was rendered."
        )
        try exampleRequire(
            distinctOutputCount == ColorGradeLook.allCases.count,
            "Two ColorGradeLook outputs unexpectedly collapsed together."
        )
        try exampleRequire(
            allLookMetadataRetained,
            "applyLook did not retain external LUT metadata."
        )
        try exampleRequire(
            monochromeChannelsConverged,
            "The monochrome look did not converge RGB channels."
        )

        try emitJSON(
            ColorLookGalleryReport(
                selfCheck: true,
                device: harness.device.name,
                source: sourceColor,
                lookCount: results.count,
                distinctOutputCount: distinctOutputCount,
                allLookMetadataRetained: allLookMetadataRetained,
                monochromeChannelsConverged: monochromeChannelsConverged,
                results: results
            )
        )
    }

    private static func result(
        for look: ColorGradeLook,
        in results: [ColorLookResult]
    ) throws -> ColorLookResult {
        guard let result = results.first(
            where: { $0.rawValue == look.rawValue }
        ) else {
            throw ExampleError("The \(look) result is missing.")
        }
        return result
    }
}
