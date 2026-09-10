import Foundation

/// Seasonal agreement between garments.
///
/// This is not weather. It asks only whether the pieces belong to overlapping
/// parts of the year. A garment with no seasons recorded is treated as all year.
enum SeasonCoherence {
    /// Every garment shares at least one season.
    static let sharedSeasonScore = 1.0

    /// Floor for outfits with no season shared by all garments.
    static let partialFloor = 0.25

    /// How much of the remaining range partial pairwise overlap can recover.
    static let partialRange = 0.50

    /// A single garment cannot conflict with itself.
    static let insufficientDataScore = 1.0

    static func score(for seasonSets: [SeasonSet]) -> Double {
        let normalized = seasonSets.map(\.normalized)
        guard normalized.count >= 2 else { return insufficientDataScore }

        let common = normalized.dropFirst().reduce(normalized[0]) { $0.intersection($1) }
        if !common.isEmpty {
            return sharedSeasonScore
        }

        var overlappingPairs = 0
        var pairCount = 0
        for lhsIndex in normalized.indices {
            for rhsIndex in normalized.index(after: lhsIndex)..<normalized.endIndex {
                pairCount += 1
                if !normalized[lhsIndex].intersection(normalized[rhsIndex]).isEmpty {
                    overlappingPairs += 1
                }
            }
        }
        guard pairCount > 0 else { return insufficientDataScore }

        let fraction = Double(overlappingPairs) / Double(pairCount)
        return partialFloor + partialRange * fraction
    }
}
