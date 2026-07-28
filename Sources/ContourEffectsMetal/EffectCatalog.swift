// SPDX-FileCopyrightText: 2026 Daito Manabe
// SPDX-License-Identifier: BSD-3-Clause

import ContourEffectsCore
import Foundation

/// Discovery and construction surface for effects included in this product.
public enum ContourEffectsMetalCatalog {
    public static let descriptors: [EffectDescriptor] = [
        ColorGradeEffect.effectDescriptor,
    ]

    public static func makeEffect(
        identifier: EffectIdentifier
    ) -> (any MetalEffectInstance)? {
        switch identifier {
        case ColorGradeEffect.identifier:
            return ColorGradeEffect()
        default:
            return nil
        }
    }
}
