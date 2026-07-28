// SPDX-FileCopyrightText: 2026 Daito Manabe
// SPDX-License-Identifier: BSD-3-Clause

import ContourEffectsCore
import ContourEffectsMetal
import ExampleSupport
import Foundation

private struct DescriptorReport: Codable {
    var identifier: String
    var displayName: String
    var category: String
    var requiredInputs: UInt64
    var parameterIdentifiers: [String]
    var canRunWithComposedColor: Bool
}

private struct DependencyReport: Codable {
    var identifier: String
    var name: String
    var distribution: String
    var license: String
    var isOptional: Bool
}

private struct StateReport: Codable {
    var schemaVersion: Int
    var encodedByteCount: Int
    var contrast: Double
    var unknownKeyPreserved: Bool
}

private struct CatalogStateReport: Codable {
    var selfCheck: Bool
    var apiVersion: String
    var descriptorCount: Int
    var descriptors: [DescriptorReport]
    var dependencies: [DependencyReport]
    var state: StateReport
}

@main
private enum CatalogStateExample {
    static func main() throws {
        let descriptors = ContourEffectsMetalCatalog.descriptors
        try exampleRequire(!descriptors.isEmpty, "The effect catalog is empty.")

        let capabilities = HostCapabilities(
            availableInputs: [.composedColor]
        )
        let descriptorReports = try descriptors.map { descriptor in
            try descriptor.validate()
            let compatibility = capabilities.compatibility(with: descriptor)
            return DescriptorReport(
                identifier: descriptor.id.rawValue,
                displayName: descriptor.displayName,
                category: descriptor.category.rawValue,
                requiredInputs: descriptor.requiredInputs.rawValue,
                parameterIdentifiers: descriptor.parameters.map(\.identifier),
                canRunWithComposedColor: compatibility.canRun
            )
        }
        let colorGradeReport = descriptorReports.first {
            $0.identifier == ColorGradeEffect.identifier.rawValue
        }
        try exampleRequire(
            colorGradeReport?.canRunWithComposedColor == true,
            "ColorGradeEffect rejected its documented minimum capability."
        )

        guard let effect = ContourEffectsMetalCatalog.makeEffect(
            identifier: ColorGradeEffect.identifier
        ) else {
            throw ExampleError("The catalog could not construct ColorGradeEffect.")
        }
        try effect.setParameterValue(.number(1.25), identifier: "contrast")

        var futureState = effect.snapshotState()
        futureState.schemaVersion = 7
        futureState.values["future.example"] = .object([
            "enabled": .bool(true),
            "revision": .number(42),
        ])

        let stateEncoder = JSONEncoder()
        stateEncoder.outputFormatting = [.sortedKeys]
        let encodedState = try stateEncoder.encode(futureState)
        let decodedState = try JSONDecoder().decode(
            EffectStateSnapshot.self,
            from: encodedState
        )

        let restoredEffect = ColorGradeEffect()
        try restoredEffect.restoreState(decodedState)
        let roundTrippedState = restoredEffect.snapshotState()
        let unknownKeyPreserved =
            roundTrippedState.values["future.example"]
            == futureState.values["future.example"]
        let contrast =
            roundTrippedState.values["contrast"]?.numberValue ?? .nan

        try exampleRequire(
            roundTrippedState.schemaVersion == 7,
            "The future state schema version was not retained."
        )
        try exampleRequire(
            unknownKeyPreserved,
            "The unknown state value was not retained."
        )
        try exampleRequire(
            abs(contrast - 1.25) < 0.000_001,
            "The generic contrast parameter did not round-trip."
        )

        let dependencies = ContourEffectsDependencies.all
            .sorted { $0.id.rawValue < $1.id.rawValue }
            .map {
                DependencyReport(
                    identifier: $0.id.rawValue,
                    name: $0.displayName,
                    distribution: $0.distribution.rawValue,
                    license: $0.license,
                    isOptional: $0.isOptional
                )
            }

        try emitJSON(
            CatalogStateReport(
                selfCheck: true,
                apiVersion: "\(ContourEffectsSDK.apiVersion.major)."
                    + "\(ContourEffectsSDK.apiVersion.minor)",
                descriptorCount: descriptorReports.count,
                descriptors: descriptorReports,
                dependencies: dependencies,
                state: StateReport(
                    schemaVersion: roundTrippedState.schemaVersion,
                    encodedByteCount: encodedState.count,
                    contrast: contrast,
                    unknownKeyPreserved: unknownKeyPreserved
                )
            )
        )
    }
}
