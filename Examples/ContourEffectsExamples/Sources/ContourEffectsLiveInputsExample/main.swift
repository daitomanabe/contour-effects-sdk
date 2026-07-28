// SPDX-FileCopyrightText: 2026 Daito Manabe
// SPDX-License-Identifier: BSD-3-Clause

import ContourEffectsCore
import ContourEffectsMetal
import ExampleSupport
import Foundation
import Metal

private struct CodableLiveState: Codable, Equatable {
    var macros: EffectPerformanceMacros
    var timing: EffectFrameTiming
}

private struct AudioReport: Codable {
    var source: String
    var isLive: Bool
    var volume: Float
    var low: Float
    var mid: Float
    var high: Float
    var beat: Float
    var attack: Float
    var spectrum: [Float]
    var timestamp: TimeInterval
}

private struct ObservationReport: Codable {
    var featurePointCount: Int
    var handPointCount: Int
    var bodyPointCount: Int
    var detectionCount: Int
    var indexTipValid: Bool
    var missingPointInvalid: Bool
    var detectionID: UInt32
    var detectionVelocityX: Float
    var detectionVelocityY: Float
}

private struct AvailabilityReport: Codable {
    var populatedInputs: UInt64
    var emptyProviderInputs: UInt64
    var emptyProvidersRemainAvailable: Bool
    var textureFlagsCannotBeForged: Bool
}

private struct LiveInputsReport: Codable {
    var selfCheck: Bool
    var device: String
    var audio: AudioReport
    var macros: EffectPerformanceMacros
    var timing: EffectFrameTiming
    var codableRoundTrip: Bool
    var observations: ObservationReport
    var availability: AvailabilityReport
}

@main
private enum LiveInputsExample {
    static func main() throws {
        let harness = try MetalExampleHarness()
        let source = try harness.makeTexture(
            pixelFormat: .rgba16Float,
            width: 1,
            height: 1,
            usage: .shaderRead,
            label: "Live Inputs Example Source"
        )

        let audio = EffectAudioFeatures(
            source: .osc,
            isLive: true,
            volume: 1.25,
            low: -0.2,
            mid: 0.5,
            high: 2,
            beat: 0.9,
            attack: .nan,
            spectrum: [-0.1, 0.25, 1.5, .infinity, 0.75],
            timestamp: 1_234.5
        ).clamped(maximumBandCount: 4)
        let expectedAudio = EffectAudioFeatures(
            source: .osc,
            isLive: true,
            volume: 1,
            low: 0,
            mid: 0.5,
            high: 1,
            beat: 0.9,
            attack: 0,
            spectrum: [0, 0.25, 1, 0],
            timestamp: 1_234.5
        )
        try exampleRequire(
            audio == expectedAudio,
            "Audio features were not clamped to the documented ABI."
        )

        let macros = EffectPerformanceMacros(
            energy: -1,
            motion: 0.25,
            density: 1.5,
            audioReactive: 0.75,
            color: .nan,
            glitch: .infinity,
            feedback: 0.5,
            texture: 2
        ).clamped()
        let expectedMacros = EffectPerformanceMacros(
            energy: 0,
            motion: 0.25,
            density: 1,
            audioReactive: 0.75,
            color: 0,
            glitch: 0,
            feedback: 0.5,
            texture: 1
        )
        try exampleRequire(
            macros == expectedMacros,
            "Performance macros were not clamped to the documented ABI."
        )

        let timing = EffectFrameTiming(
            frameIndex: 120,
            inputSequence: 42,
            hostTimeNanoseconds: 9_876_543_210,
            deltaSeconds: 1.0 / 60.0,
            inputPresentationSeconds: 4,
            renderPresentationSeconds: 4.0125
        )
        let codableState = CodableLiveState(macros: macros, timing: timing)
        let encodedState = try JSONEncoder().encode(codableState)
        let decodedState = try JSONDecoder().decode(
            CodableLiveState.self,
            from: encodedState
        )
        let codableRoundTrip = decodedState == codableState
        try exampleRequire(
            codableRoundTrip,
            "Macro and timing values did not survive JSON round-tripping."
        )

        let featurePoints = [
            EffectPoint(x: 0.12, y: 0.24, confidence: 0.82),
            EffectPoint(x: 0.78, y: 0.31, confidence: 0.74),
        ]
        try exampleRequire(
            featurePoints.allSatisfy(\.isValid),
            "The feature-point fixture is outside the source-normalized ABI."
        )

        var handPoints = [EffectPoint](
            repeating: .missing,
            count: EffectHandJoint.allCases.count
        )
        let wrist = EffectPoint(x: 0.5, y: 0.9, confidence: 0.97)
        let indexTip = EffectPoint(x: 0.72, y: 0.18, confidence: 0.91)
        handPoints[EffectHandJoint.wrist.rawValue] = wrist
        handPoints[EffectHandJoint.indexTip.rawValue] = indexTip
        let hand = EffectLandmarkSet(id: "hand-left-0", points: handPoints)

        var bodyPoints = [EffectPoint](
            repeating: .missing,
            count: EffectBodyJoint.allCases.count
        )
        bodyPoints[EffectBodyJoint.root.rawValue] = EffectPoint(
            x: 0.5,
            y: 0.55,
            confidence: 0.99
        )
        bodyPoints[EffectBodyJoint.leftWrist.rawValue] = EffectPoint(
            x: 0.2,
            y: 0.45,
            confidence: 0.85
        )
        bodyPoints[EffectBodyJoint.rightWrist.rawValue] = EffectPoint(
            x: 0.8,
            y: 0.45,
            confidence: 0.86
        )
        let body = EffectLandmarkSet(id: "body-0", points: bodyPoints)

        try exampleRequire(
            EffectHandJoint.allCases.count == 21
                && hand.points.count == 21,
            "The hand fixture does not use the 21-point ABI."
        )
        try exampleRequire(
            EffectBodyJoint.allCases.count == 19
                && body.points.count == 19,
            "The body fixture does not use the 19-point ABI."
        )
        try exampleRequire(
            hand.points[EffectHandJoint.wrist.rawValue] == wrist
                && hand.points[EffectHandJoint.indexTip.rawValue] == indexTip,
            "The hand fixture does not follow EffectHandJoint order."
        )
        try exampleRequire(
            indexTip.isValid && !EffectPoint.missing.isValid,
            "Landmark validity does not match the missing-point contract."
        )

        let detection = EffectObjectDetection(
            id: 42,
            label: "person",
            confidence: 0.93,
            boundingBox: EffectRect(
                x: 0.2,
                y: 0.1,
                width: 0.5,
                height: 0.8
            ),
            velocityX: 0.012,
            velocityY: -0.004
        )
        try exampleRequire(
            detection.id == 42
                && detection.label == "person"
                && detection.confidence == 0.93
                && detection.boundingBox == EffectRect(
                    x: 0.2,
                    y: 0.1,
                    width: 0.5,
                    height: 0.8
                )
                && detection.velocityX == 0.012
                && detection.velocityY == -0.004,
            "The detection fixture did not preserve tracking values."
        )

        let populatedFrame = MetalEffectFrame(
            source: source,
            featurePoints: featurePoints,
            handLandmarks: [hand],
            bodyLandmarks: [body],
            detections: [detection],
            audio: audio,
            macros: macros,
            timing: timing
        )
        let providerInputs: EffectInputRequirements = [
            .featurePoints,
            .handLandmarks,
            .bodyLandmarks,
            .objectDetections,
            .audio,
            .performanceMacros,
        ]
        try populatedFrame.validate(requiredInputs: providerInputs)

        let emptyProviderFrame = MetalEffectFrame(
            source: source,
            timing: timing,
            providedInputs: providerInputs
        )
        let emptyProvidersRemainAvailable =
            providerInputs.subtracting(emptyProviderFrame.availableInputs)
            .isEmpty
        try exampleRequire(
            emptyProvidersRemainAvailable,
            "Empty successful provider results were reported as unavailable."
        )

        let forgedTextureFrame = MetalEffectFrame(
            source: source,
            timing: timing,
            providedInputs: [.edge, .depth, .rawCameraColor]
        )
        let forgedTextureInputs: EffectInputRequirements = [
            .edge,
            .depth,
            .rawCameraColor,
        ]
        let textureFlagsCannotBeForged =
            forgedTextureFrame.availableInputs
            .intersection(forgedTextureInputs)
            .isEmpty
        try exampleRequire(
            textureFlagsCannotBeForged,
            "Provider flags forged missing GPU texture availability."
        )

        try emitJSON(
            LiveInputsReport(
                selfCheck: true,
                device: harness.device.name,
                audio: AudioReport(
                    source: audio.source.rawValue,
                    isLive: audio.isLive,
                    volume: audio.volume,
                    low: audio.low,
                    mid: audio.mid,
                    high: audio.high,
                    beat: audio.beat,
                    attack: audio.attack,
                    spectrum: audio.spectrum,
                    timestamp: audio.timestamp
                ),
                macros: macros,
                timing: timing,
                codableRoundTrip: codableRoundTrip,
                observations: ObservationReport(
                    featurePointCount: featurePoints.count,
                    handPointCount: hand.points.count,
                    bodyPointCount: body.points.count,
                    detectionCount: 1,
                    indexTipValid: indexTip.isValid,
                    missingPointInvalid: !EffectPoint.missing.isValid,
                    detectionID: detection.id,
                    detectionVelocityX: detection.velocityX,
                    detectionVelocityY: detection.velocityY
                ),
                availability: AvailabilityReport(
                    populatedInputs: populatedFrame.availableInputs.rawValue,
                    emptyProviderInputs:
                        emptyProviderFrame.availableInputs.rawValue,
                    emptyProvidersRemainAvailable:
                        emptyProvidersRemainAvailable,
                    textureFlagsCannotBeForged: textureFlagsCannotBeForged
                )
            )
        )
    }
}
