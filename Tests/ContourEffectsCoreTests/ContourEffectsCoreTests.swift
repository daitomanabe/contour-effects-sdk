// SPDX-FileCopyrightText: 2026 Daito Manabe
// SPDX-License-Identifier: BSD-3-Clause

import XCTest
import ContourEffectsCore

final class ContourEffectsCoreTests: XCTestCase {
    func testEffectValueUsesPlainJSONAndPreservesUnknownState() throws {
        let state = EffectStateSnapshot(
            effectIdentifier: "com.daito.contour-effects.test",
            schemaVersion: 7,
            values: [
            "enabled": .bool(true),
            "amount": .number(0.75),
            "future": .object([
                "name": .string("kept"),
                "values": .array([.number(1), .null]),
            ]),
        ])

        let data = try JSONEncoder().encode(state)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let values = try XCTUnwrap(object["values"] as? [String: Any])
        XCTAssertEqual(values["amount"] as? Double, 0.75)
        XCTAssertEqual(
            try JSONDecoder().decode(EffectStateSnapshot.self, from: data),
            state
        )
    }

    func testDescriptorRoundTripsRequirementsAndDependencies() throws {
        let descriptor = EffectDescriptor(
            id: "com.daito.contour-effects.test",
            displayName: "Test Effect",
            category: .fluid,
            executionModel: .temporal,
            requiredInputs: [.composedColor, .personMask, .opticalFlow, .audio],
            parameters: [
                EffectParameterDescriptor(
                    identifier: "amount",
                    displayName: "Amount",
                    kind: .float,
                    defaultValue: .number(0.5),
                    minimum: 0,
                    maximum: 1
                ),
            ],
            optionalDependencies: [.appleVision]
        )

        let data = try JSONEncoder().encode(descriptor)
        let decoded = try JSONDecoder().decode(EffectDescriptor.self, from: data)
        XCTAssertEqual(decoded, descriptor)
        XCTAssertTrue(decoded.requiredInputs.contains(.opticalFlow))
        XCTAssertFalse(decoded.requiredInputs.contains(.depth))
    }

    func testTimingCarriesCaptureIdentity() {
        let inputPTS = 1_001.0 / 30_000.0
        let timing = EffectFrameTiming(
            frameIndex: 42,
            inputSequence: 17,
            hostTimeNanoseconds: 123,
            deltaSeconds: 1.0 / 60.0,
            inputPresentationSeconds: inputPTS,
            renderPresentationSeconds: 2.0 / 60.0
        )

        XCTAssertEqual(timing.inputPresentationSeconds, inputPTS)
        XCTAssertEqual(timing.inputSequence, 17)
    }

    func testLiveControlsClampUnsafeTransportValues() {
        let audio = EffectAudioFeatures(
            volume: 1.4,
            beat: -.infinity,
            attack: .nan,
            spectrum: [-1, 0.4, 2, .infinity]
        ).clamped(maximumBandCount: 3)
        XCTAssertEqual(audio.volume, 1)
        XCTAssertEqual(audio.beat, 0)
        XCTAssertEqual(audio.attack, 0)
        XCTAssertEqual(audio.spectrum, [0, 0.4, 1])

        let macros = EffectPerformanceMacros(
            energy: -1,
            motion: 0.5,
            density: 2,
            audioReactive: .nan
        ).clamped()
        XCTAssertEqual(macros.energy, 0)
        XCTAssertEqual(macros.motion, 0.5)
        XCTAssertEqual(macros.density, 1)
        XCTAssertEqual(macros.audioReactive, 0)
    }

    func testHostCompatibilityReportsRequiredInputGaps() {
        let effect = EffectDescriptor(
            id: "com.daito.contour-effects.flow",
            displayName: "Flow",
            category: .distortion,
            requiredInputs: [.composedColor, .edge, .opticalFlow, .audio],
            optionalDependencies: [.glicMetal]
        )
        let host = HostCapabilities(availableInputs: [.composedColor, .edge])
        let report = host.compatibility(with: effect)

        XCTAssertFalse(report.canRun)
        XCTAssertEqual(report.missingInputs, [.opticalFlow, .audio])
        XCTAssertEqual(report.missingOptionalDependencies, [.glicMetal])
        XCTAssertTrue(report.missingRequiredDependencies.isEmpty)
    }

    func testEveryDependencyIDHasOneDescriptor() {
        XCTAssertEqual(
            Set(ContourEffectsDependencies.all.map(\.id)),
            Set(ContourEffectsDependencyID.allCases)
        )
        XCTAssertEqual(
            Set(ContourEffectsDependencies.all.map(\.id)).count,
            ContourEffectsDependencies.all.count
        )
        XCTAssertTrue(
            ContourEffectsDependencies.descriptor(for: .glicMetal).isOptional
        )
        XCTAssertEqual(
            ContourEffectsDependencies.descriptor(for: .syphon).distribution,
            .framework
        )
    }

    func testDescriptorValidationRejectsOverlappingInputs() {
        let descriptor = EffectDescriptor(
            id: "com.daito.invalid",
            displayName: "Invalid",
            category: .utility,
            requiredInputs: [.edge],
            optionalInputs: [.edge]
        )
        XCTAssertThrowsError(try descriptor.validate()) { error in
            XCTAssertEqual(
                error as? EffectDescriptorValidationError,
                .overlappingInputs
            )
        }
    }

    func testParameterValidationRejectsTypeRangeAndUnknownChoice() throws {
        let amount = EffectParameterDescriptor(
            identifier: "amount",
            displayName: "Amount",
            kind: .float,
            defaultValue: .number(0.5),
            minimum: 0,
            maximum: 1
        )
        XCTAssertNoThrow(try amount.validate(value: .number(0.75)))
        XCTAssertThrowsError(try amount.validate(value: .string("0.75")))
        XCTAssertThrowsError(try amount.validate(value: .number(2)))

        let mode = EffectParameterDescriptor(
            identifier: "mode",
            displayName: "Mode",
            kind: .enumeration,
            defaultValue: .number(0),
            choices: [
                .init(id: "0", displayName: "Zero"),
                .init(id: "1", displayName: "One"),
            ]
        )
        XCTAssertNoThrow(try mode.validate(value: .number(1)))
        XCTAssertThrowsError(try mode.validate(value: .number(2)))
        XCTAssertThrowsError(try mode.validate(value: .string("1")))
        XCTAssertThrowsError(
            try mode.validate(value: .number(Double(Int64.max)))
        )
    }

    func testDescriptorValidationRejectsEnumerationWithoutUniqueChoices() {
        let missing = EffectDescriptor(
            id: "com.daito.invalid.enum.missing",
            displayName: "Missing Choices",
            category: .utility,
            parameters: [
                EffectParameterDescriptor(
                    identifier: "mode",
                    displayName: "Mode",
                    kind: .enumeration,
                    defaultValue: .number(0)
                ),
            ]
        )
        XCTAssertThrowsError(try missing.validate()) { error in
            XCTAssertEqual(
                error as? EffectDescriptorValidationError,
                .invalidParameterChoices("mode")
            )
        }

        let duplicate = EffectDescriptor(
            id: "com.daito.invalid.enum.duplicate",
            displayName: "Duplicate Choices",
            category: .utility,
            parameters: [
                EffectParameterDescriptor(
                    identifier: "mode",
                    displayName: "Mode",
                    kind: .enumeration,
                    defaultValue: .number(0),
                    choices: [
                        .init(id: "0", displayName: "First"),
                        .init(id: "0", displayName: "Second"),
                    ]
                ),
            ]
        )
        XCTAssertThrowsError(try duplicate.validate()) { error in
            XCTAssertEqual(
                error as? EffectDescriptorValidationError,
                .invalidParameterChoices("mode")
            )
        }
    }

    func testHostRejectsIncompatibleEffectAPIMajor() {
        let effect = EffectDescriptor(
            id: "com.daito.future",
            displayName: "Future",
            apiVersion: .init(major: 2, minor: 0),
            category: .utility
        )
        let report = HostCapabilities().compatibility(with: effect)

        XCTAssertFalse(report.canRun)
        XCTAssertEqual(report.unsupportedAPIVersion, .init(major: 2, minor: 0))
    }
}
