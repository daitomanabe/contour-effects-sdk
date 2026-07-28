// SPDX-FileCopyrightText: 2026 Daito Manabe
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// Timing shared by every effect encoded for one output frame.
///
/// Hosts should propagate the original capture PTS and a stable input sequence
/// through all asynchronous analysis providers. A zero `inputSequence` means
/// the host cannot identify capture frames.
public struct EffectFrameTiming: Codable, Equatable, Sendable {
    public var frameIndex: UInt64
    public var inputSequence: UInt64
    public var hostTimeNanoseconds: UInt64
    public var deltaSeconds: Double
    public var inputPresentationSeconds: Double?
    public var renderPresentationSeconds: Double?

    public init(
        frameIndex: UInt64,
        inputSequence: UInt64 = 0,
        hostTimeNanoseconds: UInt64,
        deltaSeconds: Double,
        inputPresentationSeconds: Double? = nil,
        renderPresentationSeconds: Double? = nil
    ) {
        self.frameIndex = frameIndex
        self.inputSequence = inputSequence
        self.hostTimeNanoseconds = hostTimeNanoseconds
        self.deltaSeconds = deltaSeconds
        self.inputPresentationSeconds = inputPresentationSeconds
        self.renderPresentationSeconds = renderPresentationSeconds
    }
}
