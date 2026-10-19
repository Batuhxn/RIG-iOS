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

    /// `countingOuterwear: false` is for weather-aware ranking, where whether a
    /// layer belongs in the look is WeatherComfort's decision alone; otherwise
    /// this bonus makes every mild-weather look carry a jacket (issue #7).
    static func score(for items: [GarmentSnapshot], countingOuterwear: Bool = true) -> Double {
        let categories = Set(items.map(\.category))
        let hasBase = categories.contains(.dress) || (categories.contains(.top) && categories.contains(.bottom))
        guard hasBase else { return 0 }

        var score = baseScore
        if categories.contains(.shoes) { score += shoesBonus }
        if countingOuterwear, categories.contains(.outerwear) { score += outerwearBonus }
        if categories.contains(.bag) || categories.contains(.accessory) { score += carriedOrAccessoryBonus }
        return min(score, 1)
    }
}
