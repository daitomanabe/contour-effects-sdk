// SPDX-FileCopyrightText: 2026 Daito Manabe
// SPDX-License-Identifier: BSD-3-Clause

import ContourEffectsCore
import ContourEffectsMetal
import ExampleSupport
import Foundation
import Metal

private struct GraphLifecycleChecks: Codable {
    var alphaPreserved: Bool
    var emptyPassThrough: Bool
    var encodeBeforePrepareRejected: Bool
    var inPlaceRejected: Bool
    var replacementApplied: Bool
    var resizeMismatchRejected: Bool
    var twoEffectChainApplied: Bool
}

private struct GraphLifecycleReport: Codable {
    var selfCheck: Bool
    var device: String
    var size: [Int]
    var source: [Float]
    var twoEffectOutput: [Float]
    var replacementOutput: [Float]
    var passThroughOutput: [Float]
    var effectCounts: [Int]
    var checks: GraphLifecycleChecks
}

@main
private enum GraphLifecycleExample {
    private static let width = 4
    private static let height = 4
    private static let sourceColor: [Float] = [0.18, 0.42, 0.76, 0.375]
    private static let tolerance: Float = 0.002

    static func main() throws {
        let harness = try MetalExampleHarness()
        let textureUsage: MTLTextureUsage = [.shaderRead, .renderTarget]
        let source = try makeColorTexture(
            harness: harness,
            width: width,
            height: height,
            usage: textureUsage,
            label: "Graph Lifecycle Source"
        )
        let destination = try makeColorTexture(
            harness: harness,
            width: width,
            height: height,
            usage: textureUsage,
            label: "Graph Lifecycle Destination"
        )
        try harness.fillRGBA16(
            source,
            color: SIMD4(
                sourceColor[0],
                sourceColor[1],
                sourceColor[2],
                sourceColor[3]
            )
        )

        let encodeBeforePrepareRejected = try checkEncodeBeforePrepare(
            harness: harness,
            source: source,
            destination: destination
        )

        var firstConfiguration = ColorGradeConfiguration()
        firstConfiguration.exposure = 0.18
        firstConfiguration.contrast = 1.08
        var secondConfiguration = ColorGradeConfiguration()
        secondConfiguration.saturation = 0.62
        secondConfiguration.temperature = -0.12

        let graph = MetalEffectGraph(
            effects: [
                ColorGradeEffect(configuration: firstConfiguration),
                ColorGradeEffect(configuration: secondConfiguration),
            ]
        )
        let initialEffectCount = graph.effects.count
        try graph.prepare(
            context: MetalEffectHostContext(device: harness.device)
        )
        try graph.resize(width: width, height: height)

        let twoEffectOutput = try render(
            graph: graph,
            harness: harness,
            source: source,
            destination: destination,
            sequence: 1,
            label: "Graph Lifecycle Two Effects"
        )
        let twoEffectChainApplied =
            maximumAbsoluteError(
                Array(twoEffectOutput.prefix(3)),
                Array(sourceColor.prefix(3))
            ) > 0.01

        let resizeMismatchRejected = try checkResizeMismatch(
            graph: graph,
            harness: harness
        )
        let inPlaceRejected = try checkInPlaceEncoding(
            graph: graph,
            harness: harness,
            source: source
        )

        var replacementConfiguration = ColorGradeConfiguration()
        replacementConfiguration.brightness = 0.12
        replacementConfiguration.saturation = 1
        try graph.replaceEffects([
            ColorGradeEffect(configuration: replacementConfiguration),
        ])
        let replacementEffectCount = graph.effects.count
        let replacementOutput = try render(
            graph: graph,
            harness: harness,
            source: source,
            destination: destination,
            sequence: 2,
            label: "Graph Lifecycle Replacement"
        )
        let replacementApplied =
            maximumAbsoluteError(
                Array(replacementOutput.prefix(3)),
                Array(sourceColor.prefix(3))
            ) > 0.01
                && maximumAbsoluteError(
                    Array(replacementOutput.prefix(3)),
                    Array(twoEffectOutput.prefix(3))
                ) > 0.01

        try graph.replaceEffects([])
        let emptyEffectCount = graph.effects.count
        let passThroughOutput = try render(
            graph: graph,
            harness: harness,
            source: source,
            destination: destination,
            sequence: 3,
            label: "Graph Lifecycle Empty Pass Through"
        )
        let emptyPassThrough =
            maximumAbsoluteError(passThroughOutput, sourceColor) < tolerance
        let alphaPreserved = [
            twoEffectOutput,
            replacementOutput,
            passThroughOutput,
        ].allSatisfy {
            abs($0[3] - sourceColor[3]) < tolerance
        }

        let checks = GraphLifecycleChecks(
            alphaPreserved: alphaPreserved,
            emptyPassThrough: emptyPassThrough,
            encodeBeforePrepareRejected: encodeBeforePrepareRejected,
            inPlaceRejected: inPlaceRejected,
            replacementApplied: replacementApplied,
            resizeMismatchRejected: resizeMismatchRejected,
            twoEffectChainApplied: twoEffectChainApplied
        )
        try exampleRequire(
            checks.encodeBeforePrepareRejected,
            "Encoding before prepare did not report notPrepared."
        )
        try exampleRequire(
            checks.resizeMismatchRejected,
            "A source size that was not resized was accepted."
        )
        try exampleRequire(
            checks.inPlaceRejected,
            "In-place graph encoding was accepted."
        )
        try exampleRequire(
            checks.twoEffectChainApplied,
            "The two-effect graph did not change RGB."
        )
        try exampleRequire(
            checks.replacementApplied,
            "Replacing the graph did not apply the new effect."
        )
        try exampleRequire(
            checks.emptyPassThrough,
            "An empty graph did not copy its source."
        )
        try exampleRequire(
            checks.alphaPreserved,
            "A graph lifecycle operation changed source alpha."
        )

        try emitJSON(
            GraphLifecycleReport(
                selfCheck: true,
                device: harness.device.name,
                size: [width, height],
                source: sourceColor,
                twoEffectOutput: twoEffectOutput,
                replacementOutput: replacementOutput,
                passThroughOutput: passThroughOutput,
                effectCounts: [
                    initialEffectCount,
                    replacementEffectCount,
                    emptyEffectCount,
                ],
                checks: checks
            )
        )
    }

    private static func makeColorTexture(
        harness: MetalExampleHarness,
        width: Int,
        height: Int,
        usage: MTLTextureUsage,
        label: String
    ) throws -> MTLTexture {
        try harness.makeTexture(
            pixelFormat: .rgba16Float,
            width: width,
            height: height,
            usage: usage,
            label: label
        )
    }

    private static func render(
        graph: MetalEffectGraph,
        harness: MetalExampleHarness,
        source: MTLTexture,
        destination: MTLTexture,
        sequence: UInt64,
        label: String
    ) throws -> [Float] {
        let commandBuffer = try harness.makeCommandBuffer(label: label)
        try graph.encode(
            frame: MetalEffectFrame(
                source: source,
                timing: frameTiming(sequence: sequence)
            ),
            to: destination,
            commandBuffer: commandBuffer
        )
        try harness.commitAndWait(commandBuffer)
        return try harness.readRGBA16(destination)
    }

    private static func checkEncodeBeforePrepare(
        harness: MetalExampleHarness,
        source: MTLTexture,
        destination: MTLTexture
    ) throws -> Bool {
        let graph = MetalEffectGraph(effects: [ColorGradeEffect()])
        let commandBuffer = try harness.makeCommandBuffer(
            label: "Graph Lifecycle Before Prepare Rejection"
        )
        do {
            try graph.encode(
                frame: MetalEffectFrame(
                    source: source,
                    timing: frameTiming(sequence: 10)
                ),
                to: destination,
                commandBuffer: commandBuffer
            )
            return false
        } catch let error as MetalEffectError {
            return error == .notPrepared
        }
    }

    private static func checkResizeMismatch(
        graph: MetalEffectGraph,
        harness: MetalExampleHarness
    ) throws -> Bool {
        let mismatchedSource = try makeColorTexture(
            harness: harness,
            width: 2,
            height: 2,
            usage: [.shaderRead, .renderTarget],
            label: "Graph Lifecycle Mismatched Source"
        )
        let mismatchedDestination = try makeColorTexture(
            harness: harness,
            width: 2,
            height: 2,
            usage: [.shaderRead, .renderTarget],
            label: "Graph Lifecycle Mismatched Destination"
        )
        let commandBuffer = try harness.makeCommandBuffer(
            label: "Graph Lifecycle Resize Rejection"
        )
        do {
            try graph.encode(
                frame: MetalEffectFrame(
                    source: mismatchedSource,
                    timing: frameTiming(sequence: 11)
                ),
                to: mismatchedDestination,
                commandBuffer: commandBuffer
            )
            return false
        } catch let error as MetalEffectError {
            return error == .resizeRequired(
                expectedWidth: 2,
                expectedHeight: 2
            )
        }
    }

    private static func checkInPlaceEncoding(
        graph: MetalEffectGraph,
        harness: MetalExampleHarness,
        source: MTLTexture
    ) throws -> Bool {
        let commandBuffer = try harness.makeCommandBuffer(
            label: "Graph Lifecycle In Place Rejection"
        )
        do {
            try graph.encode(
                frame: MetalEffectFrame(
                    source: source,
                    timing: frameTiming(sequence: 12)
                ),
                to: source,
                commandBuffer: commandBuffer
            )
            return false
        } catch let error as MetalEffectError {
            return error == .incompatibleDestination
        }
    }

    private static func frameTiming(sequence: UInt64) -> EffectFrameTiming {
        EffectFrameTiming(
            frameIndex: sequence,
            inputSequence: sequence,
            hostTimeNanoseconds: sequence,
            deltaSeconds: 1.0 / 60.0,
            inputPresentationSeconds: Double(sequence) / 60.0,
            renderPresentationSeconds: Double(sequence) / 60.0
        )
    }
}
