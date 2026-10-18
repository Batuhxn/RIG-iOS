import Foundation
import XCTest
@testable import RIG

final class StubWeatherProvider: WeatherProviding, @unchecked Sendable {
    private let lock = NSLock()
    private let result: Result<WeatherReport, WeatherFailure>
    private(set) var calls = 0

    init(_ result: Result<WeatherReport, WeatherFailure>) {
        self.result = result
    }

    func forecast(for city: WeatherCity) async throws -> WeatherReport {
        try recordCall().get()
    }

    private func recordCall() -> Result<WeatherReport, WeatherFailure> {
        lock.lock()
        defer { lock.unlock() }
        calls += 1
        return result
    }
}

enum WeatherFixture {
    static let start = Date(timeIntervalSince1970: 1_800_000_000)

    static func report(
        _ city: WeatherCity = WeatherCity.presets[0],
        apparent: Double = 9,
        rain: Int = 20,
        wind: Double = 10,
        fetchedAt: Date = start
    ) -> WeatherReport {
        WeatherReport(
            city: city,
            observedLocalTime: "2026-10-19T08:00",
            airTemperatureC: apparent + 1,
            apparentTemperatureC: apparent,
            precipitationProbability: rain,
            windSpeedKPH: wind,
            weatherCode: 3,
            fetchedAt: fetchedAt
        )
    }
}

final class WeatherCacheTests: XCTestCase {
    private let city = WeatherCity.presets[0]

    private func cache() -> WeatherCache {
        WeatherCache(storage: InMemoryWeatherStorage())
    }

    func testAgeBoundaries() {
        let cache = cache()
        cache.store(WeatherFixture.report())
        let start = WeatherFixture.start

        XCTAssertEqual(cache.report(for: city, now: start)?.age, .fresh)
        XCTAssertEqual(cache.report(for: city, now: start + WeatherCache.freshInterval - 1)?.age, .fresh)
        XCTAssertEqual(cache.report(for: city, now: start + WeatherCache.freshInterval)?.age, .stale)
        XCTAssertEqual(cache.report(for: city, now: start + WeatherCache.usableInterval - 1)?.age, .stale)
        XCTAssertNil(cache.report(for: city, now: start + WeatherCache.usableInterval))
    }

    func testClockMovedBackIsStaleNotFresh() {
        let cache = cache()
        cache.store(WeatherFixture.report())
        XCTAssertEqual(cache.report(for: city, now: WeatherFixture.start - 600)?.age, .stale)
    }

    func testCitiesDoNotShareEntries() {
        let cache = cache()
        cache.store(WeatherFixture.report(WeatherCity.presets[0]))
        XCTAssertNil(cache.report(for: WeatherCity.presets[1], now: WeatherFixture.start))
    }

    func testCorruptEntryIsIgnored() {
        let storage = InMemoryWeatherStorage()
        storage.set(Data("not json".utf8), forKey: "rig.weather.report.\(city.id)")
        XCTAssertNil(WeatherCache(storage: storage).report(for: city, now: WeatherFixture.start))
    }

    // MARK: - Repository

    private func repository(
        provider: StubWeatherProvider,
        cache: WeatherCache,
        now: Date = WeatherFixture.start
    ) -> WeatherRepository {
        WeatherRepository(provider: provider, cache: cache, now: { now })
    }

    func testFreshCacheSkipsTheNetwork() async {
        let cache = cache()
        cache.store(WeatherFixture.report())
        let provider = StubWeatherProvider(.failure(.offline))
        let state = await repository(provider: provider, cache: cache).load(city)
        XCTAssertEqual(state, .ready(WeatherFixture.report(), .fresh))
        XCTAssertEqual(provider.calls, 0)
    }

    func testForceRefreshFetchesEvenWhenFresh() async {
        let cache = cache()
        cache.store(WeatherFixture.report(apparent: 9))
        let newer = WeatherFixture.report(apparent: 4)
        let provider = StubWeatherProvider(.success(newer))
        let state = await repository(provider: provider, cache: cache).load(city, forceRefresh: true)
        XCTAssertEqual(state, .ready(newer, .fresh))
        XCTAssertEqual(provider.calls, 1)
    }

    func testFailureWithRecentCacheShowsStaleWithReason() async {
        let cache = cache()
        cache.store(WeatherFixture.report())
        let later = WeatherFixture.start + WeatherCache.freshInterval + 60
        let state = await repository(provider: StubWeatherProvider(.failure(.offline)), cache: cache, now: later).load(city)
        XCTAssertEqual(state, .staleAfterFailure(WeatherFixture.report(), .offline))
        XCTAssertNotNil(state.rankingContext)
    }

    func testFailureWithoutCacheIsUnavailableAndNeverRanked() async {
        let state = await repository(provider: StubWeatherProvider(.failure(.unusableResponse)), cache: cache()).load(city)
        XCTAssertEqual(state, .unavailable(city, .unusableResponse))
        XCTAssertNil(state.rankingContext)
        XCTAssertNil(state.report)
    }

    func testSuccessIsCached() async {
        let cache = cache()
        let provider = StubWeatherProvider(.success(WeatherFixture.report()))
        _ = await repository(provider: provider, cache: cache).load(city)
        XCTAssertEqual(cache.report(for: city, now: WeatherFixture.start)?.age, .fresh)
    }

    func testReportForAnotherCityIsRejected() async {
        let wrongCity = WeatherFixture.report(WeatherCity.presets[1])
        let state = await repository(provider: StubWeatherProvider(.success(wrongCity)), cache: cache()).load(city)
        XCTAssertEqual(state, .unavailable(city, .unusableResponse))
    }

    func testCachedStateIsAvailableWithoutNetwork() {
        let cache = cache()
        XCTAssertNil(repository(provider: StubWeatherProvider(.failure(.offline)), cache: cache).cachedState(for: city))
        cache.store(WeatherFixture.report())
        XCTAssertEqual(
            repository(provider: StubWeatherProvider(.failure(.offline)), cache: cache).cachedState(for: city),
            .ready(WeatherFixture.report(), .fresh)
        )
    }

    // MARK: - Latest request gate

    func testOnlyTheLatestTicketIsCurrent() {
        var gate = LatestRequestGate()
        let ankara = gate.issue()
        let izmir = gate.issue()
        XCTAssertFalse(gate.isCurrent(ankara))
        XCTAssertTrue(gate.isCurrent(izmir))
    }
}
