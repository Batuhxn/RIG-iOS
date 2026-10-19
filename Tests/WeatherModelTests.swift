import Foundation
import XCTest
@testable import RIG

/// Answers per city after a per-city delay, so a slow city can be overtaken.
final class DelayedWeatherProvider: WeatherProviding, @unchecked Sendable {
    let delays: [String: UInt64]

    init(delays: [String: UInt64]) {
        self.delays = delays
    }

    func forecast(for city: WeatherCity) async throws -> WeatherReport {
        try await Task.sleep(nanoseconds: delays[city.id] ?? 0)
        return WeatherFixture.report(city, fetchedAt: Date())
    }
}

/// Takes 300 ms to decline, so the rules-only async path is slow.
struct SlowCompatibilityProvider: CompatibilityProvider {
    let isEnabled = true

    func compatibilitySignal(for items: [GarmentSnapshot]) async throws -> Double? {
        try? await Task.sleep(nanoseconds: 300_000_000)
        return nil
    }
}

@MainActor
final class WeatherModelTests: XCTestCase {
    private var suiteName = ""
    private var defaults = UserDefaults.standard

    override func setUp() async throws {
        suiteName = "rig.weather.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName) ?? .standard
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func repository(_ provider: any WeatherProviding) -> WeatherRepository {
        WeatherRepository(provider: provider, cache: WeatherCache(storage: InMemoryWeatherStorage()))
    }

    func testNoCityMeansNoRequest() async {
        let provider = StubWeatherProvider(.success(WeatherFixture.report()))
        let model = WeatherModel(defaultsSuiteName: suiteName)
        await model.start(using: repository(provider))
        XCTAssertEqual(model.state, .noCity)
        XCTAssertEqual(provider.calls, 0)
        XCTAssertNil(model.rankingContext)
    }

    func testSelectionIsRememberedAndLoaded() async {
        let izmir = WeatherCity.presets[2]
        let model = WeatherModel(defaultsSuiteName: suiteName)
        await model.select(izmir, using: repository(StubWeatherProvider(.success(WeatherFixture.report(izmir)))))
        XCTAssertEqual(model.state.report?.city, izmir)
        XCTAssertFalse(model.isRefreshing)
        let relaunched = WeatherModel(defaultsSuiteName: suiteName)
        await relaunched.start(using: repository(StubWeatherProvider(.success(WeatherFixture.report(izmir)))))
        XCTAssertEqual(relaunched.selectedCity, izmir)
    }

    func testSlowEarlierCityNeverOverwritesNewerSelection() async {
        let ankara = WeatherCity.presets[1]
        let izmir = WeatherCity.presets[2]
        let repository = repository(DelayedWeatherProvider(delays: ["ankara": 300_000_000, "izmir": 0]))
        let model = WeatherModel(defaultsSuiteName: suiteName)

        let slow = Task { await model.select(ankara, using: repository) }
        try? await Task.sleep(nanoseconds: 20_000_000)
        await model.select(izmir, using: repository)
        await slow.value

        XCTAssertEqual(model.state.report?.city, izmir)
        XCTAssertEqual(model.selectedCity, izmir)
    }

    func testSupersededCityIsCancelledAndNotCached() async {
        let ankara = WeatherCity.presets[1]
        let izmir = WeatherCity.presets[2]
        let cache = WeatherCache(storage: InMemoryWeatherStorage())
        let repository = WeatherRepository(
            provider: DelayedWeatherProvider(delays: ["ankara": 300_000_000, "izmir": 0]),
            cache: cache
        )
        let model = WeatherModel(defaultsSuiteName: suiteName)

        let slow = Task { await model.select(ankara, using: repository) }
        try? await Task.sleep(nanoseconds: 20_000_000)
        await model.select(izmir, using: repository)
        await slow.value

        XCTAssertNil(cache.report(for: ankara, now: Date()), "a superseded request must not write the cache")
        XCTAssertNotNil(cache.report(for: izmir, now: Date()))
    }

    func testHomeGlanceReadsCacheOnlyAndNeverFetches() {
        let city = WeatherCity.presets[0]
        let cache = WeatherCache(storage: InMemoryWeatherStorage())
        let provider = StubWeatherProvider(.success(WeatherFixture.report(city)))
        let repository = WeatherRepository(provider: provider, cache: cache)
        let model = WeatherModel(defaultsSuiteName: suiteName)

        model.showCached(using: repository)
        XCTAssertEqual(model.state, .noCity, "no saved city: nothing to show")

        defaults.set(city.id, forKey: "rig.weather.selectedCityID")
        model.showCached(using: repository)
        XCTAssertEqual(model.state, .noCity, "saved city but empty cache: still nothing, and no request")

        let report = WeatherFixture.report(city, fetchedAt: Date())
        cache.store(report)
        model.showCached(using: repository)
        XCTAssertEqual(model.state.report, report)
        XCTAssertEqual(provider.calls, 0)
    }

    func testOfflineWithoutCacheIsExplicit() async {
        let model = WeatherModel(defaultsSuiteName: suiteName)
        let city = WeatherCity.presets[0]
        await model.select(city, using: repository(StubWeatherProvider(.failure(.offline))))
        XCTAssertEqual(model.state, .unavailable(city, .offline))
        XCTAssertNil(model.rankingContext)
    }

    func testClearingCityCancelsInFlightResult() async {
        let repository = repository(DelayedWeatherProvider(delays: ["istanbul": 200_000_000]))
        let model = WeatherModel(defaultsSuiteName: suiteName)
        let pending = Task { await model.select(WeatherCity.presets[0], using: repository) }
        try? await Task.sleep(nanoseconds: 20_000_000)
        model.clearCity()
        await pending.value
        XCTAssertEqual(model.state, .noCity)
        XCTAssertNil(model.selectedCity)
    }

    // MARK: - Suggestions with weather

    func testSuggestionsUseWeatherRankingWhenForecastIsUsable() async {
        let wardrobe = Fixture.smallWardrobe()
        let cold = WeatherContext(apparentTemperatureC: 2, precipitationProbability: 10, windSpeedKPH: 5)
        let model = SuggestionsModel()
        await model.generate(wardrobe: wardrobe, engine: OutfitEngine(), startOver: true, weather: cold)
        XCTAssertEqual(
            model.suggestions.map(\.signature),
            OutfitEngine().weatherRankedSuggestions(from: wardrobe, weather: cold).map(\.signature)
        )
    }

    /// The first, weatherless generate is slow (its engine consults a delayed
    /// provider); a forecast arrives and a weather generate finishes first. The
    /// late weatherless result must not replace the weather-ranked looks.
    func testLateWeatherlessResultNeverOverwritesWeatherRanking() async {
        let wardrobe = Fixture.smallWardrobe()
        let cold = WeatherContext(apparentTemperatureC: 2, precipitationProbability: 10, windSpeedKPH: 5)
        let slowEngine = OutfitEngine(compatibilityProvider: SlowCompatibilityProvider())
        let model = SuggestionsModel()

        let first = Task { await model.generate(wardrobe: wardrobe, engine: slowEngine, startOver: true, weather: nil) }
        try? await Task.sleep(nanoseconds: 20_000_000)
        await model.generate(wardrobe: wardrobe, engine: slowEngine, startOver: true, weather: cold)
        await first.value

        XCTAssertEqual(
            model.suggestions.map(\.signature),
            OutfitEngine().weatherRankedSuggestions(from: wardrobe, weather: cold).map(\.signature)
        )
        XCTAssertFalse(model.isLoading)
    }

    func testFreshCacheOnStartMakesNoRequest() async {
        let city = WeatherCity.presets[0]
        let cache = WeatherCache(storage: InMemoryWeatherStorage())
        cache.store(WeatherFixture.report(city, fetchedAt: Date()))
        let provider = StubWeatherProvider(.failure(.offline))
        defaults.set(city.id, forKey: "rig.weather.selectedCityID")

        let model = WeatherModel(defaultsSuiteName: suiteName)
        await model.start(using: WeatherRepository(provider: provider, cache: cache))

        XCTAssertEqual(provider.calls, 0)
        XCTAssertFalse(model.isRefreshing)
        XCTAssertNotNil(model.rankingContext)
    }

    func testSuggestionsWithoutWeatherAreUnchanged() async {
        let wardrobe = Fixture.smallWardrobe()
        let withNil = SuggestionsModel()
        await withNil.generate(wardrobe: wardrobe, engine: OutfitEngine(), startOver: true, weather: nil)
        let invalid = SuggestionsModel()
        await invalid.generate(
            wardrobe: wardrobe, engine: OutfitEngine(), startOver: true,
            weather: WeatherContext(apparentTemperatureC: .infinity)
        )
        let expected = await OutfitEngine().suggestions(from: wardrobe).map(\.signature)
        XCTAssertEqual(withNil.suggestions.map(\.signature), expected)
        XCTAssertEqual(invalid.suggestions.map(\.signature), expected)
    }
}
