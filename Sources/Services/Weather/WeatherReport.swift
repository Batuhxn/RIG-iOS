import Foundation

/// One forecast as the interface shows it, plus the ranking inputs.
///
/// `context` is the engine's own `WeatherContext`; this type only adds what a
/// person needs to judge the numbers: where, when, and how old they are.
struct WeatherReport: Codable, Hashable, Sendable {
    let city: WeatherCity
    /// Local wall-clock time of the "current" reading, as Open-Meteo reports it
    /// (for example "2026-10-19T01:30"). Kept as text because it is already in
    /// the city's own timezone and is only ever displayed.
    let observedLocalTime: String
    let airTemperatureC: Double
    let apparentTemperatureC: Double
    /// Highest hourly precipitation probability from the current hour through
    /// the next `rainLookaheadHours - 1` hours. People dress for the next few
    /// hours, not for the current fifteen minutes.
    let precipitationProbability: Int
    let windSpeedKPH: Double
    /// WMO weather interpretation code.
    let weatherCode: Int
    /// When this device received the forecast. Drives staleness, not display.
    let fetchedAt: Date

    static let rainLookaheadHours = 6

    var context: WeatherContext {
        WeatherContext(
            apparentTemperatureC: apparentTemperatureC,
            precipitationProbability: precipitationProbability,
            windSpeedKPH: windSpeedKPH
        )
    }

    var condition: WeatherCondition { WeatherCondition(code: weatherCode) }
}

/// A coarse reading of the WMO code, for an icon and a word. Never used for
/// ranking: the engine only sees temperature, rain probability and wind.
enum WeatherCondition: Equatable, Sendable {
    case clear, partlyCloudy, cloudy, fog, drizzle, rain, snow, thunderstorm, unknown

    init(code: Int) {
        switch code {
        case 0: self = .clear
        case 1, 2: self = .partlyCloudy
        case 3: self = .cloudy
        case 45, 48: self = .fog
        case 51...57: self = .drizzle
        case 61...67, 80...82: self = .rain
        case 71...77, 85, 86: self = .snow
        case 95...99: self = .thunderstorm
        default: self = .unknown
        }
    }

    var label: String {
        switch self {
        case .clear: return "Clear"
        case .partlyCloudy: return "Partly cloudy"
        case .cloudy: return "Overcast"
        case .fog: return "Fog"
        case .drizzle: return "Drizzle"
        case .rain: return "Rain"
        case .snow: return "Snow"
        case .thunderstorm: return "Thunderstorm"
        case .unknown: return "Conditions unavailable"
        }
    }

    var symbolName: String {
        switch self {
        case .clear: return "sun.max"
        case .partlyCloudy: return "cloud.sun"
        case .cloudy: return "cloud"
        case .fog: return "cloud.fog"
        case .drizzle: return "cloud.drizzle"
        case .rain: return "cloud.rain"
        case .snow: return "cloud.snow"
        case .thunderstorm: return "cloud.bolt.rain"
        case .unknown: return "questionmark.circle"
        }
    }
}
