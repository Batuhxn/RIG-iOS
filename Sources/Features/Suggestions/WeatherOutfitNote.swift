import Foundation

/// Short, grounded weather notes for one suggested look.
///
/// RIG records category, colour and season tags — not fabric, insulation or
/// waterproofing. So notes say what the look contains and what the forecast
/// says, and never that a garment is warm enough, breathable or waterproof.
/// Thresholds mirror the ones `WeatherComfort` ranks with, so a note never
/// contradicts the ordering it explains.
enum WeatherOutfitNote {
    static let maximumNotes = 2

    /// `rainHours` is how many hours the rain probability covers; the note
    /// states it, because the number is the highest single hour, not the chance
    /// of any rain across the whole window.
    static func notes(
        for items: [GarmentSnapshot],
        weather: WeatherContext,
        rainHours: Int = WeatherReport.rainLookaheadHours
    ) -> [String] {
        guard weather.isUsable, !items.isEmpty else { return [] }

        let feelsLike = formattedTemperature(weather.apparentTemperatureC)
        let hasOuterwear = items.contains { $0.category == .outerwear }
        let isWindyAndCool = weather.apparentTemperatureC <= 18 && weather.windSpeedKPH >= 25
        var notes: [String] = []

        // Facts side by side, no causal "for": an outer layer is not known to
        // be adequate for any particular temperature.
        if weather.apparentTemperatureC <= 12 || isWindyAndCool {
            notes.append(hasOuterwear
                ? "Includes an outer layer; feels like \(feelsLike)."
                : "No outer layer; feels like \(feelsLike).")
        } else if weather.apparentTemperatureC >= 25 {
            notes.append(hasOuterwear
                ? "Has an outer layer; feels like \(feelsLike)."
                : "No extra layer; feels like \(feelsLike).")
        }

        if weather.hasLikelyRain {
            notes.append(
                "Highest hourly rain chance in the next \(rainHours) h: \(weather.precipitationProbability)%. "
                    + "Check your shoes and outer layer suit wet weather."
            )
        } else if isWindyAndCool {
            notes.append("Wind \(Int(weather.windSpeedKPH.rounded())) km/h.")
        }

        return Array(notes.prefix(maximumNotes))
    }

    /// "9°C", never "-0°C".
    static func formattedTemperature(_ celsius: Double) -> String {
        let rounded = Int(celsius.rounded())
        return "\(rounded == 0 ? 0 : rounded)°C"
    }
}
