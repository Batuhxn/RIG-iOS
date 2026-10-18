import Foundation

/// Anything that can fetch a forecast. The live one talks to Open-Meteo; tests
/// substitute a stub so no test ever touches the network.
protocol WeatherProviding: Sendable {
    func forecast(for city: WeatherCity) async throws -> WeatherReport
}

enum WeatherFailure: Error, Equatable, Sendable {
    /// No connection, timeout, or a transport error.
    case offline
    /// The service answered but with something RIG will not rank on.
    case unusableResponse
}

/// What the forecast card shows. Every case is explicit so the interface never
/// has to guess whether old numbers are current.
enum WeatherState: Equatable, Sendable {
    case noCity
    case loading(WeatherCity)
    case ready(WeatherReport, WeatherCache.Age)
    /// A refresh failed but a recent forecast exists. Shown with its age.
    case staleAfterFailure(WeatherReport, WeatherFailure)
    case unavailable(WeatherCity, WeatherFailure)

    /// The forecast suggestions may be ranked against, if any.
    var rankingContext: WeatherContext? {
        switch self {
        case .ready(let report, _), .staleAfterFailure(let report, _):
            let context = report.context
            return context.isUsable ? context : nil
        case .noCity, .loading, .unavailable:
            return nil
        }
    }

    var report: WeatherReport? {
        switch self {
        case .ready(let report, _), .staleAfterFailure(let report, _): return report
        case .noCity, .loading, .unavailable: return nil
        }
    }
}

/// Cache first, network second, and a recent forecast over nothing.
struct WeatherRepository: Sendable {
    let provider: any WeatherProviding
    let cache: WeatherCache
    let now: @Sendable () -> Date

    init(provider: any WeatherProviding, cache: WeatherCache, now: @escaping @Sendable () -> Date = { Date() }) {
        self.provider = provider
        self.cache = cache
        self.now = now
    }

    /// The cached state for an immediate first paint, without any network.
    func cachedState(for city: WeatherCity) -> WeatherState? {
        cache.report(for: city, now: now()).map { .ready($0.report, $0.age) }
    }

    func load(_ city: WeatherCity, forceRefresh: Bool = false) async -> WeatherState {
        let cached = cache.report(for: city, now: now())
        if !forceRefresh, let cached, cached.age == .fresh {
            return .ready(cached.report, .fresh)
        }

        do {
            let report = try await provider.forecast(for: city)
            guard report.context.isUsable, report.city.id == city.id else {
                throw WeatherFailure.unusableResponse
            }
            cache.store(report)
            return .ready(report, .fresh)
        } catch {
            let failure = (error as? WeatherFailure) ?? .offline
            if let cached {
                return .staleAfterFailure(cached.report, failure)
            }
            return .unavailable(city, failure)
        }
    }
}

/// A fixed cool, showery forecast for SwiftUI previews. Never touches the network.
struct PreviewWeatherProvider: WeatherProviding {
    func forecast(for city: WeatherCity) async throws -> WeatherReport {
        WeatherReport(
            city: city,
            observedLocalTime: "2026-10-19T08:00",
            airTemperatureC: 11,
            apparentTemperatureC: 9,
            precipitationProbability: 65,
            windSpeedKPH: 14,
            weatherCode: 80,
            fetchedAt: Date()
        )
    }
}

/// Lets only the most recent request publish its result.
///
/// Switching from Ankara to İzmir while Ankara is still loading must never end
/// with Ankara's forecast under İzmir's name. Each request takes a ticket; a
/// result is applied only if its ticket is still the latest one issued.
struct LatestRequestGate: Sendable {
    private(set) var latest: UInt64 = 0

    mutating func issue() -> UInt64 {
        latest &+= 1
        return latest
    }

    func isCurrent(_ ticket: UInt64) -> Bool {
        ticket == latest
    }
}
