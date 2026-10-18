import Foundation

/// Conservative, deterministic weather guidance from the information RIG
/// actually stores. This is a ranking hint, not a warmth or waterproof rating.
///
/// All-year garment metadata is treated as unknown/neutral rather than
/// automatically ideal in every climate. Neither fabric nor waterproofing
/// is currently recorded, so rain only triggers a small, cautious adjustment.
enum WeatherComfort {
    static func score(for items: [GarmentSnapshot], weather: WeatherContext) -> Double {
        guard weather.isUsable else { return 0.5 }
        let temperature = weather.apparentTemperatureC
        let baseAndLayers = items.filter {
            $0.category == .top || $0.category == .bottom
                || $0.category == .dress || $0.category == .outerwear
        }
        guard !baseAndLayers.isEmpty else { return 0.5 }

        let suitableSeasons: SeasonSet
        switch temperature {
        case ..<8:
            suitableSeasons = [.winter]
        case ..<17:
            suitableSeasons = [.spring, .autumn, .winter]
        case ..<25:
            suitableSeasons = [.spring, .summer, .autumn]
        default:
            suitableSeasons = [.summer]
        }

        let seasonFit = baseAndLayers.reduce(0.0) { result, item in
            if item.seasons.isAllSeason { return result + 0.6 }
            return result + (item.seasons.intersection(suitableSeasons).isEmpty ? 0.15 : 1.0)
        } / Double(baseAndLayers.count)

        let hasOuterwear = items.contains { $0.category == .outerwear }
        let layerFit: Double
        if temperature <= 12 || (temperature <= 18 && weather.windSpeedKPH >= 25) {
            layerFit = hasOuterwear ? 1.0 : 0.0
        } else if temperature >= 25 {
            layerFit = hasOuterwear ? 0.0 : 1.0
        } else {
            // In mild conditions either choice can be sensible.
            layerFit = 0.8
        }

        // Outerwear is not necessarily rainwear. This small weight does NOT
        // claim that an item protects against precipitation.
        let rainFit: Double = weather.hasLikelyRain
            ? (hasOuterwear ? 0.65 : 0.45)
            : 0.5

        return min(max(0.62 * seasonFit + 0.30 * layerFit + 0.08 * rainFit, 0), 1)
    }
}
