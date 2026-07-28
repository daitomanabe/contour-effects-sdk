// SPDX-FileCopyrightText: 2026 Daito Manabe
// SPDX-License-Identifier: BSD-3-Clause

import ContourEffectsCore
import ContourEffectsMetal
import Foundation
import Metal

private enum SmokeError: LocalizedError {
    case noMetalDevice
    case commandQueue
    case texture
    case commandBuffer
    case incompatibleHost(String)
    case gpu(String)

    var errorDescription: String? {
        switch self {
        case .noMetalDevice:
            return "No Metal device is available."
        case .commandQueue:
            return "Metal command queue creation failed."
        case .texture:
            return "Metal texture creation failed."
        case .commandBuffer:
            return "Metal command buffer creation failed."
        case let .incompatibleHost(message):
            return "The host cannot run the effect: \(message)"
        case let .gpu(message):
            return "Metal command failed: \(message)"
        }
    }
}

@main
private enum MinimalContourEffectsHost {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw SmokeError.noMetalDevice
        }
        guard let queue = device.makeCommandQueue() else {
            throw SmokeError.commandQueue
        }

        let descriptor = ColorGradeEffect.effectDescriptor
        try descriptor.validate()
        let compatibility = HostCapabilities().compatibility(with: descriptor)
        guard compatibility.canRun else {
            throw SmokeError.incompatibleHost(
                "missing inputs \(compatibility.missingInputs.rawValue)"
            )
        }

        var configuration = ColorGradeConfiguration()
        configuration.applyLook(.cinema)
        let effect = ColorGradeEffect(configuration: configuration)
        let graph = MetalEffectGraph(effects: [effect])
        let context = MetalEffectHostContext(
            device: device,
            workingPixelFormat: .rgba16Float
        )
        try graph.prepare(context: context)
        try graph.resize(width: 64, height: 64)

        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: 64,
            height: 64,
            mipmapped: false
        )
        textureDescriptor.storageMode = .shared
        textureDescriptor.usage = [.shaderRead, .renderTarget]
        guard let source = device.makeTexture(descriptor: textureDescriptor),
              let destination = device.makeTexture(descriptor: textureDescriptor)
        else {
            throw SmokeError.texture
        }
        writeTestColor(to: source)

        guard let commandBuffer = queue.makeCommandBuffer() else {
            throw SmokeError.commandBuffer
        }
        let frame = MetalEffectFrame(
            source: source,
            timing: EffectFrameTiming(
                frameIndex: 0,
                inputSequence: 1,
                hostTimeNanoseconds: DispatchTime.now().uptimeNanoseconds,
                deltaSeconds: 1.0 / 60.0,
                inputPresentationSeconds: 0,
                renderPresentationSeconds: 0
            )
        )
        try graph.encode(
            frame: frame,
            to: destination,
            commandBuffer: commandBuffer
        )
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else {
            throw SmokeError.gpu(
                commandBuffer.error?.localizedDescription ?? "unknown failure"
            )
        }

        let output = readFirstPixel(from: destination)
        guard output.allSatisfy(\.isFinite) else {
            throw SmokeError.gpu("the output contains a non-finite component")
        }
        print(
            "ContourEffects SDK \(ContourEffectsSDK.apiVersion.major)."
                + "\(ContourEffectsSDK.apiVersion.minor)"
                + " | effects=\(ContourEffectsMetalCatalog.descriptors.count)"
                + " | device=\(device.name)"
                + " | firstPixel=\(output)"
        )
    }

    private static func writeTestColor(to texture: MTLTexture) {
        let pixel = SIMD4<Float16>(0.18, 0.42, 0.76, 1)
        let pixels = [SIMD4<Float16>](
            repeating: pixel,
            count: texture.width * texture.height
        )
        pixels.withUnsafeBytes { bytes in
            texture.replace(
                region: MTLRegionMake2D(0, 0, texture.width, texture.height),
                mipmapLevel: 0,
                withBytes: bytes.baseAddress!,
                bytesPerRow: texture.width * MemoryLayout<SIMD4<Float16>>.stride
            )
        }
    }

    private static func readFirstPixel(from texture: MTLTexture) -> [Float] {
        var pixel = SIMD4<Float16>()
        withUnsafeMutableBytes(of: &pixel) { bytes in
            texture.getBytes(
                bytes.baseAddress!,
                bytesPerRow: MemoryLayout<SIMD4<Float16>>.stride,
                from: MTLRegionMake2D(0, 0, 1, 1),
                mipmapLevel: 0
            )
        }
        return [Float(pixel.x), Float(pixel.y), Float(pixel.z), Float(pixel.w)]
    }
}
