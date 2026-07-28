// SPDX-FileCopyrightText: 2026 Daito Manabe
// SPDX-License-Identifier: BSD-3-Clause

import ContourEffectsCore
import Foundation
import Metal

/// Serial same-command-buffer graph with two reusable ping-pong textures.
public final class MetalEffectGraph {
    public private(set) var effects: [any MetalEffectInstance]

    private var context: MetalEffectHostContext?
    private var scratchA: MTLTexture?
    private var scratchB: MTLTexture?
    private var width = 0
    private var height = 0

    public init(effects: [any MetalEffectInstance] = []) {
        self.effects = effects
    }

    public func prepare(context: MetalEffectHostContext) throws {
        do {
            for effect in effects {
                try effect.prepare(context: context)
                if width > 0, height > 0 {
                    try effect.resize(width: width, height: height)
                }
            }
            var newScratch: (MTLTexture, MTLTexture)?
            if width > 0, height > 0 {
                newScratch = try makeScratchTextures(
                    context: context,
                    width: width,
                    height: height
                )
            }
            self.context = context
            if let newScratch {
                scratchA = newScratch.0
                scratchB = newScratch.1
            }
        } catch {
            invalidatePreparedState()
            throw error
        }
    }

    public func replaceEffects(_ effects: [any MetalEffectInstance]) throws {
        if let context {
            for effect in effects {
                try effect.prepare(context: context)
                if width > 0, height > 0 {
                    try effect.resize(width: width, height: height)
                }
            }
        }
        self.effects = effects
    }

    public func resize(width: Int, height: Int) throws {
        guard width > 0, height > 0 else {
            throw MetalEffectError.textureCreationFailed
        }
        let newScratch: (MTLTexture, MTLTexture)?
        if let context {
            newScratch = try makeScratchTextures(
                context: context,
                width: width,
                height: height
            )
        } else {
            newScratch = nil
        }
        do {
            for effect in effects {
                try effect.resize(width: width, height: height)
            }
        } catch {
            invalidatePreparedState()
            throw error
        }
        self.width = width
        self.height = height
        if let newScratch {
            scratchA = newScratch.0
            scratchB = newScratch.1
        }
    }

    public func reset() {
        effects.forEach { $0.reset() }
    }

    public func encode(
        frame: MetalEffectFrame,
        to destination: MTLTexture,
        commandBuffer: MTLCommandBuffer
    ) throws {
        guard let context else { throw MetalEffectError.notPrepared }
        try validateTexturePair(
            source: frame.source,
            destination: destination,
            expectedPixelFormat: context.workingPixelFormat,
            preparedDevice: context.device,
            commandBuffer: commandBuffer
        )
        try frame.validateResources(context: context, commandBuffer: commandBuffer)

        guard width == frame.source.width, height == frame.source.height else {
            throw MetalEffectError.resizeRequired(
                expectedWidth: frame.source.width,
                expectedHeight: frame.source.height
            )
        }

        guard !effects.isEmpty else {
            try encodeCopy(
                source: frame.source,
                destination: destination,
                commandBuffer: commandBuffer
            )
            return
        }

        guard let scratchA, let scratchB else {
            throw MetalEffectError.textureCreationFailed
        }

        var currentFrame = frame
        for (index, effect) in effects.enumerated() {
            try currentFrame.validate(requiredInputs: effect.descriptor.requiredInputs)
            let isLast = index == effects.index(before: effects.endIndex)
            let output: MTLTexture
            if isLast {
                output = destination
            } else {
                output = index.isMultiple(of: 2) ? scratchA : scratchB
            }
            try effect.encode(
                frame: currentFrame,
                to: output,
                commandBuffer: commandBuffer
            )
            currentFrame = currentFrame.replacingSource(output)
        }
    }

    private func makeScratchTextures(
        context: MetalEffectHostContext,
        width: Int,
        height: Int
    ) throws -> (MTLTexture, MTLTexture) {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: context.workingPixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.storageMode = .private
        descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        guard let scratchA = context.device.makeTexture(descriptor: descriptor),
              let scratchB = context.device.makeTexture(descriptor: descriptor)
        else {
            throw MetalEffectError.textureCreationFailed
        }
        scratchA.label = "ContourEffectsMetal Graph Scratch A"
        scratchB.label = "ContourEffectsMetal Graph Scratch B"
        return (scratchA, scratchB)
    }

    private func encodeCopy(
        source: MTLTexture,
        destination: MTLTexture,
        commandBuffer: MTLCommandBuffer
    ) throws {
        guard let encoder = commandBuffer.makeBlitCommandEncoder() else {
            throw MetalEffectError.incompatibleDestination
        }
        encoder.label = "ContourEffectsMetal Graph Passthrough"
        encoder.copy(
            from: source,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: .init(x: 0, y: 0, z: 0),
            sourceSize: .init(width: source.width, height: source.height, depth: 1),
            to: destination,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: .init(x: 0, y: 0, z: 0)
        )
        encoder.endEncoding()
    }

    private func invalidatePreparedState() {
        context = nil
        scratchA = nil
        scratchB = nil
        width = 0
        height = 0
    }
}
