import Foundation

/// Colour rules for v0.1.
///
/// This is a small, deliberately legible rule set — not fashion theory and not a
/// probability. Every constant below is a tunable that later versions are meant
/// to adjust from accumulated feedback. The interface never shows the number.
///
/// The rules, in order of precedence for a pair of colour families:
///
/// 1. Anything paired with `multicolor` scores flat mid-range. We cannot reason
///    about a garment with no single hue, so we refuse to be confident either way.
/// 2. Two neutrals combine broadly.
/// 3. The same family with itself is monochromatic and combines well.
/// 4. A neutral anchors an accent.
/// 5. Two different accents are judged by distance on a coarse colour wheel:
///    close together (analogous) is good, roughly opposite (complementary) is
///    acceptable, and the awkward middle is penalised.
/// 6. Two vivid accents that are not analogous take a further penalty, which is
///    what keeps several unrelated loud colours from scoring well.
///
/// An outfit score is the mean of its pairwise scores, with one extra penalty
/// when the palette carries more than a few distinct accent families.
enum ColorHarmony {
    static let bothNeutralScore = 0.92
    static let sameFamilyScore = 0.90
    static let neutralWithAccentScore = 0.85
    static let analogousScore = 0.75
    static let complementaryScore = 0.65
    static let relatedScore = 0.55
    static let unclassifiedScore = 0.50
    static let clashScore = 0.40

    static let analogousThresholdDegrees = 40.0
    static let relatedThresholdDegrees = 90.0
    static let complementaryThresholdDegrees = 150.0

    /// Applied to two vivid accents that are not analogous.
    static let vividContrastMultiplier = 0.85

    /// More distinct accent families than this and the whole palette is damped.
    static let busyPaletteAccentLimit = 3
    static let busyPaletteMultiplier = 0.85

    /// Returned when there is nothing to compare. Neither reward nor punishment.
    static let insufficientDataScore = 0.70

    static func circularDistanceDegrees(_ lhs: Double, _ rhs: Double) -> Double {
        let raw = abs(lhs - rhs).truncatingRemainder(dividingBy: 360)
        return min(raw, 360 - raw)
    }

    static func pairScore(_ lhs: ColorFamily, _ rhs: ColorFamily) -> Double {
        if lhs == .multicolor || rhs == .multicolor {
            return unclassifiedScore
        }
        if lhs.isNeutral && rhs.isNeutral {
            return bothNeutralScore
        }
        if lhs == rhs {
            return sameFamilyScore
        }
        if lhs.isNeutral != rhs.isNeutral {
            return neutralWithAccentScore
        }
        guard let lhsHue = lhs.hueAngle, let rhsHue = rhs.hueAngle else {
            return unclassifiedScore
        }

        let distance = circularDistanceDegrees(lhsHue, rhsHue)
        let base: Double
        if distance <= analogousThresholdDegrees {
            base = analogousScore
        } else if distance <= relatedThresholdDegrees {
            base = relatedScore
        } else if distance >= complementaryThresholdDegrees {
            base = complementaryScore
        } else {
            base = clashScore
        }

        if distance > analogousThresholdDegrees && lhs.isVivid && rhs.isVivid {
            return base * vividContrastMultiplier
        }
        return base
    }

    static func score(for colors: [ColorFamily]) -> Double {
        guard colors.count >= 2 else { return insufficientDataScore }

        var total = 0.0
        var pairCount = 0
        for lhsIndex in colors.indices {
            for rhsIndex in colors.index(after: lhsIndex)..<colors.endIndex {
                total += pairScore(colors[lhsIndex], colors[rhsIndex])
                pairCount += 1
            }
        }
        guard pairCount > 0 else { return insufficientDataScore }

        var mean = total / Double(pairCount)

        let distinctAccents = Set(colors.filter { $0.tone == .accent })
        if distinctAccents.count > busyPaletteAccentLimit {
            mean *= busyPaletteMultiplier
        }

        return min(max(mean, 0), 1)
    }
}
