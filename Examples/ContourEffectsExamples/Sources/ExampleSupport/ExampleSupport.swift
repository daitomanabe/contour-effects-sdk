// SPDX-FileCopyrightText: 2026 Daito Manabe
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
import Metal

public struct ExampleError: LocalizedError {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }
}

public func exampleRequire(
    _ condition: @autoclosure () -> Bool,
    _ message: String
) throws {
    guard condition() else { throw ExampleError(message) }
}

public func emitJSON<Value: Encodable>(_ value: Value) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(value)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data([0x0A]))
}

public func maximumAbsoluteError(
    _ lhs: [Float],
    _ rhs: [Float]
) -> Float {
    zip(lhs, rhs).map { abs($0 - $1) }.max() ?? .infinity
}

public final class MetalExampleHarness {
    public let device: MTLDevice
    public let queue: MTLCommandQueue

    public init() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw ExampleError("No Metal device is available.")
        }
        guard let queue = device.makeCommandQueue() else {
            throw ExampleError("Metal command queue creation failed.")
        }
        self.device = device
        self.queue = queue
    }

    public func makeTexture(
        pixelFormat: MTLPixelFormat,
        width: Int,
        height: Int,
        usage: MTLTextureUsage,
        label: String
    ) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.storageMode = .shared
        descriptor.usage = usage
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw ExampleError("Metal texture creation failed: \(label)")
        }
        texture.label = label
        return texture
    }

    public func fillRGBA16(
        _ texture: MTLTexture,
        color: SIMD4<Float>
    ) throws {
        try exampleRequire(
            texture.pixelFormat == .rgba16Float,
            "fillRGBA16 requires rgba16Float."
        )
        let pixel = SIMD4<Float16>(
            Float16(color.x),
            Float16(color.y),
            Float16(color.z),
            Float16(color.w)
        )
        let pixels = [SIMD4<Float16>](
            repeating: pixel,
            count: texture.width * texture.height
        )
        pixels.withUnsafeBytes { bytes in
            texture.replace(
                region: MTLRegionMake2D(0, 0, texture.width, texture.height),
                mipmapLevel: 0,
                withBytes: bytes.baseAddress!,
                bytesPerRow: texture.width
                    * MemoryLayout<SIMD4<Float16>>.stride
            )
        }
    }

    public func writeRGBA16(
        _ texture: MTLTexture,
        values: [SIMD4<Float>]
    ) throws {
        try exampleRequire(
            texture.pixelFormat == .rgba16Float,
            "writeRGBA16 requires rgba16Float."
        )
        try exampleRequire(
            values.count == texture.width * texture.height,
            "The RGBA16 fixture has an invalid sample count."
        )
        let pixels = values.map {
            SIMD4<Float16>(
                Float16($0.x),
                Float16($0.y),
                Float16($0.z),
                Float16($0.w)
            )
        }
        pixels.withUnsafeBytes { bytes in
            texture.replace(
                region: MTLRegionMake2D(0, 0, texture.width, texture.height),
                mipmapLevel: 0,
                withBytes: bytes.baseAddress!,
                bytesPerRow: texture.width
                    * MemoryLayout<SIMD4<Float16>>.stride
            )
        }
    }

    public func writeRG16(
        _ texture: MTLTexture,
        values: [SIMD2<Float>]
    ) throws {
        try exampleRequire(
            texture.pixelFormat == .rg16Float,
            "writeRG16 requires rg16Float."
        )
        try exampleRequire(
            values.count == texture.width * texture.height,
            "The RG16 fixture has an invalid sample count."
        )
        let pixels = values.map {
            SIMD2<Float16>(Float16($0.x), Float16($0.y))
        }
        pixels.withUnsafeBytes { bytes in
            texture.replace(
                region: MTLRegionMake2D(0, 0, texture.width, texture.height),
                mipmapLevel: 0,
                withBytes: bytes.baseAddress!,
                bytesPerRow: texture.width
                    * MemoryLayout<SIMD2<Float16>>.stride
            )
        }
    }

    public func writeR8(
        _ texture: MTLTexture,
        values: [UInt8]
    ) throws {
        try exampleRequire(
            texture.pixelFormat == .r8Unorm,
            "writeR8 requires r8Unorm."
        )
        try exampleRequire(
            values.count == texture.width * texture.height,
            "The R8 fixture has an invalid sample count."
        )
        values.withUnsafeBytes { bytes in
            texture.replace(
                region: MTLRegionMake2D(0, 0, texture.width, texture.height),
                mipmapLevel: 0,
                withBytes: bytes.baseAddress!,
                bytesPerRow: texture.width
            )
        }
    }

    public func readRGBA16(
        _ texture: MTLTexture,
        x: Int = 0,
        y: Int = 0
    ) throws -> [Float] {
        try exampleRequire(
            texture.pixelFormat == .rgba16Float,
            "readRGBA16 requires rgba16Float."
        )
        try exampleRequire(
            (0 ..< texture.width).contains(x)
                && (0 ..< texture.height).contains(y),
            "The requested pixel is outside the texture."
        )
        var pixel = SIMD4<Float16>(repeating: 0)
        withUnsafeMutableBytes(of: &pixel) { bytes in
            texture.getBytes(
                bytes.baseAddress!,
                bytesPerRow: MemoryLayout<SIMD4<Float16>>.stride,
                from: MTLRegionMake2D(x, y, 1, 1),
                mipmapLevel: 0
            )
        }
        return [
            Float(pixel.x),
            Float(pixel.y),
            Float(pixel.z),
            Float(pixel.w),
        ]
    }

    public func makeCommandBuffer(label: String) throws -> MTLCommandBuffer {
        guard let commandBuffer = queue.makeCommandBuffer() else {
            throw ExampleError("Metal command buffer creation failed.")
        }
        commandBuffer.label = label
        return commandBuffer
    }

    public func commitAndWait(_ commandBuffer: MTLCommandBuffer) throws {
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else {
            throw ExampleError(
                commandBuffer.error?.localizedDescription
                    ?? "Metal command failed."
            )
        }
    }
}
