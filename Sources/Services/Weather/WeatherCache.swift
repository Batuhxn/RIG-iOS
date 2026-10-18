import Foundation

/// Where cached forecasts live. `UserDefaults` in the app, a dictionary in tests.
protocol WeatherCacheStorage: AnyObject, Sendable {
    func data(forKey key: String) -> Data?
    func set(_ data: Data?, forKey key: String)
}

/// `UserDefaults` is documented as thread-safe but is not `Sendable` on every
/// toolchain, so it is wrapped rather than retroactively declared Sendable.
final class UserDefaultsWeatherStorage: WeatherCacheStorage, @unchecked Sendable {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func data(forKey key: String) -> Data? {
        defaults.data(forKey: key)
    }

    func set(_ data: Data?, forKey key: String) {
        defaults.set(data, forKey: key)
    }
}

/// Last good forecast per city, with explicit age rules.
///
/// - Younger than `freshInterval`: shown and ranked on without a network call.
/// - Younger than `usableInterval`: shown as stale with its age, and ranked on
///   only when a refresh fails.
/// - Older: discarded. A forecast from this morning says nothing about tonight.
struct WeatherCache: Sendable {
    static let freshInterval: TimeInterval = 45 * 60
    static let usableInterval: TimeInterval = 3 * 60 * 60

    enum Age: Equatable, Sendable {
        case fresh
        case stale
    }

    private let storage: any WeatherCacheStorage
    private let keyPrefix = "rig.weather.report."

    init(storage: any WeatherCacheStorage) {
        self.storage = storage
    }

    func store(_ report: WeatherReport) {
        guard let data = try? JSONEncoder().encode(report) else { return }
        storage.set(data, forKey: keyPrefix + report.city.id)
    }

    /// The cached report and how old it is, or nil when nothing usable exists.
    /// A report "from the future" (device clock moved back) is treated as stale
    /// rather than fresh, so a wrong clock cannot pin an old forecast forever.
    func report(for city: WeatherCity, now: Date) -> (report: WeatherReport, age: Age)? {
        guard let data = storage.data(forKey: keyPrefix + city.id),
              let report = try? JSONDecoder().decode(WeatherReport.self, from: data),
              report.city.id == city.id
        else { return nil }

        let elapsed = now.timeIntervalSince(report.fetchedAt)
        if elapsed < 0 { return (report, .stale) }
        if elapsed < Self.freshInterval { return (report, .fresh) }
        if elapsed < Self.usableInterval { return (report, .stale) }
        return nil
    }

    func clear(_ city: WeatherCity) {
        storage.set(nil, forKey: keyPrefix + city.id)
    }
}
