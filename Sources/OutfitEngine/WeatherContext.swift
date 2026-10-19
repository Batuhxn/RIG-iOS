import Foundation

/// Normalized forecast inputs for ranking. The weather provider and the UI
/// intentionally live outside the outfit engine.
struct WeatherContext: Hashable, Sendable {
    /// Feels-like temperature in degrees Celsius, not the raw air temperature.
    let apparentTemperatureC: Double
    /// Probability of precipitation from 0 to 100.
    let precipitationProbability: Int
    /// Wind speed in km/h.
    let windSpeedKPH: Double

    init(
        apparentTemperatureC: Double,
        precipitationProbability: Int = 0,
        windSpeedKPH: Double = 0
    ) {
        self.apparentTemperatureC = apparentTemperatureC
        self.precipitationProbability = min(max(precipitationProbability, 0), 100)
        self.windSpeedKPH = windSpeedKPH
    }

    var isUsable: Bool {
        apparentTemperatureC.isFinite && windSpeedKPH.isFinite && windSpeedKPH >= 0
    }

    var hasLikelyRain: Bool { precipitationProbability >= 60 }
}
