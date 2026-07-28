// SPDX-FileCopyrightText: 2026 Daito Manabe
// SPDX-License-Identifier: BSD-3-Clause

import ContourEffectsCore
import ContourEffectsMetal
import ExampleSupport
import Foundation
import Metal

private struct LUTRenderReport: Codable {
    var selfCheck: Bool
    var device: String
    var lutTitle: String
    var lutSize: Int
    var source: [Float]
    var output: [Float]
    var expected: [Float]
    var maximumError: Float
    var alphaPreserved: Bool
    var malformedLUTRejected: Bool
}

@main
private enum LUTRenderExample {
    private static let authoredSwapRedBlueLUT = """
    TITLE "ContourEffects Example Swap Red Blue"
    LUT_3D_SIZE 2
    DOMAIN_MIN 0 0 0
    DOMAIN_MAX 1 1 1
    0 0 0
    0 0 1
    0 1 0
    0 1 1
    1 0 0
    1 0 1
    1 1 0
    1 1 1
    """

    static func main() throws {
        let harness = try MetalExampleHarness()
        let cube = try CubeLUT.parse(authoredSwapRedBlueLUT)
        let metalLUT = try MetalLUT3D(
            identifier: "example.swap-red-blue",
            cube: cube,
            device: harness.device
        )

        var configuration = ColorGradeConfiguration()
        configuration.lutMix = 1
        configuration.lutInputSpace = .displayRGB
        let effect = ColorGradeEffect(configuration: configuration)
        effect.setLUT(metalLUT)
        effect.configuration.lutMix = 1

        let graph = MetalEffectGraph(effects: [effect])
        try graph.prepare(
            context: MetalEffectHostContext(device: harness.device)
        )
        try graph.resize(width: 8, height: 8)

        let usage: MTLTextureUsage = [.shaderRead, .renderTarget]
        let source = try harness.makeTexture(
            pixelFormat: .rgba16Float,
            width: 8,
            height: 8,
            usage: usage,
            label: "LUT Example Source"
        )
        let destination = try harness.makeTexture(
            pixelFormat: .rgba16Float,
            width: 8,
            height: 8,
            usage: usage,
            label: "LUT Example Destination"
        )
        let sourceColor: [Float] = [0.2, 0.4, 0.8, 0.625]
        try harness.fillRGBA16(
            source,
            color: SIMD4(
                sourceColor[0],
                sourceColor[1],
                sourceColor[2],
                sourceColor[3]
            )
        )

        let commandBuffer = try harness.makeCommandBuffer(
            label: "ContourEffects LUT Example"
        )
        try graph.encode(
            frame: MetalEffectFrame(
                source: source,
                timing: EffectFrameTiming(
                    frameIndex: 0,
                    inputSequence: 1,
                    hostTimeNanoseconds: DispatchTime.now().uptimeNanoseconds,
                    deltaSeconds: 1.0 / 60.0,
                    inputPresentationSeconds: 0,
                    renderPresentationSeconds: 0
                )
            ),
            to: destination,
            commandBuffer: commandBuffer
        )
        try harness.commitAndWait(commandBuffer)

        let output = try harness.readRGBA16(destination)
        let expected: [Float] = [
            sourceColor[2],
            sourceColor[1],
            sourceColor[0],
            sourceColor[3],
        ]
        let maximumError = maximumAbsoluteError(output, expected)
        let alphaPreserved = abs(output[3] - sourceColor[3]) < 0.002

        var malformedLUTRejected = false
        do {
            _ = try CubeLUT.parse(
                "LUT_3D_SIZE 2\n0 0 0\n1 0 0\n"
            )
        } catch let error as CubeLUTError {
            if case .sampleCount = error {
                malformedLUTRejected = true
            }
        }

        try exampleRequire(
            output.allSatisfy(\.isFinite),
            "The LUT output contains a non-finite component."
        )
        try exampleRequire(
            maximumError < 0.015,
            "The authored LUT produced an unexpected output."
        )
        try exampleRequire(alphaPreserved, "The LUT changed source alpha.")
        try exampleRequire(
            malformedLUTRejected,
            "The malformed LUT was not rejected."
        )

        try emitJSON(
            LUTRenderReport(
                selfCheck: true,
                device: harness.device.name,
                lutTitle: cube.title,
                lutSize: cube.size,
                source: sourceColor,
                output: output,
                expected: expected,
                maximumError: maximumError,
                alphaPreserved: alphaPreserved,
                malformedLUTRejected: malformedLUTRejected
            )
        )
    }
}
