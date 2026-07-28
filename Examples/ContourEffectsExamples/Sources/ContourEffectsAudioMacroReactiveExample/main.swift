// SPDX-FileCopyrightText: 2026 Daito Manabe
// SPDX-License-Identifier: BSD-3-Clause

import ContourEffectsCore
import ContourEffectsMetal
import ExampleSupport
import Foundation
import Metal

private final class AudioMacroReactiveEffect: MetalEffectInstance {
    static let identifier: EffectIdentifier =
        "ws.daito.contour-effects.example.audio-macro-reactive"

    let descriptor = EffectDescriptor(
        id: identifier,
        displayName: "Example Audio Macro Reactive",
        category: .utility,
        requiredInputs: [
            .composedColor,
            .audio,
            .performanceMacros,
        ]
    )

    private var pipeline: MTLRenderPipelineState?
    private var preparedDevice: MTLDevice?
    private var workingPixelFormat: MTLPixelFormat?
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
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.label = "Example Audio Macro Reactive"
            descriptor.vertexFunction = library.makeFunction(
                name: "exampleReactiveVertex"
            )
            descriptor.fragmentFunction = library.makeFunction(
                name: "exampleReactiveFragment"
            )
            descriptor.colorAttachments[0].pixelFormat =
                context.workingPixelFormat
            pipeline = try context.device.makeRenderPipelineState(
                descriptor: descriptor
            )
            preparedDevice = context.device
            workingPixelFormat = context.workingPixelFormat
        } catch {
            pipeline = nil
            preparedDevice = nil
            workingPixelFormat = nil
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
        guard let pipeline,
              let preparedDevice,
              let workingPixelFormat
        else {
            throw MetalEffectError.notPrepared
        }
        try frame.validate(requiredInputs: descriptor.requiredInputs)
        guard frame.source.width == width,
              frame.source.height == height
        else {
            throw MetalEffectError.resizeRequired(
                expectedWidth: frame.source.width,
                expectedHeight: frame.source.height
            )
        }
        guard frame.source.device === preparedDevice,
              frame.source.device
                === commandBuffer.commandQueue.device,
              frame.source.textureType == .type2D,
              frame.source.sampleCount == 1,
              frame.source.pixelFormat == workingPixelFormat,
              frame.source.usage.contains(.shaderRead)
        else {
            throw MetalEffectError.incompatibleSource
        }
        guard destination !== frame.source,
              destination.device === preparedDevice,
              destination.width == width,
              destination.height == height,
              destination.textureType == .type2D,
              destination.sampleCount == 1,
              destination.pixelFormat == workingPixelFormat,
              destination.usage.contains(.renderTarget)
        else {
            throw MetalEffectError.incompatibleDestination
        }

        let audio = frame.audio.clamped()
        let macros = frame.macros.clamped()
        let presentationSeconds = Float(
            frame.timing.renderPresentationSeconds
                ?? frame.timing.inputPresentationSeconds
                ?? 0
        )
        let phase = presentationSeconds * 2 * .pi
        let motionAmount =
            audio.volume * macros.motion
                + audio.attack * macros.audioReactive
        let shiftX = cos(phase) * motionAmount * 0.093_75
        let shiftY =
            sin(phase) * motionAmount * 0.062_5
                + audio.beat * macros.motion * 0.031_25
        let colorMix = min(
            max(
                audio.beat * macros.audioReactive
                    + audio.high * macros.color * 0.5,
                0
            ),
            1
        )
        let energyLift = audio.volume * macros.energy * 0.12
        var uniforms = ReactiveUniforms(
            controls: SIMD4(
                shiftX,
                shiftY,
                colorMix,
                energyLift
            )
        )

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = destination
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(
            descriptor: pass
        ) else {
            throw MetalEffectError.pipelineCreationFailed(
                "render encoder unavailable"
            )
        }
        encoder.label = "Example Audio Macro Reactive"
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(frame.source, index: 0)
        encoder.setFragmentBytes(
            &uniforms,
            length: MemoryLayout<ReactiveUniforms>.stride,
            index: 0
        )
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

    private struct ReactiveUniforms {
        var controls: SIMD4<Float>
    }

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct ExampleReactiveRaster {
        float4 position [[position]];
        float2 uv;
    };

    struct ExampleReactiveUniforms {
        float4 controls;
    };

    constexpr sampler exampleReactiveSampler(
        coord::normalized,
        address::clamp_to_edge,
        filter::nearest
    );

    vertex ExampleReactiveRaster exampleReactiveVertex(
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
        ExampleReactiveRaster out;
        out.position = float4(positions[vertexID], 0.0, 1.0);
        out.uv = uvs[vertexID];
        return out;
    }

    fragment half4 exampleReactiveFragment(
        ExampleReactiveRaster in [[stage_in]],
        texture2d<half> source [[texture(0)]],
        constant ExampleReactiveUniforms &uniforms [[buffer(0)]]
    ) {
        float2 shiftedUV = in.uv + uniforms.controls.xy;
        float4 sourceColor = float4(
            source.sample(exampleReactiveSampler, shiftedUV)
        );
        float3 remapped = sourceColor.brg;
        float3 color = mix(
            sourceColor.rgb,
            remapped,
            uniforms.controls.z
        );
        color = saturate(color + uniforms.controls.w);
        return half4(half3(color), half(sourceColor.a));
    }
    """
}

private struct ClampReport: Codable {
    var volume: Float
    var low: Float
    var high: Float
    var attack: Float
    var spectrum: [Float]
    var energy: Float
    var motion: Float
    var color: Float
    var feedback: Float
}

private struct AudioMacroReactiveReport: Codable {
    var selfCheck: Bool
    var device: String
    var clamped: ClampReport
    var clampingVerified: Bool
    var zeroPixel: [Float]
    var motionPixel: [Float]
    var colorPixel: [Float]
    var highPixel: [Float]
    var motionDifference: Float
    var colorDifference: Float
    var highDifference: Float
    var alphaPreserved: Bool
    var missingProvidedInputsRejected: Bool
}

@main
private enum AudioMacroReactiveExample {
    private static let width = 8
    private static let height = 4
    private static let sourceAlpha: Float = 0.625

    static func main() throws {
        let harness = try MetalExampleHarness()
        let usage: MTLTextureUsage = [.shaderRead, .renderTarget]
        let source = try harness.makeTexture(
            pixelFormat: .rgba16Float,
            width: width,
            height: height,
            usage: usage,
            label: "Audio Macro Example Source"
        )
        let destination = try harness.makeTexture(
            pixelFormat: .rgba16Float,
            width: width,
            height: height,
            usage: usage,
            label: "Audio Macro Example Destination"
        )
        writeGradient(to: source)

        let effect = AudioMacroReactiveEffect()
        let graph = MetalEffectGraph(effects: [effect])
        try graph.prepare(
            context: MetalEffectHostContext(device: harness.device)
        )
        try graph.resize(width: width, height: height)

        let rawAudio = EffectAudioFeatures(
            source: .osc,
            isLive: true,
            volume: 1.7,
            low: -0.2,
            mid: 0.4,
            high: .infinity,
            beat: 2,
            attack: .nan,
            spectrum: [-1, 0.5, 2, .nan],
            timestamp: 12
        )
        let clampedAudio = rawAudio.clamped(maximumBandCount: 3)
        let rawMacros = EffectPerformanceMacros(
            energy: 1.4,
            motion: -0.2,
            density: 0.5,
            audioReactive: 0.8,
            color: .infinity,
            glitch: .nan,
            feedback: 2,
            texture: -1
        )
        let clampedMacros = rawMacros.clamped()
        let clampingVerified =
            clampedAudio.volume == 1
                && clampedAudio.low == 0
                && clampedAudio.mid == 0.4
                && clampedAudio.high == 0
                && clampedAudio.beat == 1
                && clampedAudio.attack == 0
                && clampedAudio.spectrum == [0, 0.5, 1]
                && clampedMacros.energy == 1
                && clampedMacros.motion == 0
                && clampedMacros.density == 0.5
                && clampedMacros.audioReactive == 0.8
                && clampedMacros.color == 0
                && clampedMacros.glitch == 0
                && clampedMacros.feedback == 1
                && clampedMacros.texture == 0
        try exampleRequire(
            clampingVerified,
            "Audio or macro normalization did not match the SDK contract."
        )

        let zeroPixel = try render(
            graph: graph,
            harness: harness,
            source: source,
            destination: destination,
            audio: .zero,
            macros: .zero,
            sequence: 1
        )
        let motionPixel = try render(
            graph: graph,
            harness: harness,
            source: source,
            destination: destination,
            audio: EffectAudioFeatures(
                source: .osc,
                isLive: true,
                volume: 1
            ),
            macros: EffectPerformanceMacros(motion: 1),
            sequence: 2
        )
        let colorPixel = try render(
            graph: graph,
            harness: harness,
            source: source,
            destination: destination,
            audio: EffectAudioFeatures(
                source: .osc,
                isLive: true,
                high: 1,
                beat: 1
            ),
            macros: EffectPerformanceMacros(
                audioReactive: 1,
                color: 1
            ),
            sequence: 3
        )
        let highPixel = try render(
            graph: graph,
            harness: harness,
            source: source,
            destination: destination,
            audio: EffectAudioFeatures(
                source: .osc,
                isLive: true,
                volume: 1,
                high: 1,
                beat: 1,
                attack: 1
            ),
            macros: EffectPerformanceMacros(
                energy: 0.5,
                motion: 1,
                audioReactive: 1,
                color: 1
            ),
            sequence: 4
        )

        let motionDifference = rgbDifference(motionPixel, zeroPixel)
        let colorDifference = rgbDifference(colorPixel, zeroPixel)
        let highDifference = rgbDifference(highPixel, zeroPixel)
        let allPixels = [zeroPixel, motionPixel, colorPixel, highPixel]
        let alphaPreserved = allPixels.allSatisfy {
            abs($0[3] - sourceAlpha) < 0.002
        }

        try exampleRequire(
            motionDifference > 0.05,
            "Motion input did not produce a visible spatial change."
        )
        try exampleRequire(
            colorDifference > 0.20,
            "Color input did not produce a visible color change."
        )
        try exampleRequire(
            highDifference > 0.20,
            "Combined audio and macros did not change the output."
        )
        try exampleRequire(
            alphaPreserved,
            "Reactive processing changed source alpha."
        )

        var missingProvidedInputsRejected = false
        let missingFrame = MetalEffectFrame(
            source: source,
            audio: EffectAudioFeatures(volume: 1),
            macros: EffectPerformanceMacros(motion: 1),
            timing: timing(sequence: 5),
            providedInputs: []
        )
        do {
            try graph.encode(
                frame: missingFrame,
                to: destination,
                commandBuffer: try harness.makeCommandBuffer(
                    label: "Audio Macro Missing Providers"
                )
            )
        } catch let error as MetalEffectError {
            if case .missingInputs(let inputs) = error,
               inputs.contains(.audio),
               inputs.contains(.performanceMacros)
            {
                missingProvidedInputsRejected = true
            }
        }
        try exampleRequire(
            missingProvidedInputsRejected,
            "Missing audio and macro providers did not fail closed."
        )

        try emitJSON(
            AudioMacroReactiveReport(
                selfCheck: true,
                device: harness.device.name,
                clamped: ClampReport(
                    volume: clampedAudio.volume,
                    low: clampedAudio.low,
                    high: clampedAudio.high,
                    attack: clampedAudio.attack,
                    spectrum: clampedAudio.spectrum,
                    energy: clampedMacros.energy,
                    motion: clampedMacros.motion,
                    color: clampedMacros.color,
                    feedback: clampedMacros.feedback
                ),
                clampingVerified: clampingVerified,
                zeroPixel: zeroPixel,
                motionPixel: motionPixel,
                colorPixel: colorPixel,
                highPixel: highPixel,
                motionDifference: motionDifference,
                colorDifference: colorDifference,
                highDifference: highDifference,
                alphaPreserved: alphaPreserved,
                missingProvidedInputsRejected: missingProvidedInputsRejected
            )
        )
    }

    private static func writeGradient(to texture: MTLTexture) {
        var pixels: [SIMD4<Float16>] = []
        pixels.reserveCapacity(width * height)
        for y in 0 ..< height {
            for x in 0 ..< width {
                let red = Float(x) / Float(width - 1)
                let green = 0.2 + Float(y) * 0.15
                let blue = 1 - red * 0.6
                pixels.append(
                    SIMD4(
                        Float16(red),
                        Float16(green),
                        Float16(blue),
                        Float16(sourceAlpha)
                    )
                )
            }
        }
        pixels.withUnsafeBytes { bytes in
            texture.replace(
                region: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0,
                withBytes: bytes.baseAddress!,
                bytesPerRow: width
                    * MemoryLayout<SIMD4<Float16>>.stride
            )
        }
    }

    private static func render(
        graph: MetalEffectGraph,
        harness: MetalExampleHarness,
        source: MTLTexture,
        destination: MTLTexture,
        audio: EffectAudioFeatures,
        macros: EffectPerformanceMacros,
        sequence: UInt64
    ) throws -> [Float] {
        let commandBuffer = try harness.makeCommandBuffer(
            label: "Audio Macro Frame \(sequence)"
        )
        try graph.encode(
            frame: MetalEffectFrame(
                source: source,
                audio: audio.clamped(),
                macros: macros.clamped(),
                timing: timing(sequence: sequence)
            ),
            to: destination,
            commandBuffer: commandBuffer
        )
        try harness.commitAndWait(commandBuffer)
        return try harness.readRGBA16(destination, x: 2, y: 1)
    }

    private static func timing(sequence: UInt64) -> EffectFrameTiming {
        EffectFrameTiming(
            frameIndex: sequence - 1,
            inputSequence: sequence,
            hostTimeNanoseconds: sequence * 1_000_000,
            deltaSeconds: 1.0 / 60.0,
            inputPresentationSeconds: 0,
            renderPresentationSeconds: 0
        )
    }

    private static func rgbDifference(
        _ lhs: [Float],
        _ rhs: [Float]
    ) -> Float {
        maximumAbsoluteError(
            Array(lhs.prefix(3)),
            Array(rhs.prefix(3))
        )
    }
}
