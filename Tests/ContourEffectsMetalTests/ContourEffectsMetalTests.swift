// SPDX-FileCopyrightText: 2026 Daito Manabe
// SPDX-License-Identifier: BSD-3-Clause

import ContourEffectsCore
import ContourEffectsMetal
import Metal
import XCTest

final class ContourEffectsMetalTests: XCTestCase {
    func testCatalogBuildsEveryAdvertisedEffect() {
        XCTAssertFalse(ContourEffectsMetalCatalog.descriptors.isEmpty)
        for descriptor in ContourEffectsMetalCatalog.descriptors {
            XCTAssertNotNil(
                ContourEffectsMetalCatalog.makeEffect(identifier: descriptor.id)
            )
        }
    }

    func testCubeLUTParsesStandard3DOrder() throws {
        let lut = try CubeLUT.parse("""
        TITLE "Identity 2"
        LUT_3D_SIZE 2
        DOMAIN_MIN 0 0 0
        DOMAIN_MAX 1 1 1
        0 0 0
        1 0 0
        0 1 0
        1 1 0
        0 0 1
        1 0 1
        0 1 1
        1 1 1
        """)

        XCTAssertEqual(lut.title, "Identity 2")
        XCTAssertEqual(lut.size, 2)
        XCTAssertEqual(lut.samples[1], SIMD3<Float>(1, 0, 0))
        XCTAssertEqual(lut.samples[7], SIMD3<Float>(1, 1, 1))
    }

    func testConfigurationSanitizesExternalState() {
        var configuration = ColorGradeConfiguration()
        configuration.exposure = 99
        configuration.contrast = -2
        configuration.grain = .nan
        configuration.lutMix = 4
        configuration.sanitize()

        XCTAssertEqual(configuration.exposure, 3)
        XCTAssertEqual(configuration.contrast, 0.5)
        XCTAssertEqual(configuration.grain, 0)
        XCTAssertEqual(configuration.lutMix, 1)
    }

    func testColorGradeStatePreservesUnknownFutureKeys() throws {
        let effect = ColorGradeEffect()
        try effect.restoreState(
            EffectStateSnapshot(
                effectIdentifier: ColorGradeEffect.identifier,
                schemaVersion: 3,
                values: [
                    "exposure": .number(0.75),
                    "futureCurve": .object(["mode": .string("new")]),
                ]
            )
        )

        XCTAssertEqual(effect.configuration.exposure, 0.75)
        XCTAssertEqual(
            effect.snapshotState().values["futureCurve"],
            .object(["mode": .string("new")])
        )
        XCTAssertEqual(effect.snapshotState().schemaVersion, 3)
    }

    func testEmptyObservationSetCanStillDeclareProviderAvailability() {
        let device = MTLCreateSystemDefaultDevice()
        guard let device else { return }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: 1,
            height: 1,
            mipmapped: false
        )
        descriptor.usage = .shaderRead
        guard let source = device.makeTexture(descriptor: descriptor) else { return }
        let frame = MetalEffectFrame(
            source: source,
            timing: EffectFrameTiming(
                frameIndex: 0,
                hostTimeNanoseconds: 0,
                deltaSeconds: 0
            ),
            providedInputs: [.objectDetections]
        )

        XCTAssertTrue(frame.detections.isEmpty)
        XCTAssertTrue(frame.availableInputs.contains(.objectDetections))
    }

    func testProvidedInputsCannotForgeMissingTextureAvailability() {
        let device = MTLCreateSystemDefaultDevice()
        guard let device else { return }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: 1,
            height: 1,
            mipmapped: false
        )
        descriptor.usage = .shaderRead
        guard let source = device.makeTexture(descriptor: descriptor) else { return }
        let frame = MetalEffectFrame(
            source: source,
            timing: EffectFrameTiming(
                frameIndex: 0,
                hostTimeNanoseconds: 0,
                deltaSeconds: 0
            ),
            providedInputs: [.edge, .depth, .rawCameraColor]
        )

        XCTAssertFalse(frame.availableInputs.contains(.edge))
        XCTAssertFalse(frame.availableInputs.contains(.depth))
        XCTAssertFalse(frame.availableInputs.contains(.rawCameraColor))
    }

    func testCubeLUTRejectsUnsafePublicConstruction() {
        XCTAssertThrowsError(
            try CubeLUT(
                title: "Broken",
                size: 2,
                domainMinimum: .zero,
                domainMaximum: SIMD3<Float>(repeating: 1),
                samples: []
            )
        ) { error in
            XCTAssertEqual(
                error as? CubeLUTError,
                .sampleCount(expected: 8, actual: 0)
            )
        }
    }

    func testCubeLUTRejectsSamplesOutsideHalfFloatRange() {
        let samples = [SIMD3<Float>](
            repeating: SIMD3<Float>(70_000, 0, 0),
            count: 8
        )
        XCTAssertThrowsError(
            try CubeLUT(
                title: "Too Large",
                size: 2,
                domainMinimum: .zero,
                domainMaximum: SIMD3<Float>(repeating: 1),
                samples: samples
            )
        ) { error in
            XCTAssertEqual(
                error as? CubeLUTError,
                .sampleOutsideHalfFloatRange("sample 0")
            )
        }
    }

    func testColorGradeEncodesARealMetalFrame() throws {
        let device = try requireMetalDevice()
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let input = try makeTexture(
            device: device,
            width: 2,
            height: 2,
            usage: [.shaderRead],
            pixelFormat: .rgba16Float
        )
        let output = try makeTexture(
            device: device,
            width: 2,
            height: 2,
            usage: [.shaderRead, .renderTarget],
            pixelFormat: .rgba16Float
        )
        let sourcePixels = [SIMD4<Float16>](
            repeating: SIMD4<Float16>(0.2, 0.2, 0.2, 1),
            count: 4
        )
        sourcePixels.withUnsafeBytes { bytes in
            input.replace(
                region: MTLRegionMake2D(0, 0, 2, 2),
                mipmapLevel: 0,
                withBytes: bytes.baseAddress!,
                bytesPerRow: 2 * MemoryLayout<SIMD4<Float16>>.stride
            )
        }

        var configuration = ColorGradeConfiguration()
        configuration.exposure = 1
        let effect = ColorGradeEffect(configuration: configuration)
        try effect.prepare(
            context: .init(device: device, workingPixelFormat: .rgba16Float)
        )
        try effect.resize(width: 2, height: 2)

        let commandBuffer = try XCTUnwrap(queue.makeCommandBuffer())
        let frame = MetalEffectFrame(
            source: input,
            timing: EffectFrameTiming(
                frameIndex: 1,
                hostTimeNanoseconds: 1,
                deltaSeconds: 1.0 / 60.0,
                renderPresentationSeconds: 1.0 / 60.0
            )
        )
        try effect.encode(frame: frame, to: output, commandBuffer: commandBuffer)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        XCTAssertEqual(commandBuffer.status, .completed)

        var outputPixels = [SIMD4<Float16>](repeating: .zero, count: 4)
        outputPixels.withUnsafeMutableBytes { bytes in
            output.getBytes(
                bytes.baseAddress!,
                bytesPerRow: 2 * MemoryLayout<SIMD4<Float16>>.stride,
                from: MTLRegionMake2D(0, 0, 2, 2),
                mipmapLevel: 0
            )
        }
        XCTAssertGreaterThan(
            Float(outputPixels[0].x),
            Float(sourcePixels[0].x)
        )
        XCTAssertGreaterThan(
            Float(outputPixels[0].y),
            Float(sourcePixels[0].y)
        )
        XCTAssertGreaterThan(
            Float(outputPixels[0].z),
            Float(sourcePixels[0].z)
        )
        XCTAssertEqual(outputPixels[0].w, 1)
    }

    func testGenericParameterSetterRejectsInvalidAndAssetValues() throws {
        let effect = ColorGradeEffect()
        XCTAssertThrowsError(
            try effect.setParameterValue(
                .string("bright"),
                identifier: "exposure"
            )
        )
        XCTAssertEqual(effect.configuration.exposure, 0)

        XCTAssertThrowsError(
            try effect.setParameterValue(
                .string("lut-id"),
                identifier: "lut"
            )
        ) { error in
            XCTAssertEqual(
                error as? MetalEffectError,
                .parameterRequiresAssetResolver("lut")
            )
        }
    }

    func testGenericLookSetterAppliesTheSelectedLookThroughExistential() throws {
        var configuration = ColorGradeConfiguration()
        configuration.isEnabled = false
        let concrete = ColorGradeEffect(configuration: configuration)
        let effect: any MetalEffectInstance = concrete

        try effect.setParameterValue(
            .number(Double(ColorGradeLook.cinema.rawValue)),
            identifier: "look"
        )

        XCTAssertEqual(concrete.configuration.look, .cinema)
        XCTAssertEqual(concrete.configuration.contrast, 1.12, accuracy: 0.001)
        XCTAssertEqual(concrete.configuration.filmCurve, 0.48, accuracy: 0.001)
        XCTAssertFalse(concrete.configuration.isEnabled)
    }

    func testColorGradeRejectsAmbiguousWorkingColorAndAlpha() throws {
        let device = try requireMetalDevice()
        let effect = ColorGradeEffect()

        XCTAssertThrowsError(
            try effect.prepare(
                context: .init(
                    device: device,
                    workingColorSpace: .linearSRGB
                )
            )
        )
        XCTAssertThrowsError(
            try effect.prepare(
                context: .init(
                    device: device,
                    alphaMode: .premultiplied
                )
            )
        )
        XCTAssertThrowsError(
            try effect.prepare(
                context: .init(
                    device: device,
                    workingPixelFormat: .bgra8Unorm
                )
            )
        )
    }

    func testGraphRepreparesEffectsAtTheCurrentSize() throws {
        let device = try requireMetalDevice()
        let effect = ResizeTrackingEffect()
        let graph = MetalEffectGraph(effects: [effect])

        try graph.prepare(
            context: .init(device: device, workingPixelFormat: .bgra8Unorm)
        )
        try graph.resize(width: 320, height: 180)
        try graph.prepare(
            context: .init(device: device, workingPixelFormat: .bgra8Unorm)
        )

        XCTAssertEqual(effect.prepareCount, 2)
        XCTAssertEqual(effect.resizeCalls, [
            SIMD2<Int>(320, 180),
            SIMD2<Int>(320, 180),
        ])
    }

    func testGraphPassesThroughWithoutEffects() throws {
        let device = try requireMetalDevice()
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let input = try makeTexture(
            device: device,
            width: 2,
            height: 2,
            usage: [.shaderRead]
        )
        let output = try makeTexture(
            device: device,
            width: 2,
            height: 2,
            usage: [.shaderRead, .renderTarget]
        )
        let sourceBytes: [UInt8] = [
            1, 2, 3, 255, 4, 5, 6, 255,
            7, 8, 9, 255, 10, 11, 12, 255,
        ]
        input.replace(
            region: MTLRegionMake2D(0, 0, 2, 2),
            mipmapLevel: 0,
            withBytes: sourceBytes,
            bytesPerRow: 8
        )

        let graph = MetalEffectGraph()
        try graph.prepare(context: .init(device: device, workingPixelFormat: .bgra8Unorm))
        try graph.resize(width: 2, height: 2)
        let commandBuffer = try XCTUnwrap(queue.makeCommandBuffer())
        try graph.encode(
            frame: MetalEffectFrame(
                source: input,
                timing: EffectFrameTiming(
                    frameIndex: 0,
                    hostTimeNanoseconds: 0,
                    deltaSeconds: 0
                )
            ),
            to: output,
            commandBuffer: commandBuffer
        )
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        var outputBytes = [UInt8](repeating: 0, count: sourceBytes.count)
        output.getBytes(
            &outputBytes,
            bytesPerRow: 8,
            from: MTLRegionMake2D(0, 0, 2, 2),
            mipmapLevel: 0
        )
        XCTAssertEqual(outputBytes, sourceBytes)
    }

    func testGraphRejectsAnalysisTextureOutsideABI() throws {
        let device = try requireMetalDevice()
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let input = try makeTexture(
            device: device,
            width: 2,
            height: 2,
            usage: [.shaderRead]
        )
        let output = try makeTexture(
            device: device,
            width: 2,
            height: 2,
            usage: [.shaderRead, .renderTarget]
        )
        let invalidEdge = try makeTexture(
            device: device,
            width: 2,
            height: 2,
            usage: [.shaderRead]
        )
        let graph = MetalEffectGraph()
        try graph.prepare(context: .init(device: device, workingPixelFormat: .bgra8Unorm))
        try graph.resize(width: 2, height: 2)
        let commandBuffer = try XCTUnwrap(queue.makeCommandBuffer())

        XCTAssertThrowsError(
            try graph.encode(
                frame: MetalEffectFrame(
                    source: input,
                    analysisTextures: .init(edge: invalidEdge),
                    timing: EffectFrameTiming(
                        frameIndex: 0,
                        hostTimeNanoseconds: 0,
                        deltaSeconds: 0
                    )
                ),
                to: output,
                commandBuffer: commandBuffer
            )
        ) { error in
            XCTAssertEqual(
                error as? MetalEffectError,
                .incompatibleAnalysisTexture("edge")
            )
        }
    }

    private func requireMetalDevice() throws -> MTLDevice {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal is unavailable on this test host.")
        }
        return device
    }

    private func makeTexture(
        device: MTLDevice,
        width: Int,
        height: Int,
        usage: MTLTextureUsage,
        pixelFormat: MTLPixelFormat = .bgra8Unorm
    ) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.storageMode = .shared
        descriptor.usage = usage
        return try XCTUnwrap(device.makeTexture(descriptor: descriptor))
    }
}

private final class ResizeTrackingEffect: MetalEffectInstance {
    let descriptor = EffectDescriptor(
        id: "com.daito.contour-effects.test.resize",
        displayName: "Resize Tracking",
        category: .utility
    )
    var prepareCount = 0
    var resizeCalls: [SIMD2<Int>] = []

    func prepare(context _: MetalEffectHostContext) throws {
        prepareCount += 1
    }

    func resize(width: Int, height: Int) throws {
        resizeCalls.append(SIMD2(width, height))
    }

    func encode(
        frame _: MetalEffectFrame,
        to _: MTLTexture,
        commandBuffer _: MTLCommandBuffer
    ) throws {}

    func reset() {}

    func snapshotState() -> EffectStateSnapshot {
        EffectStateSnapshot(effectIdentifier: descriptor.id)
    }

    func restoreState(_: EffectStateSnapshot) throws {}
}
