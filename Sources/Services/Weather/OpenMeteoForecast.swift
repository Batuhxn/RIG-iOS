import Foundation

/// The subset of an Open-Meteo `/v1/forecast` response RIG reads.
///
/// Requested with `timezone=auto`, so every timestamp is local wall-clock time
/// in the city's own zone ("yyyy-MM-ddTHH:mm") and the hourly series lines up
/// with `current.time` by its hour prefix — no timezone arithmetic required.
struct OpenMeteoForecast: Decodable, Sendable {
    struct Current: Decodable, Sendable {
        let time: String
        let temperature2M: Double
        let apparentTemperature: Double
        let weatherCode: Int
        let windSpeed10M: Double
    }

    struct Hourly: Decodable, Sendable {
        let time: [String]
        /// Individual hours may be null in the response.
        let precipitationProbability: [Int?]
    }

    let current: Current
    let hourly: Hourly

    /// Query items for exactly the fields decoded above. Units are the API
    /// defaults (°C, km/h) and are restated so a default change cannot slip in.
    static func queryItems(for city: WeatherCity) -> [URLQueryItem] {
        [
            URLQueryItem(name: "latitude", value: String(format: "%.2f", city.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.2f", city.longitude)),
            URLQueryItem(
                name: "current",
                value: "temperature_2m,apparent_temperature,weather_code,wind_speed_10m"
            ),
            URLQueryItem(name: "hourly", value: "precipitation_probability"),
            URLQueryItem(name: "temperature_unit", value: "celsius"),
            URLQueryItem(name: "wind_speed_unit", value: "kmh"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "2")
        ]
    }

    /// The API's snake_case keys map onto the properties above:
    /// `temperature_2m` -> `temperature2M` (Foundation capitalises "2m" as "2M").
    static func decode(_ data: Data) throws -> OpenMeteoForecast {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(OpenMeteoForecast.self, from: data)
    }

    /// Highest probability in the hours from the current one onwards, or nil
    /// when the current hour is missing from the series or every value is null.
    func precipitationProbability(lookaheadHours: Int) -> Int? {
        guard lookaheadHours > 0, current.time.count >= 13 else { return nil }
        let currentHour = String(current.time.prefix(13))
        guard let start = hourly.time.firstIndex(where: { $0.hasPrefix(currentHour) }) else { return nil }
        let end = min(start + lookaheadHours, hourly.time.count, hourly.precipitationProbability.count)
        guard start < end else { return nil }
        return hourly.precipitationProbability[start..<end].compactMap { $0 }.max()
    }

    /// A report, or nil when the readings are not something RIG should rank on.
    /// Missing rain data is not invented as "dry": the forecast is rejected and
    /// the interface falls back to ordinary suggestions.
    func report(for city: WeatherCity, fetchedAt: Date) -> WeatherReport? {
        guard current.apparentTemperature.isFinite,
              current.temperature2M.isFinite,
              current.windSpeed10M.isFinite,
              current.windSpeed10M >= 0,
              let rain = precipitationProbability(lookaheadHours: WeatherReport.rainLookaheadHours)
        else { return nil }

        return WeatherReport(
            city: city,
            observedLocalTime: current.time,
            airTemperatureC: current.temperature2M,
            apparentTemperatureC: current.apparentTemperature,
            precipitationProbability: min(max(rain, 0), 100),
            windSpeedKPH: current.windSpeed10M,
            weatherCode: current.weatherCode,
            fetchedAt: fetchedAt
        )
    }
}
