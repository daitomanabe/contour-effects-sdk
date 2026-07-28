// SPDX-FileCopyrightText: 2026 Daito Manabe
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
import Metal

public enum CubeLUTError: LocalizedError, Equatable {
    case unreadable
    case unsupportedOneDimensional
    case missingSize
    case invalidSize(Int)
    case invalidDomain
    case invalidSample(String)
    case sampleOutsideHalfFloatRange(String)
    case sampleCount(expected: Int, actual: Int)
    case textureCreationFailed

    public var errorDescription: String? {
        switch self {
        case .unreadable: return "The .cube LUT could not be read as UTF-8 text."
        case .unsupportedOneDimensional: return "Only 3D .cube LUTs are supported."
        case .missingSize: return "The LUT_3D_SIZE declaration is missing."
        case let .invalidSize(size):
            return "LUT_3D_SIZE \(size) is outside the supported 2...64 range."
        case .invalidDomain:
            return "DOMAIN_MIN and DOMAIN_MAX must describe a non-zero RGB range."
        case let .invalidSample(line):
            return "Invalid RGB sample in .cube LUT: \(line)"
        case let .sampleOutsideHalfFloatRange(line):
            return "RGB sample cannot be represented by the rgba16Float LUT texture: \(line)"
        case let .sampleCount(expected, actual):
            return "The LUT contains \(actual) RGB samples; \(expected) are required."
        case .textureCreationFailed:
            return "Metal could not allocate the 3D LUT texture."
        }
    }
}

public struct CubeLUT: Sendable, Equatable {
    public let title: String
    public let size: Int
    public let domainMinimum: SIMD3<Float>
    public let domainMaximum: SIMD3<Float>
    /// Resolve/Adobe .cube order: red changes fastest, then green, then blue.
    public let samples: [SIMD3<Float>]

    public init(
        title: String,
        size: Int,
        domainMinimum: SIMD3<Float>,
        domainMaximum: SIMD3<Float>,
        samples: [SIMD3<Float>]
    ) throws {
        try Self.validate(
            size: size,
            domainMinimum: domainMinimum,
            domainMaximum: domainMaximum,
            samples: samples
        )
        self.title = title
        self.size = size
        self.domainMinimum = domainMinimum
        self.domainMaximum = domainMaximum
        self.samples = samples
    }

    public static func load(from url: URL) throws -> Self {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw CubeLUTError.unreadable
        }
        return try parse(text)
    }

    public static func parse(_ text: String) throws -> Self {
        var title = "UNTITLED LUT"
        var size: Int?
        var domainMinimum = SIMD3<Float>(repeating: 0)
        var domainMaximum = SIMD3<Float>(repeating: 1)
        var samples: [SIMD3<Float>] = []

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine
                .split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if line.hasPrefix("TITLE") {
                let value = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                title = value.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                continue
            }
            if line.hasPrefix("LUT_1D_SIZE") {
                throw CubeLUTError.unsupportedOneDimensional
            }
            if line.hasPrefix("LUT_3D_SIZE") {
                let fields = line.split(whereSeparator: \.isWhitespace)
                guard fields.count == 2, let parsed = Int(fields[1]) else {
                    throw CubeLUTError.missingSize
                }
                guard (2 ... 64).contains(parsed) else {
                    throw CubeLUTError.invalidSize(parsed)
                }
                size = parsed
                samples.reserveCapacity(parsed * parsed * parsed)
                continue
            }
            if line.hasPrefix("DOMAIN_MIN") || line.hasPrefix("DOMAIN_MAX") {
                let fields = line.split(whereSeparator: \.isWhitespace)
                guard fields.count == 4,
                      let x = Float(fields[1]),
                      let y = Float(fields[2]),
                      let z = Float(fields[3])
                else {
                    throw CubeLUTError.invalidDomain
                }
                if fields[0] == "DOMAIN_MIN" {
                    domainMinimum = SIMD3(x, y, z)
                } else {
                    domainMaximum = SIMD3(x, y, z)
                }
                continue
            }

            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count == 3,
                  let red = Float(fields[0]),
                  let green = Float(fields[1]),
                  let blue = Float(fields[2]),
                  red.isFinite, green.isFinite, blue.isFinite
            else {
                throw CubeLUTError.invalidSample(line)
            }
            samples.append(SIMD3(red, green, blue))
        }

        guard let size else { throw CubeLUTError.missingSize }
        guard domainMaximum.x > domainMinimum.x,
              domainMaximum.y > domainMinimum.y,
              domainMaximum.z > domainMinimum.z
        else {
            throw CubeLUTError.invalidDomain
        }
        let expected = size * size * size
        guard samples.count == expected else {
            throw CubeLUTError.sampleCount(expected: expected, actual: samples.count)
        }
        return try Self(
            title: title,
            size: size,
            domainMinimum: domainMinimum,
            domainMaximum: domainMaximum,
            samples: samples
        )
    }

    public func makeTexture(device: MTLDevice) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type3D
        descriptor.pixelFormat = .rgba16Float
        descriptor.width = size
        descriptor.height = size
        descriptor.depth = size
        descriptor.mipmapLevelCount = 1
        descriptor.storageMode = .shared
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw CubeLUTError.textureCreationFailed
        }
        texture.label = "ContourEffects LUT · \(title)"

        var texels = [SIMD4<Float16>]()
        texels.reserveCapacity(samples.count)
        for sample in samples {
            texels.append(SIMD4(
                Float16(sample.x),
                Float16(sample.y),
                Float16(sample.z),
                Float16(1)
            ))
        }
        texels.withUnsafeBytes { bytes in
            texture.replace(
                region: MTLRegionMake3D(0, 0, 0, size, size, size),
                mipmapLevel: 0,
                slice: 0,
                withBytes: bytes.baseAddress!,
                bytesPerRow: size * MemoryLayout<SIMD4<Float16>>.stride,
                bytesPerImage: size * size * MemoryLayout<SIMD4<Float16>>.stride
            )
        }
        return texture
    }

    private static func validate(
        size: Int,
        domainMinimum: SIMD3<Float>,
        domainMaximum: SIMD3<Float>,
        samples: [SIMD3<Float>]
    ) throws {
        guard (2 ... 64).contains(size) else {
            throw CubeLUTError.invalidSize(size)
        }
        guard domainMinimum.x.isFinite,
              domainMinimum.y.isFinite,
              domainMinimum.z.isFinite,
              domainMaximum.x.isFinite,
              domainMaximum.y.isFinite,
              domainMaximum.z.isFinite,
              domainMaximum.x > domainMinimum.x,
              domainMaximum.y > domainMinimum.y,
              domainMaximum.z > domainMinimum.z
        else {
            throw CubeLUTError.invalidDomain
        }
        let expected = size * size * size
        guard samples.count == expected else {
            throw CubeLUTError.sampleCount(expected: expected, actual: samples.count)
        }
        for (index, sample) in samples.enumerated() {
            guard sample.x.isFinite, sample.y.isFinite, sample.z.isFinite else {
                throw CubeLUTError.invalidSample("sample \(index)")
            }
            guard Float16(sample.x).isFinite,
                  Float16(sample.y).isFinite,
                  Float16(sample.z).isFinite
            else {
                throw CubeLUTError.sampleOutsideHalfFloatRange(
                    "sample \(index)"
                )
            }
        }
    }
}

public final class MetalLUT3D {
    public let identifier: String
    public let texture: MTLTexture
    public let domainMinimum: SIMD3<Float>
    public let domainMaximum: SIMD3<Float>

    public init(
        identifier: String,
        texture: MTLTexture,
        domainMinimum: SIMD3<Float> = .zero,
        domainMaximum: SIMD3<Float> = SIMD3<Float>(repeating: 1)
    ) throws {
        guard texture.textureType == .type3D,
              texture.pixelFormat == .rgba16Float,
              texture.width >= 2,
              texture.width == texture.height,
              texture.width == texture.depth,
              texture.usage.contains(.shaderRead)
        else {
            throw CubeLUTError.textureCreationFailed
        }
        guard domainMinimum.x.isFinite,
              domainMinimum.y.isFinite,
              domainMinimum.z.isFinite,
              domainMaximum.x.isFinite,
              domainMaximum.y.isFinite,
              domainMaximum.z.isFinite,
              domainMaximum.x > domainMinimum.x,
              domainMaximum.y > domainMinimum.y,
              domainMaximum.z > domainMinimum.z
        else {
            throw CubeLUTError.invalidDomain
        }
        self.identifier = identifier
        self.texture = texture
        self.domainMinimum = domainMinimum
        self.domainMaximum = domainMaximum
    }

    public convenience init(
        identifier: String,
        cube: CubeLUT,
        device: MTLDevice
    ) throws {
        try self.init(
            identifier: identifier,
            texture: cube.makeTexture(device: device),
            domainMinimum: cube.domainMinimum,
            domainMaximum: cube.domainMaximum
        )
    }
}
