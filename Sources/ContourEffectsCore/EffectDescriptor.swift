// SPDX-FileCopyrightText: 2026 Daito Manabe
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

public struct EffectIdentifier:
    RawRepresentable,
    Codable,
    Hashable,
    Sendable,
    ExpressibleByStringLiteral
{
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        rawValue = value
    }
}

public enum EffectCategory: String, Codable, CaseIterable, Sendable {
    case color
    case distortion
    case glitch
    case particles
    case fluid
    case reactionDiffusion
    case analysis
    case compositing
    case threeDimensional
    case utility
}

public enum EffectExecutionModel: String, Codable, Sendable {
    case stateless
    case temporal
    case asynchronous
}

public enum EffectSynchronizationPolicy: String, Codable, Sendable {
    /// Favor newest source and analysis values. This is the default for VJ use.
    case latestLowLatency
    /// Use the source frame whose sequence matches the analysis result.
    case analysisMatchedFrame
}

/// Analysis and host data an effect can request.
public struct EffectInputRequirements: OptionSet, Codable, Equatable, Sendable {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public static let composedColor = Self(rawValue: 1 << 0)
    public static let rawCameraColor = Self(rawValue: 1 << 1)
    public static let edge = Self(rawValue: 1 << 2)
    public static let opticalFlow = Self(rawValue: 1 << 3)
    public static let featurePoints = Self(rawValue: 1 << 4)
    public static let personMask = Self(rawValue: 1 << 5)
    public static let silhouetteContour = Self(rawValue: 1 << 6)
    public static let handLandmarks = Self(rawValue: 1 << 7)
    public static let bodyLandmarks = Self(rawValue: 1 << 8)
    public static let sceneMask = Self(rawValue: 1 << 9)
    public static let objectDetections = Self(rawValue: 1 << 10)
    public static let depth = Self(rawValue: 1 << 11)
    public static let audio = Self(rawValue: 1 << 12)
    public static let performanceMacros = Self(rawValue: 1 << 13)
}

public enum EffectParameterValueKind: String, Codable, Equatable, Sendable {
    case float
    case integer
    case boolean
    case enumeration
    case trigger
    case color
    case vector2
    case fileReference
}

public struct EffectParameterChoice: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var displayName: String

    public init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}

/// A host-readable parameter description suitable for UI and automation.
public struct EffectParameterDescriptor: Codable, Equatable, Sendable {
    public var identifier: String
    public var displayName: String
    public var kind: EffectParameterValueKind
    public var defaultValue: EffectValue
    public var minimum: Double?
    public var maximum: Double?
    public var choices: [EffectParameterChoice]
    public var unit: String?
    public var smoothingTime: Double
    public var isAutomatable: Bool
    public var midiAssignable: Bool
    public var oscAddress: String?

    public init(
        identifier: String,
        displayName: String,
        kind: EffectParameterValueKind,
        defaultValue: EffectValue,
        minimum: Double? = nil,
        maximum: Double? = nil,
        choices: [EffectParameterChoice] = [],
        unit: String? = nil,
        smoothingTime: Double = 0,
        isAutomatable: Bool = true,
        midiAssignable: Bool = true,
        oscAddress: String? = nil
    ) {
        self.identifier = identifier
        self.displayName = displayName
        self.kind = kind
        self.defaultValue = defaultValue
        self.minimum = minimum
        self.maximum = maximum
        self.choices = choices
        self.unit = unit
        self.smoothingTime = smoothingTime
        self.isAutomatable = isAutomatable
        self.midiAssignable = midiAssignable
        self.oscAddress = oscAddress
    }

    public func validate(value: EffectValue) throws {
        switch kind {
        case .float:
            let number = try finiteNumber(value)
            try validateRange(number)
        case .integer:
            let number = try finiteNumber(value)
            guard number.rounded(.towardZero) == number else {
                throw EffectParameterValidationError
                    .expectedInteger(identifier)
            }
            try validateRange(number)
        case .boolean, .trigger:
            guard value.boolValue != nil else {
                throw EffectParameterValidationError
                    .typeMismatch(identifier, expected: "boolean")
            }
        case .enumeration:
            guard !choices.isEmpty else {
                throw EffectParameterValidationError.missingChoices(identifier)
            }
            guard Set(choices.map(\.id)).count == choices.count else {
                throw EffectParameterValidationError.duplicateChoice(identifier)
            }
            let choiceID: String
            switch defaultValue {
            case .number:
                let number = try finiteNumber(value)
                guard number.rounded(.towardZero) == number else {
                    throw EffectParameterValidationError
                        .expectedInteger(identifier)
                }
                choiceID = String(
                    format: "%.0f",
                    locale: Locale(identifier: "en_US_POSIX"),
                    number
                )
            case .string:
                guard let string = value.stringValue else {
                    throw EffectParameterValidationError
                        .typeMismatch(identifier, expected: "string")
                }
                choiceID = string
            default:
                throw EffectParameterValidationError
                    .invalidEnumerationDefault(identifier)
            }
            if !choices.contains(where: { $0.id == choiceID }) {
                throw EffectParameterValidationError
                    .unknownChoice(identifier, choiceID: choiceID)
            }
        case .color:
            try validateNumericArray(value, allowedCounts: [3, 4])
        case .vector2:
            try validateNumericArray(value, allowedCounts: [2])
        case .fileReference:
            guard value == .null || value.stringValue != nil else {
                throw EffectParameterValidationError
                    .typeMismatch(identifier, expected: "string or null")
            }
        }
    }

    private func finiteNumber(_ value: EffectValue) throws -> Double {
        guard let number = value.numberValue else {
            throw EffectParameterValidationError
                .typeMismatch(identifier, expected: "number")
        }
        guard number.isFinite else {
            throw EffectParameterValidationError.nonFinite(identifier)
        }
        return number
    }

    private func validateRange(_ number: Double) throws {
        if let minimum, number < minimum {
            throw EffectParameterValidationError.outsideRange(identifier)
        }
        if let maximum, number > maximum {
            throw EffectParameterValidationError.outsideRange(identifier)
        }
    }

    private func validateNumericArray(
        _ value: EffectValue,
        allowedCounts: Set<Int>
    ) throws {
        guard case let .array(elements) = value,
              allowedCounts.contains(elements.count)
        else {
            let counts = allowedCounts.sorted().map(String.init).joined(separator: " or ")
            throw EffectParameterValidationError.typeMismatch(
                identifier,
                expected: "an array of \(counts) numbers"
            )
        }
        for element in elements {
            _ = try finiteNumber(element)
        }
    }
}

public enum EffectParameterValidationError: LocalizedError, Equatable {
    case typeMismatch(String, expected: String)
    case nonFinite(String)
    case expectedInteger(String)
    case outsideRange(String)
    case invalidEnumerationDefault(String)
    case missingChoices(String)
    case duplicateChoice(String)
    case unknownChoice(String, choiceID: String)

    public var errorDescription: String? {
        switch self {
        case let .typeMismatch(identifier, expected):
            return "Effect parameter \(identifier) requires \(expected)."
        case let .nonFinite(identifier):
            return "Effect parameter \(identifier) must be finite."
        case let .expectedInteger(identifier):
            return "Effect parameter \(identifier) requires an integer."
        case let .outsideRange(identifier):
            return "Effect parameter \(identifier) is outside its declared range."
        case let .invalidEnumerationDefault(identifier):
            return "Enumeration parameter \(identifier) needs a numeric or string default."
        case let .missingChoices(identifier):
            return "Enumeration parameter \(identifier) must declare its choices."
        case let .duplicateChoice(identifier):
            return "Enumeration parameter \(identifier) has duplicate choice identifiers."
        case let .unknownChoice(identifier, choiceID):
            return "Enumeration parameter \(identifier) has no choice \(choiceID)."
        }
    }
}

public enum EffectDescriptorValidationError: LocalizedError, Equatable {
    case emptyEffectIdentifier
    case duplicateParameterIdentifier(String)
    case emptyParameterIdentifier
    case invalidParameterRange(String)
    case defaultOutsideRange(String)
    case invalidDefaultValue(String)
    case invalidParameterChoices(String)
    case overlappingInputs
    case overlappingDependencies

    public var errorDescription: String? {
        switch self {
        case .emptyEffectIdentifier:
            return "Effect identifiers must not be empty."
        case let .duplicateParameterIdentifier(identifier):
            return "Effect parameter identifier is duplicated: \(identifier)"
        case .emptyParameterIdentifier:
            return "Effect parameter identifiers must not be empty."
        case let .invalidParameterRange(identifier):
            return "Effect parameter \(identifier) has an invalid numeric range."
        case let .defaultOutsideRange(identifier):
            return "Effect parameter \(identifier) has a default outside its range."
        case let .invalidDefaultValue(identifier):
            return "Effect parameter \(identifier) has an invalid default value."
        case let .invalidParameterChoices(identifier):
            return "Enumeration parameter \(identifier) has missing or duplicate choices."
        case .overlappingInputs:
            return "Required and optional effect inputs must not overlap."
        case .overlappingDependencies:
            return "Required and optional effect dependencies must not overlap."
        }
    }
}

/// Stable metadata for discovery without instantiating an effect.
public struct EffectDescriptor: Codable, Equatable, Sendable, Identifiable {
    public var id: EffectIdentifier
    public var displayName: String
    public var apiVersion: EffectAPIVersion
    public var stateSchemaVersion: Int
    public var category: EffectCategory
    public var executionModel: EffectExecutionModel
    public var requiredInputs: EffectInputRequirements
    public var optionalInputs: EffectInputRequirements
    public var synchronizationPolicy: EffectSynchronizationPolicy
    public var parameters: [EffectParameterDescriptor]
    public var requiredDependencies: [ContourEffectsDependencyID]
    public var optionalDependencies: [ContourEffectsDependencyID]

    public init(
        id: EffectIdentifier,
        displayName: String,
        apiVersion: EffectAPIVersion = ContourEffectsSDK.apiVersion,
        stateSchemaVersion: Int = 1,
        category: EffectCategory,
        executionModel: EffectExecutionModel = .stateless,
        requiredInputs: EffectInputRequirements = [.composedColor],
        optionalInputs: EffectInputRequirements = [],
        synchronizationPolicy: EffectSynchronizationPolicy = .latestLowLatency,
        parameters: [EffectParameterDescriptor] = [],
        requiredDependencies: [ContourEffectsDependencyID] = [],
        optionalDependencies: [ContourEffectsDependencyID] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.apiVersion = apiVersion
        self.stateSchemaVersion = stateSchemaVersion
        self.category = category
        self.executionModel = executionModel
        self.requiredInputs = requiredInputs
        self.optionalInputs = optionalInputs
        self.synchronizationPolicy = synchronizationPolicy
        self.parameters = parameters
        self.requiredDependencies = requiredDependencies
        self.optionalDependencies = optionalDependencies
    }

    public func validate() throws {
        guard !id.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw EffectDescriptorValidationError.emptyEffectIdentifier
        }
        guard requiredInputs.intersection(optionalInputs).isEmpty else {
            throw EffectDescriptorValidationError.overlappingInputs
        }
        guard Set(requiredDependencies).isDisjoint(with: Set(optionalDependencies)) else {
            throw EffectDescriptorValidationError.overlappingDependencies
        }

        var identifiers = Set<String>()
        for parameter in parameters {
            let identifier = parameter.identifier.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard !identifier.isEmpty else {
                throw EffectDescriptorValidationError.emptyParameterIdentifier
            }
            guard identifiers.insert(identifier).inserted else {
                throw EffectDescriptorValidationError
                    .duplicateParameterIdentifier(identifier)
            }
            if parameter.kind == .enumeration,
               (
                   parameter.choices.isEmpty
                       || Set(parameter.choices.map(\.id)).count
                       != parameter.choices.count
               )
            {
                throw EffectDescriptorValidationError
                    .invalidParameterChoices(identifier)
            }
            if let minimum = parameter.minimum,
               let maximum = parameter.maximum
            {
                guard minimum.isFinite, maximum.isFinite, minimum <= maximum else {
                    throw EffectDescriptorValidationError
                        .invalidParameterRange(identifier)
                }
                if let value = parameter.defaultValue.numberValue,
                   (!value.isFinite || value < minimum || value > maximum)
                {
                    throw EffectDescriptorValidationError
                        .defaultOutsideRange(identifier)
                }
            }
            do {
                try parameter.validate(value: parameter.defaultValue)
            } catch {
                throw EffectDescriptorValidationError
                    .invalidDefaultValue(identifier)
            }
        }
    }
}

public struct HostCapabilities: Codable, Equatable, Sendable {
    public var availableInputs: EffectInputRequirements
    public var availableDependencies: Set<ContourEffectsDependencyID>

    public init(
        availableInputs: EffectInputRequirements = [.composedColor],
        availableDependencies: Set<ContourEffectsDependencyID> = []
    ) {
        self.availableInputs = availableInputs
        self.availableDependencies = availableDependencies
    }

    public func compatibility(with effect: EffectDescriptor) -> EffectCompatibilityReport {
        EffectCompatibilityReport(
            unsupportedAPIVersion: ContourEffectsSDK.apiVersion
                .supports(effect.apiVersion) ? nil : effect.apiVersion,
            missingInputs: effect.requiredInputs.subtracting(availableInputs),
            missingRequiredDependencies: Set(effect.requiredDependencies)
                .subtracting(availableDependencies),
            missingOptionalDependencies: Set(effect.optionalDependencies)
                .subtracting(availableDependencies)
        )
    }
}

public struct EffectCompatibilityReport: Codable, Equatable, Sendable {
    public var unsupportedAPIVersion: EffectAPIVersion?
    public var missingInputs: EffectInputRequirements
    public var missingRequiredDependencies: Set<ContourEffectsDependencyID>
    public var missingOptionalDependencies: Set<ContourEffectsDependencyID>

    public init(
        unsupportedAPIVersion: EffectAPIVersion? = nil,
        missingInputs: EffectInputRequirements = [],
        missingRequiredDependencies: Set<ContourEffectsDependencyID> = [],
        missingOptionalDependencies: Set<ContourEffectsDependencyID> = []
    ) {
        self.unsupportedAPIVersion = unsupportedAPIVersion
        self.missingInputs = missingInputs
        self.missingRequiredDependencies = missingRequiredDependencies
        self.missingOptionalDependencies = missingOptionalDependencies
    }

    public var canRun: Bool {
        unsupportedAPIVersion == nil
            && missingInputs.isEmpty
            && missingRequiredDependencies.isEmpty
    }
}
