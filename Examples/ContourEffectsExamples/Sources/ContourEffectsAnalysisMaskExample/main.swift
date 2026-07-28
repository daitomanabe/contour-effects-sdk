// SPDX-FileCopyrightText: 2026 Daito Manabe
// SPDX-License-Identifier: BSD-3-Clause

import ContourEffectsCore
import ContourEffectsMetal
import ExampleSupport
import Foundation
import Metal

private final class AnalysisMaskEffect: MetalEffectInstance {
    static let identifier: EffectIdentifier =
        "ws.daito.contour-effects.example.analysis-mask"

    let descriptor = EffectDescriptor(
        id: identifier,
        displayName: "Example Analysis Mask",
        category: .compositing,
        requiredInputs: [.composedColor, .rawCameraColor, .personMask]
    )

    private var pipeline: MTLRenderPipelineState?
    private var width = 0
    private var height = 0
    private var preservedSchemaVersion = 1
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
            pipelineDescriptor.label = "Example Analysis Mask"
            pipelineDescriptor.vertexFunction = library.makeFunction(
                name: "exampleMaskVertex"
            )
            pipelineDescriptor.fragmentFunction = library.makeFunction(
                name: "exampleMaskFragment"
            )
            pipelineDescriptor.colorAttachments[0].pixelFormat =
                context.workingPixelFormat
            pipeline = try context.device.makeRenderPipelineState(
                descriptor: pipelineDescriptor
            )
        } catch {
            throw MetalEffectError.pipelineCreationFailed(
                error.localizedDescription
            )
        }
    }

    func resize(width: Int, height: Int) throws {
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
        guard let pipeline else { throw MetalEffectError.notPrepared }
        try frame.validate(requiredInputs: descriptor.requiredInputs)
        guard let rawCamera = frame.rawCamera,
              let personMask = frame.analysisTextures.personMask
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
        encoder.label = "Example Analysis Mask"
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(frame.source, index: 0)
        encoder.setFragmentTexture(rawCamera, index: 1)
        encoder.setFragmentTexture(personMask, index: 2)
        encoder.drawPrimitives(
            type: .triangle,
            vertexStart: 0,
            vertexCount: 6
        )
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

    struct ExampleRaster {
        float4 position [[position]];
        float2 uv;
    };

    constexpr sampler exampleSampler(
        coord::normalized,
        address::clamp_to_edge,
        filter::linear
    );

    vertex ExampleRaster exampleMaskVertex(uint vertexID [[vertex_id]]) {
        const float2 positions[6] = {
            float2(-1.0, -1.0), float2( 1.0, -1.0), float2(-1.0,  1.0),
            float2( 1.0, -1.0), float2( 1.0,  1.0), float2(-1.0,  1.0)
        };
        const float2 uvs[6] = {
            float2(0.0, 1.0), float2(1.0, 1.0), float2(0.0, 0.0),
            float2(1.0, 1.0), float2(1.0, 0.0), float2(0.0, 0.0)
        };
        ExampleRaster out;
        out.position = float4(positions[vertexID], 0.0, 1.0);
        out.uv = uvs[vertexID];
        return out;
    }

    fragment half4 exampleMaskFragment(
        ExampleRaster in [[stage_in]],
        texture2d<half> source [[texture(0)]],
        texture2d<half> rawCamera [[texture(1)]],
        texture2d<half> personMask [[texture(2)]]
    ) {
        float4 composed = float4(source.sample(exampleSampler, in.uv));
        float4 camera = float4(rawCamera.sample(exampleSampler, in.uv));
        float mask = saturate(float(personMask.sample(exampleSampler, in.uv).r));
        float4 processed = float4(1.0 - composed.rgb, composed.a);
        return half4(mix(camera, processed, mask));
    }
    """
}

private struct AnalysisMaskReport: Codable {
    var selfCheck: Bool
    var device: String
    var outsidePixel: [Float]
    var expectedOutside: [Float]
    var insidePixel: [Float]
    var expectedInside: [Float]
    var missingMaskRejected: Bool
    var wrongMaskABIRejected: Bool
    var unknownStatePreserved: Bool
}

@main
private enum AnalysisMaskExample {
    static func main() throws {
        let harness = try MetalExampleHarness()
        let width = 4
        let height = 4
        let colorUsage: MTLTextureUsage = [.shaderRead, .renderTarget]

        let source = try harness.makeTexture(
            pixelFormat: .rgba16Float,
            width: width,
            height: height,
            usage: colorUsage,
            label: "Analysis Example Composed Source"
        )
        let rawCamera = try harness.makeTexture(
            pixelFormat: .rgba16Float,
            width: width,
            height: height,
            usage: colorUsage,
            label: "Analysis Example Raw Camera"
        )
        let destination = try harness.makeTexture(
            pixelFormat: .rgba16Float,
            width: width,
            height: height,
            usage: colorUsage,
            label: "Analysis Example Destination"
        )
        let personMask = try harness.makeTexture(
            pixelFormat: .r8Unorm,
            width: width,
            height: height,
            usage: .shaderRead,
            label: "Analysis Example Person Mask"
        )

        let sourceColor: [Float] = [0.2, 0.4, 0.6, 0.75]
        let cameraColor: [Float] = [0.05, 0.1, 0.15, 1]
        try harness.fillRGBA16(
            source,
            color: SIMD4(
                sourceColor[0],
                sourceColor[1],
                sourceColor[2],
                sourceColor[3]
            )
        )
        try harness.fillRGBA16(
            rawCamera,
            color: SIMD4(
                cameraColor[0],
                cameraColor[1],
                cameraColor[2],
                cameraColor[3]
            )
        )
        let maskValues = (0 ..< width * height).map { index -> UInt8 in
            (index % width) < width / 2 ? 0 : 255
        }
        try harness.writeR8(personMask, values: maskValues)

        let effect = AnalysisMaskEffect()
        try effect.restoreState(
            EffectStateSnapshot(
                effectIdentifier: AnalysisMaskEffect.identifier,
                schemaVersion: 4,
                values: [
                    "future.mask.feather": .number(0.42),
                ]
            )
        )
        let restoredState = effect.snapshotState()
        let unknownStatePreserved =
            restoredState.schemaVersion == 4
            && restoredState.values["future.mask.feather"] == .number(0.42)
        try exampleRequire(
            unknownStatePreserved,
            "The example-local effect discarded future state."
        )

        let graph = MetalEffectGraph(effects: [effect])
        try graph.prepare(
            context: MetalEffectHostContext(device: harness.device)
        )
        try graph.resize(width: width, height: height)

        let validFrame = MetalEffectFrame(
            source: source,
            rawCamera: rawCamera,
            analysisTextures: .init(personMask: personMask),
            timing: frameTiming(sequence: 1)
        )
        let validCommandBuffer = try harness.makeCommandBuffer(
            label: "Analysis Mask Valid Frame"
        )
        try graph.encode(
            frame: validFrame,
            to: destination,
            commandBuffer: validCommandBuffer
        )
        try harness.commitAndWait(validCommandBuffer)

        let outsidePixel = try harness.readRGBA16(
            destination,
            x: 0,
            y: height / 2
        )
        let insidePixel = try harness.readRGBA16(
            destination,
            x: width - 1,
            y: height / 2
        )
        let expectedOutside = cameraColor
        let expectedInside: [Float] = [
            1 - sourceColor[0],
            1 - sourceColor[1],
            1 - sourceColor[2],
            sourceColor[3],
        ]
        try exampleRequire(
            maximumAbsoluteError(outsidePixel, expectedOutside) < 0.015,
            "Pixels outside the person mask did not preserve raw camera."
        )
        try exampleRequire(
            maximumAbsoluteError(insidePixel, expectedInside) < 0.015,
            "Pixels inside the person mask were not processed."
        )

        var missingMaskRejected = false
        let missingMaskFrame = MetalEffectFrame(
            source: source,
            rawCamera: rawCamera,
            timing: frameTiming(sequence: 2)
        )
        do {
            try graph.encode(
                frame: missingMaskFrame,
                to: destination,
                commandBuffer: try harness.makeCommandBuffer(
                    label: "Analysis Mask Missing Input"
                )
            )
        } catch let error as MetalEffectError {
            if case .missingInputs(let inputs) = error,
               inputs.contains(.personMask)
            {
                missingMaskRejected = true
            }
        }

        let wrongMask = try harness.makeTexture(
            pixelFormat: .r16Float,
            width: width,
            height: height,
            usage: .shaderRead,
            label: "Analysis Example Wrong Mask"
        )
        var wrongMaskABIRejected = false
        let wrongMaskFrame = MetalEffectFrame(
            source: source,
            rawCamera: rawCamera,
            analysisTextures: .init(personMask: wrongMask),
            timing: frameTiming(sequence: 3)
        )
        do {
            try graph.encode(
                frame: wrongMaskFrame,
                to: destination,
                commandBuffer: try harness.makeCommandBuffer(
                    label: "Analysis Mask Wrong ABI"
                )
            )
        } catch let error as MetalEffectError {
            if case .incompatibleAnalysisTexture("person-mask") = error {
                wrongMaskABIRejected = true
            }
        }

        try exampleRequire(
            missingMaskRejected,
            "A missing person mask did not fail closed."
        )
        try exampleRequire(
            wrongMaskABIRejected,
            "A person mask with the wrong pixel format was accepted."
        )

        try emitJSON(
            AnalysisMaskReport(
                selfCheck: true,
                device: harness.device.name,
                outsidePixel: outsidePixel,
                expectedOutside: expectedOutside,
                insidePixel: insidePixel,
                expectedInside: expectedInside,
                missingMaskRejected: missingMaskRejected,
                wrongMaskABIRejected: wrongMaskABIRejected,
                unknownStatePreserved: unknownStatePreserved
            )
        )
    }

    private static func frameTiming(sequence: UInt64) -> EffectFrameTiming {
        EffectFrameTiming(
            frameIndex: sequence - 1,
            inputSequence: sequence,
            hostTimeNanoseconds: DispatchTime.now().uptimeNanoseconds,
            deltaSeconds: 1.0 / 60.0,
            inputPresentationSeconds: Double(sequence - 1) / 60.0,
            renderPresentationSeconds: Double(sequence - 1) / 60.0
        )
    }
}
