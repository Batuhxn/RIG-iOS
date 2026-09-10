import Foundation

/// Every tunable the engine has, in one place.
///
/// The weights sum to 1 so a total score always lands in 0...1. Nothing in the
/// interface shows that number; it exists to rank, not to inform.
struct OutfitEngineConfiguration: Hashable, Sendable {
    var colorWeight: Double = 0.45
    var seasonWeight: Double = 0.30
    var completenessWeight: Double = 0.20
    /// Explicit favourites only. Not a learned style model.
    var preferenceWeight: Double = 0.05

    /// Upper bound on evaluated combinations for one suggestion pass.
    /// 300 keeps a large wardrobe from turning a tap into a stall, and is far
    /// more than the handful of suggestions the interface actually shows.
    var maximumEvaluatedCandidates: Int = 300

    /// Upper bound on structural bases (dresses plus top/bottom pairings).
    var maximumBaseCombinations: Int = 60

    var shoeFanout: Int = 2
    var outerwearFanout: Int = 1
    var accessoryFanout: Int = 1

    /// Hard ceiling on how much any future compatibility provider may move a
    /// score. The rule engine keeps at least 85% of the weight, permanently.
    var compatibilitySignalWeight: Double = 0.15

    /// How many rule-ranked candidates a compatibility provider is allowed to
    /// see. A provider never scores the whole candidate set.
    var compatibilityRescoreDepth: Int = 12

    static let maximumAllowedCompatibilitySignalWeight = 0.15

    /// The weight actually applied, after the ceiling.
    var effectiveCompatibilitySignalWeight: Double {
        min(max(compatibilitySignalWeight, 0), Self.maximumAllowedCompatibilitySignalWeight)
    }

    static let `default` = OutfitEngineConfiguration()
}
