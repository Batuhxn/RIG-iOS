import Foundation

/// The subset of an Open-Meteo `/v1/forecast` response RIG reads.
///
/// Requested with `timeformat=unixtime`, so every timestamp is an absolute
/// instant. The rain window is aligned by instant and each step is checked to be
/// exactly one hour, so a repeated or skipped local hour (a DST change, or a gap
/// in the feed) can never pass for "the next six hours".
struct OpenMeteoForecast: Decodable, Sendable {
    struct Current: Decodable, Sendable {
        /// Unix seconds.
        let time: Int
        let temperature2M: Double
        let apparentTemperature: Double
        let weatherCode: Int
        let windSpeed10M: Double
    }

    struct Hourly: Decodable, Sendable {
        /// Unix seconds, each the start of an hour.
        let time: [Int]
        /// Individual hours may be null in the response.
        let precipitationProbability: [Int?]
    }

    /// The city's offset from UTC at `current.time`; used only to display the
    /// observation in the city's own wall-clock time.
    let utcOffsetSeconds: Int
    let current: Current
    let hourly: Hourly

    /// The rain window must cover at least this many consecutive, non-null hours
    /// from the current one; otherwise the forecast is rejected.
    static let minimumRainHours = 3
    /// The observation must be this close to the moment it was received.
    static let maximumObservationSkew: TimeInterval = 2 * 60 * 60

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
            URLQueryItem(name: "timeformat", value: "unixtime"),
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

    struct RainWindow: Equatable, Sendable {
        /// Highest single-hour probability in the window, 0...100.
        let maximumHourlyProbability: Int
        /// How many consecutive hours, starting with the current one, it covers.
        let hours: Int
    }

    /// The highest hourly probability over up to `lookaheadHours` consecutive
    /// hours starting with the hour that contains `current.time`.
    ///
    /// The window stops at the first null value or the first step that is not
    /// exactly 3600 s. Fewer than `minimumRainHours` usable hours gives nil:
    /// missing data is never read as "dry".
    func rainWindow(lookaheadHours: Int) -> RainWindow? {
        guard lookaheadHours > 0, hourly.time.count == hourly.precipitationProbability.count,
              let start = hourly.time.lastIndex(where: { $0 <= current.time }),
              current.time - hourly.time[start] < 3600
        else { return nil }

        var maximum: Int?
        var hours = 0
        var index = start
        while index < hourly.time.count, hours < lookaheadHours {
            if index > start, hourly.time[index] - hourly.time[index - 1] != 3600 { break }
            guard let value = hourly.precipitationProbability[index] else { break }
            maximum = max(maximum ?? value, value)
            hours += 1
            index += 1
        }

        guard let maximum, hours >= min(Self.minimumRainHours, lookaheadHours) else { return nil }
        return RainWindow(maximumHourlyProbability: min(max(maximum, 0), 100), hours: hours)
    }

    /// "2026-10-19T08:00" in the city's own time, for display only.
    var observedLocalTime: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(current.time + utcOffsetSeconds)))
    }

    /// A report, or nil when the readings are not something RIG should rank on:
    /// non-finite values, negative wind, too little rain data, or an
    /// observation far from the moment it was received.
    func report(for city: WeatherCity, fetchedAt: Date) -> WeatherReport? {
        let observedAt = Date(timeIntervalSince1970: TimeInterval(current.time))
        guard current.apparentTemperature.isFinite,
              current.temperature2M.isFinite,
              current.windSpeed10M.isFinite,
              current.windSpeed10M >= 0,
              abs(fetchedAt.timeIntervalSince(observedAt)) <= Self.maximumObservationSkew,
              let rain = rainWindow(lookaheadHours: WeatherReport.rainLookaheadHours)
        else { return nil }

        return WeatherReport(
            city: city,
            observedLocalTime: observedLocalTime,
            observedAt: observedAt,
            airTemperatureC: current.temperature2M,
            apparentTemperatureC: current.apparentTemperature,
            precipitationProbability: rain.maximumHourlyProbability,
            rainHoursCovered: rain.hours,
            windSpeedKPH: current.windSpeed10M,
            weatherCode: current.weatherCode,
            fetchedAt: fetchedAt
        )
    }
}
