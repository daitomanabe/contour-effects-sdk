// SPDX-FileCopyrightText: 2026 Daito Manabe
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// A lossless JSON value used by SDK effect state.
///
/// Values deliberately remain dynamically typed so an older host can retain
/// parameters written by a newer effect without understanding them.
public indirect enum EffectValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([EffectValue])
    case object([String: EffectValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([EffectValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: EffectValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported effect state value"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case let .bool(value):
            try container.encode(value)
        case let .number(value):
            try container.encode(value)
        case let .string(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case let .object(value):
            try container.encode(value)
        }
    }

    public var boolValue: Bool? {
        guard case let .bool(value) = self else { return nil }
        return value
    }

    public var numberValue: Double? {
        guard case let .number(value) = self else { return nil }
        return value
    }

    public var stringValue: String? {
        guard case let .string(value) = self else { return nil }
        return value
    }
}

/// Versioned, forward-compatible state owned by one effect instance.
public struct EffectStateSnapshot: Codable, Equatable, Sendable {
    public var effectIdentifier: EffectIdentifier
    public var schemaVersion: Int
    public var values: [String: EffectValue]

    public init(
        effectIdentifier: EffectIdentifier,
        schemaVersion: Int = 1,
        values: [String: EffectValue] = [:]
    ) {
        self.effectIdentifier = effectIdentifier
        self.schemaVersion = schemaVersion
        self.values = values
    }
}
