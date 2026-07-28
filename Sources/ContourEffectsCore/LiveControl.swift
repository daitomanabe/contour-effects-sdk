// SPDX-FileCopyrightText: 2026 Daito Manabe
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// Audio data consumed by effects independently of the host transport.
///
/// A host may populate this from OSC (`/vol`, `/fft`, `/attack`), an audio
/// engine, or another source. Values are normalized by `clamped()`.
public enum EffectAudioSource: String, Codable, Sendable {
    case none
    case host
    case system
    case osc
}

public struct EffectAudioFeatures: Equatable, Sendable {
    public var source: EffectAudioSource
    public var isLive: Bool
    public var volume: Float
    public var low: Float
    public var mid: Float
    public var high: Float
    public var beat: Float
    public var attack: Float
    public var spectrum: [Float]
    public var timestamp: TimeInterval

    public init(
        source: EffectAudioSource = .none,
        isLive: Bool = false,
        volume: Float = 0,
        low: Float = 0,
        mid: Float = 0,
        high: Float = 0,
        beat: Float = 0,
        attack: Float = 0,
        spectrum: [Float] = [],
        timestamp: TimeInterval = 0
    ) {
        self.source = source
        self.isLive = isLive
        self.volume = volume
        self.low = low
        self.mid = mid
        self.high = high
        self.beat = beat
        self.attack = attack
        self.spectrum = spectrum
        self.timestamp = timestamp
    }

    public static let zero = Self()

    public func clamped(maximumBandCount: Int = 128) -> Self {
        Self(
            source: source,
            isLive: isLive,
            volume: volume.normalized,
            low: low.normalized,
            mid: mid.normalized,
            high: high.normalized,
            beat: beat.normalized,
            attack: attack.normalized,
            spectrum: spectrum.prefix(max(0, maximumBandCount)).map(\.normalized),
            timestamp: timestamp
        )
    }
}

/// The eight semantic live controls shared by ContourEffects effects.
public struct EffectPerformanceMacros: Codable, Equatable, Sendable {
    public var energy: Float
    public var motion: Float
    public var density: Float
    public var audioReactive: Float
    public var color: Float
    public var glitch: Float
    public var feedback: Float
    public var texture: Float

    public init(
        energy: Float = 0,
        motion: Float = 0,
        density: Float = 0,
        audioReactive: Float = 0,
        color: Float = 0,
        glitch: Float = 0,
        feedback: Float = 0,
        texture: Float = 0
    ) {
        self.energy = energy
        self.motion = motion
        self.density = density
        self.audioReactive = audioReactive
        self.color = color
        self.glitch = glitch
        self.feedback = feedback
        self.texture = texture
    }

    public static let zero = Self()

    public func clamped() -> Self {
        Self(
            energy: energy.normalized,
            motion: motion.normalized,
            density: density.normalized,
            audioReactive: audioReactive.normalized,
            color: color.normalized,
            glitch: glitch.normalized,
            feedback: feedback.normalized,
            texture: texture.normalized
        )
    }
}

private extension Float {
    var normalized: Float {
        guard isFinite else { return 0 }
        return min(max(self, 0), 1)
    }
}
