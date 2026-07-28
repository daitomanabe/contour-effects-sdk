// SPDX-FileCopyrightText: 2026 Daito Manabe
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// A top-left-origin point normalized to the source frame.
///
/// Valid points use finite `x` and `y` values in 0...1 and confidence in
/// 0...1. Fixed-order landmark arrays use `missing` when a joint was not
/// observed, instead of changing their element count.
public struct EffectPoint: Codable, Equatable, Sendable {
    public var x: Float
    public var y: Float
    public var confidence: Float

    public init(x: Float, y: Float, confidence: Float = 1) {
        self.x = x
        self.y = y
        self.confidence = confidence
    }

    public static let missing = Self(x: -1, y: -1, confidence: 0)

    public var isValid: Bool {
        x.isFinite
            && y.isFinite
            && confidence.isFinite
            && (0 ... 1).contains(x)
            && (0 ... 1).contains(y)
            && (0 ... 1).contains(confidence)
    }
}

/// A top-left-origin rectangle normalized to the source frame.
///
/// Hosts provide finite values and keep the rectangle inside 0...1 source UV.
public struct EffectRect: Codable, Equatable, Sendable {
    public var x: Float
    public var y: Float
    public var width: Float
    public var height: Float

    public init(x: Float, y: Float, width: Float, height: Float) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct EffectLandmarkSet: Codable, Equatable, Sendable, Identifiable {
    /// Stable while the provider continues tracking the same subject.
    public var id: String
    public var points: [EffectPoint]

    public init(id: String, points: [EffectPoint]) {
        self.id = id
        self.points = points
    }
}

/// ABI 1.0 order for the 21 points in every hand landmark set.
public enum EffectHandJoint: Int, Codable, CaseIterable, Sendable {
    case wrist
    case thumbCMC
    case thumbMP
    case thumbIP
    case thumbTip
    case indexMCP
    case indexPIP
    case indexDIP
    case indexTip
    case middleMCP
    case middlePIP
    case middleDIP
    case middleTip
    case ringMCP
    case ringPIP
    case ringDIP
    case ringTip
    case littleMCP
    case littlePIP
    case littleDIP
    case littleTip
}

/// ABI 1.0 order for the 19 points in every body landmark set.
public enum EffectBodyJoint: Int, Codable, CaseIterable, Sendable {
    case root
    case neck
    case nose
    case leftEye
    case rightEye
    case leftEar
    case rightEar
    case leftShoulder
    case rightShoulder
    case leftElbow
    case rightElbow
    case leftWrist
    case rightWrist
    case leftHip
    case rightHip
    case leftKnee
    case rightKnee
    case leftAnkle
    case rightAnkle
}

public struct EffectObjectDetection: Codable, Equatable, Sendable, Identifiable {
    /// Stable until track loss and not reused within one source generation.
    public var id: UInt32
    public var label: String
    public var confidence: Float
    public var boundingBox: EffectRect
    /// Source-normalized displacement divided by the input-sequence delta;
    /// +X is right.
    public var velocityX: Float
    /// Source-normalized displacement divided by the input-sequence delta;
    /// +Y is down.
    public var velocityY: Float

    public init(
        id: UInt32,
        label: String,
        confidence: Float,
        boundingBox: EffectRect,
        velocityX: Float = 0,
        velocityY: Float = 0
    ) {
        self.id = id
        self.label = label
        self.confidence = confidence
        self.boundingBox = boundingBox
        self.velocityX = velocityX
        self.velocityY = velocityY
    }
}
