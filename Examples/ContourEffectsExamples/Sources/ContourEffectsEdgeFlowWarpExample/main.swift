// SPDX-FileCopyrightText: 2026 Daito Manabe
// SPDX-License-Identifier: BSD-3-Clause

import ContourEffectsCore
import ContourEffectsMetal
import ExampleSupport
import Foundation
import Metal

private final class EdgeFlowWarpEffect: MetalEffectInstance {
    static let identifier: EffectIdentifier =
        "ws.daito.contour-effects.example.edge-flow-warp"

    static let effectDescriptor = EffectDescriptor(
        id: identifier,
        displayName: "Example Edge Flow Warp",
        category: .analysis,
        requiredInputs: [.composedColor, .edge, .opticalFlow]
    )

    let descriptor = effectDescriptor

    private var pipeline: MTLRenderPipelineState?
    private var preparedDevice: MTLDevice?
    private var width = 0
    private var height = 0
    private var preservedSchemaVersion =
        EdgeFlowWarpEffect.effectDescriptor.stateSchemaVersion
    private var preservedStateValues: [String: EffectValue] = [:]

    func prepare(context: MetalEffectHostContext) throws {
        guard context.workingPixelFormat == .rgba16Float,
              context.workingColorSpace == .displaySRGB,
              context.alphaMode == .straight
        else {
            throw MetalEffectError.incompatibleHostContext(
                "The example requires display sRGB rgba16Float with straight alpha."
            )
        }
        do {
            let library = try context.device.makeLibrary(
                source: Self.shaderSource,
                options: nil
            )
            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            pipelineDescriptor.label = "Example Edge Flow Warp"
            pipelineDescriptor.vertexFunction = library.makeFunction(
                name: "exampleEdgeFlowVertex"
            )
            pipelineDescriptor.fragmentFunction = library.makeFunction(
                name: "exampleEdgeFlowFragment"
            )
            pipelineDescriptor.colorAttachments[0].pixelFormat =
                context.workingPixelFormat
            pipeline = try context.device.makeRenderPipelineState(
                descriptor: pipelineDescriptor
            )
            preparedDevice = context.device
        } catch {
            throw MetalEffectError.pipelineCreationFailed(
                error.localizedDescription
            )
        }
    }

    func resize(width: Int, height: Int) throws {
        guard preparedDevice != nil else {
            throw MetalEffectError.notPrepared
        }
        guard width > 0, height > 0 else {
            throw MetalEffectError.incompatibleDestination
        }
        self.width = width
        self.height = height
    }

    func encode(
        frame: MetalEffectFrame,
        to destination: MTLTexture,
        commandBuffer: MTLCommandBuffer
    ) throws {
        guard let pipeline, let preparedDevice else {
            throw MetalEffectError.notPrepared
        }
        try frame.validate(requiredInputs: descriptor.requiredInputs)
        guard let edge = frame.analysisTextures.edge,
              let opticalFlow = frame.analysisTextures.opticalFlow
        else {
            throw MetalEffectError.missingInputs(
                descriptor.requiredInputs.subtracting(frame.availableInputs)
            )
        }
        guard frame.source.width == width,
              frame.source.height == height,
              destination.width == width,
              destination.height == height
        else {
            throw MetalEffectError.resizeRequired(
                expectedWidth: frame.source.width,
                expectedHeight: frame.source.height
            )
        }
        guard frame.source !== destination,
              frame.source.device === preparedDevice,
              destination.device === preparedDevice,
              commandBuffer.commandQueue.device === preparedDevice,
              frame.source.pixelFormat == .rgba16Float,
              destination.pixelFormat == .rgba16Float,
              frame.source.textureType == .type2D,
              destination.textureType == .type2D,
              frame.source.sampleCount == 1,
              destination.sampleCount == 1,
              frame.source.usage.contains(.shaderRead),
              destination.usage.contains(.renderTarget)
        else {
            throw MetalEffectError.incompatibleDestination
        }

        let renderPass = MTLRenderPassDescriptor()
        renderPass.colorAttachments[0].texture = destination
        renderPass.colorAttachments[0].loadAction = .dontCare
        renderPass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(
            descriptor: renderPass
        ) else {
            throw MetalEffectError.pipelineCreationFailed(
                "render encoder unavailable"
            )
        }
        encoder.label = "Example Edge Flow Warp"
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(frame.source, index: 0)
        encoder.setFragmentTexture(edge, index: 1)
        encoder.setFragmentTexture(opticalFlow, index: 2)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        encoder.endEncoding()
    }

    func reset() {}

    func snapshotState() -> EffectStateSnapshot {
        EffectStateSnapshot(
            effectIdentifier: Self.identifier,
            schemaVersion: preservedSchemaVersion,
            values: preservedStateValues
        )
    }

    func restoreState(_ state: EffectStateSnapshot) throws {
        guard state.effectIdentifier == Self.identifier else {
            throw MetalEffectError.invalidState(
                "The state belongs to a different effect."
            )
        }
        preservedSchemaVersion = state.schemaVersion
        preservedStateValues = state.values
    }

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct ExampleEdgeFlowRaster {
        float4 position [[position]];
        float2 uv;
    };

    constexpr sampler exampleNearestSampler(
        coord::normalized,
        address::clamp_to_edge,
        filter::nearest
    );

    vertex ExampleEdgeFlowRaster exampleEdgeFlowVertex(
        uint vertexID [[vertex_id]]
    ) {
        const float2 positions[6] = {
            float2(-1.0, -1.0), float2( 1.0, -1.0), float2(-1.0,  1.0),
            float2( 1.0, -1.0), float2( 1.0,  1.0), float2(-1.0,  1.0)
        };
        const float2 uvs[6] = {
            float2(0.0, 1.0), float2(1.0, 1.0), float2(0.0, 0.0),
            float2(1.0, 1.0), float2(1.0, 0.0), float2(0.0, 0.0)
        };
        ExampleEdgeFlowRaster out;
        out.position = float4(positions[vertexID], 0.0, 1.0);
        out.uv = uvs[vertexID];
        return out;
    }

    fragment half4 exampleEdgeFlowFragment(
        ExampleEdgeFlowRaster in [[stage_in]],
        texture2d<half> source [[texture(0)]],
        texture2d<half> edge [[texture(1)]],
        texture2d<half> opticalFlow [[texture(2)]]
    ) {
        float4 original = float4(source.sample(exampleNearestSampler, in.uv));
        float edgeAmount = saturate(
            float(edge.sample(exampleNearestSampler, in.uv).r)
        );
        float2 flow = float2(
            opticalFlow.sample(exampleNearestSampler, in.uv).rg
        );
        float4 warped = float4(
            source.sample(exampleNearestSampler, in.uv + flow)
        );
        return half4(mix(original, warped, edgeAmount));
    }
    """
}

private struct EdgeFlowWarpReport: Codable {
    var selfCheck: Bool
    var device: String
    var sourceSize: [Int]
    var flowSize: [Int]
    var flowResolutionScale: Float
    var edgeOffPixel: [Float]
    var expectedEdgeOffPixel: [Float]
    var edgeOnPixel: [Float]
    var expectedEdgeOnPixel: [Float]
    var wrongFlowFormatRejected: Bool
    var wrongFlowAspectRejected: Bool
}

@main
private enum EdgeFlowWarpExample {
    static func main() throws {
        let harness = try MetalExampleHarness()
        let width = 8
        let height = 4
        let flowWidth = width / 4
        let flowHeight = height / 4
        let colorUsage: MTLTextureUsage = [.shaderRead, .renderTarget]

        let source = try harness.makeTexture(
            pixelFormat: .rgba16Float,
            width: width,
            height: height,
            usage: colorUsage,
            label: "Edge Flow Example Source"
        )
        let destination = try harness.makeTexture(
            pixelFormat: .rgba16Float,
            width: width,
            height: height,
            usage: colorUsage,
            label: "Edge Flow Example Destination"
        )
        let edge = try harness.makeTexture(
            pixelFormat: .r8Unorm,
            width: width,
            height: height,
            usage: .shaderRead,
            label: "Edge Flow Example Edge"
        )
        let opticalFlow = try harness.makeTexture(
            pixelFormat: .rg16Float,
            width: flowWidth,
            height: flowHeight,
            usage: .shaderRead,
            label: "Edge Flow Example Quarter Flow"
        )

        let red = SIMD4<Float>(0.2, 0.1, 0.08, 0.75)
        let blue = SIMD4<Float>(0.05, 0.25, 0.8, 0.75)
        let sourcePixels = (0 ..< width * height).map { index in
            index % width < width / 2 ? red : blue
        }
        try harness.writeRGBA16(source, values: sourcePixels)
        let edgeValues = (0 ..< width * height).map { index -> UInt8 in
            index % width == 3 ? 255 : 0
        }
        try harness.writeR8(edge, values: edgeValues)
        try harness.writeRG16(
            opticalFlow,
            values: [
                SIMD2<Float>(0.25, 0),
                SIMD2<Float>(0.25, 0),
            ]
        )

        let graph = MetalEffectGraph(effects: [EdgeFlowWarpEffect()])
        try graph.prepare(
            context: MetalEffectHostContext(device: harness.device)
        )
        try graph.resize(width: width, height: height)

        let frame = MetalEffectFrame(
            source: source,
            analysisTextures: .init(edge: edge, opticalFlow: opticalFlow),
            timing: frameTiming(sequence: 1)
        )
        let commandBuffer = try harness.makeCommandBuffer(
            label: "Edge Flow Valid Frame"
        )
        try graph.encode(
            frame: frame,
            to: destination,
            commandBuffer: commandBuffer
        )
        try harness.commitAndWait(commandBuffer)

        let edgeOffPixel = try harness.readRGBA16(
            destination,
            x: 1,
            y: height / 2
        )
        let edgeOnPixel = try harness.readRGBA16(
            destination,
            x: 3,
            y: height / 2
        )
        let expectedEdgeOffPixel = [red.x, red.y, red.z, red.w]
        let expectedEdgeOnPixel = [blue.x, blue.y, blue.z, blue.w]
        try exampleRequire(
            maximumAbsoluteError(
                edgeOffPixel,
                expectedEdgeOffPixel
            ) < 0.015,
            "The edge-off pixel was unexpectedly warped."
        )
        try exampleRequire(
            maximumAbsoluteError(
                edgeOnPixel,
                expectedEdgeOnPixel
            ) < 0.015,
            "The edge-on pixel did not follow optical flow."
        )

        let wrongFormatFlow = try harness.makeTexture(
            pixelFormat: .r16Float,
            width: flowWidth,
            height: flowHeight,
            usage: .shaderRead,
            label: "Edge Flow Wrong Format"
        )
        let wrongFlowFormatRejected = try rejectsFlow(
            wrongFormatFlow,
            expectedName: "optical-flow",
            graph: graph,
            source: source,
            edge: edge,
            destination: destination,
            harness: harness,
            sequence: 2
        )

        let wrongAspectFlow = try harness.makeTexture(
            pixelFormat: .rg16Float,
            width: 1,
            height: 1,
            usage: .shaderRead,
            label: "Edge Flow Wrong Aspect"
        )
        let wrongFlowAspectRejected = try rejectsFlow(
            wrongAspectFlow,
            expectedName: "optical-flow",
            graph: graph,
            source: source,
            edge: edge,
            destination: destination,
            harness: harness,
            sequence: 3
        )

        try exampleRequire(
            wrongFlowFormatRejected,
            "An optical-flow texture with the wrong format was accepted."
        )
        try exampleRequire(
            wrongFlowAspectRejected,
            "An optical-flow texture with the wrong aspect was accepted."
        )

        try emitJSON(
            EdgeFlowWarpReport(
                selfCheck: true,
                device: harness.device.name,
                sourceSize: [width, height],
                flowSize: [flowWidth, flowHeight],
                flowResolutionScale: Float(flowWidth) / Float(width),
                edgeOffPixel: edgeOffPixel,
                expectedEdgeOffPixel: expectedEdgeOffPixel,
                edgeOnPixel: edgeOnPixel,
                expectedEdgeOnPixel: expectedEdgeOnPixel,
                wrongFlowFormatRejected: wrongFlowFormatRejected,
                wrongFlowAspectRejected: wrongFlowAspectRejected
            )
        )
    }

    private static func rejectsFlow(
        _ flow: MTLTexture,
        expectedName: String,
        graph: MetalEffectGraph,
        source: MTLTexture,
        edge: MTLTexture,
        destination: MTLTexture,
        harness: MetalExampleHarness,
        sequence: UInt64
    ) throws -> Bool {
        let frame = MetalEffectFrame(
            source: source,
            analysisTextures: .init(edge: edge, opticalFlow: flow),
            timing: frameTiming(sequence: sequence)
        )
        do {
            try graph.encode(
                frame: frame,
                to: destination,
                commandBuffer: try harness.makeCommandBuffer(
                    label: "Edge Flow Invalid Frame"
                )
            )
            return false
        } catch let error as MetalEffectError {
            if case let .incompatibleAnalysisTexture(name) = error,
               name == expectedName
            {
                return true
            }
            throw error
        }
    }

    private static func frameTiming(sequence: UInt64) -> EffectFrameTiming {
        EffectFrameTiming(
            frameIndex: sequence - 1,
            inputSequence: sequence,
            hostTimeNanoseconds: sequence * 1_000_000,
            deltaSeconds: 1.0 / 60.0,
            inputPresentationSeconds: Double(sequence - 1) / 60.0,
            renderPresentationSeconds: Double(sequence - 1) / 60.0
        )
    }
}
