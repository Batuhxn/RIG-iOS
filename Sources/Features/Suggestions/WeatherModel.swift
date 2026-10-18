import Foundation
import Observation

/// The forecast card's state: which city, and what is known about its weather.
///
/// The chosen city is remembered on this device only. Nothing is fetched until
/// the user has picked one, so a first launch makes no network request at all.
@MainActor
@Observable
final class WeatherModel {
    private(set) var state: WeatherState = .noCity
    private(set) var isRefreshing = false
    private(set) var selectedCityID: String?

    @ObservationIgnored private var gate = LatestRequestGate()
    @ObservationIgnored private var inFlight: Task<WeatherState, Never>?
    /// nil means `UserDefaults.standard`; tests pass a throwaway suite.
    nonisolated private let defaultsSuiteName: String?
    nonisolated private static let cityKey = "rig.weather.selectedCityID"

    /// Nonisolated for the same reason as `SuggestionsModel`: it is created as a
    /// `@State` default inside a view struct, so it touches only a `Sendable`
    /// constant. The saved city is read on the main actor in `start(using:)`.
    nonisolated init(defaultsSuiteName: String? = nil) {
        self.defaultsSuiteName = defaultsSuiteName
    }

    private var defaults: UserDefaults {
        defaultsSuiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    var selectedCity: WeatherCity? {
        selectedCityID.flatMap(WeatherCity.preset(id:))
    }

    /// The forecast suggestions should be ranked against, if any.
    var rankingContext: WeatherContext? { state.rankingContext }

    /// First appearance: paint any cached forecast immediately, then refresh it
    /// in the background if it is not fresh.
    func start(using repository: WeatherRepository) async {
        selectedCityID = defaults.string(forKey: Self.cityKey)
        guard let city = selectedCity else {
            state = .noCity
            return
        }
        if let cached = repository.cachedState(for: city) {
            state = cached
            // Fresh enough: no request, and no refresh spinner flashing by.
            if case .ready(_, .fresh) = cached { return }
        }
        await load(city, using: repository, forceRefresh: false)
    }

    func select(_ city: WeatherCity, using repository: WeatherRepository) async {
        defaults.set(city.id, forKey: Self.cityKey)
        selectedCityID = city.id
        state = repository.cachedState(for: city) ?? .loading(city)
        await load(city, using: repository, forceRefresh: false)
    }

    func refresh(using repository: WeatherRepository) async {
        guard let city = selectedCity else { return }
        await load(city, using: repository, forceRefresh: true)
    }

    func clearCity() {
        _ = gate.issue()
        inFlight?.cancel()
        inFlight = nil
        defaults.removeObject(forKey: Self.cityKey)
        selectedCityID = nil
        isRefreshing = false
        state = .noCity
    }

    private func load(_ city: WeatherCity, using repository: WeatherRepository, forceRefresh: Bool) async {
        let ticket = gate.issue()
        // Cancel the superseded request so it stops its network call and skips
        // its cache write. The gate below is still what guarantees correctness.
        inFlight?.cancel()
        isRefreshing = true
        if state.report == nil {
            state = .loading(city)
        }

        let task = Task { await repository.load(city, forceRefresh: forceRefresh) }
        inFlight = task
        let result = await task.value

        // A newer request (another city, or a manual refresh) owns the card now.
        guard gate.isCurrent(ticket) else { return }
        inFlight = nil
        isRefreshing = false
        state = result
    }
}
