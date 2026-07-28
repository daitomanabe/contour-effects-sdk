// SPDX-FileCopyrightText: 2026 Daito Manabe
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

public struct EffectAPIVersion: Codable, Equatable, Hashable, Sendable {
    public var major: UInt16
    public var minor: UInt16

    public init(major: UInt16, minor: UInt16) {
        self.major = major
        self.minor = minor
    }

    public static let v1 = Self(major: 1, minor: 0)

    /// A host can run effects from the same major API whose minor version is
    /// no newer than the host implementation.
    public func supports(_ effectVersion: Self) -> Bool {
        major == effectVersion.major && minor >= effectVersion.minor
    }
}

public enum ContourEffectsSDK {
    public static let apiVersion = EffectAPIVersion.v1
    public static let minimumMacOSVersion = "14.0"
}
