import Foundation

/// The only file in RIG allowed to use the network. See scripts/static_audit.py,
/// which enforces that and pins the host below.
///
/// What leaves the device: a GET with a preset city's rounded coordinates and
/// the list of fields wanted. No garment, photo, identifier, cookie or user
/// setting is ever sent, and the session stores no cookies or cache on disk.
///
/// Licensing: Open-Meteo's free API is for non-commercial use, with CC BY 4.0
/// attribution (shown on the forecast card). A commercial release needs their
/// commercial terms first; nothing here assumes free production use.
struct OpenMeteoWeatherService: WeatherProviding {
    static let host = "api.open-meteo.com"
    static let attributionURL = URL(string: "https://open-meteo.com/")
    static let requestTimeout: TimeInterval = 10

    /// Swappable transport so tests never touch the network.
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let transport: Transport
    private let now: @Sendable () -> Date

    init(transport: Transport? = nil, now: @escaping @Sendable () -> Date = { Date() }) {
        self.transport = transport ?? Self.ephemeralTransport()
        self.now = now
    }

    static func request(for city: WeatherCity) -> URLRequest? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/v1/forecast"
        components.queryItems = OpenMeteoForecast.queryItems(for: city)
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: requestTimeout)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        return request
    }

    func forecast(for city: WeatherCity) async throws -> WeatherReport {
        guard let request = Self.request(for: city) else { throw WeatherFailure.unusableResponse }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport(request)
        } catch {
            throw WeatherFailure.offline
        }

        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let forecast = try? OpenMeteoForecast.decode(data),
              let report = forecast.report(for: city, fetchedAt: now())
        else { throw WeatherFailure.unusableResponse }
        return report
    }

    private static func ephemeralTransport() -> Transport {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = requestTimeout * 2
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        return { request in try await session.data(for: request) }
    }
}
