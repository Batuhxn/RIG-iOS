import Foundation

/// How finished a look is, structurally.
///
/// A valid base is the floor; shoes matter most after that. This never decides
/// validity — `OutfitValidator` does — it only separates a bare base from a
/// look someone could actually walk out in.
enum OutfitCompleteness {
    static let baseScore = 0.60
    static let shoesBonus = 0.20
    static let outerwearBonus = 0.10
    static let carriedOrAccessoryBonus = 0.10

    static func score(for items: [GarmentSnapshot]) -> Double {
        let categories = Set(items.map(\.category))
        let hasBase = categories.contains(.dress) || (categories.contains(.top) && categories.contains(.bottom))
        guard hasBase else { return 0 }

        var score = baseScore
        if categories.contains(.shoes) { score += shoesBonus }
        if categories.contains(.outerwear) { score += outerwearBonus }
        if categories.contains(.bag) || categories.contains(.accessory) { score += carriedOrAccessoryBonus }
        return min(score, 1)
    }
}
