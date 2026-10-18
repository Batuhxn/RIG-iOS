import Foundation
import XCTest
@testable import RIG

final class WeatherForecastParsingTests: XCTestCase {
    private let istanbul = WeatherCity.presets[0]
    /// 2026-10-19T00:00:00Z.
    static let midnightUTC = 1_792_368_000
    static let offset = 10_800

    /// Shaped like a real Open-Meteo response with timeformat=unixtime.
    /// `hours` lists the hourly timestamps as offsets in hours from midnight UTC.
    static func sampleJSON(
        currentMinutesAfterMidnight: Int = 90,
        apparent: String = "13.2",
        hours: [Int] = Array(0..<8),
        probabilities: String = "0,5,10,40,70,20,90,100"
    ) -> Data {
        let times = hours.map { String(midnightUTC + $0 * 3600) }.joined(separator: ",")
        let current = midnightUTC + currentMinutesAfterMidnight * 60
        let json = """
        {"latitude":41.02,"longitude":28.94,"utc_offset_seconds":\(offset),"timezone":"Europe/Istanbul",
         "current":{"time":\(current),"interval":900,"temperature_2m":13.8,
                    "apparent_temperature":\(apparent),"weather_code":61,"wind_speed_10m":7.1},
         "hourly":{"time":[\(times)],"precipitation_probability":[\(probabilities)]}}
        """
        return Data(json.utf8)
    }

    /// The instant of `current` in the default sample.
    private var observed: Date {
        Date(timeIntervalSince1970: TimeInterval(Self.midnightUTC + 90 * 60))
    }

    func testDecodesCurrentReadings() throws {
        let forecast = try OpenMeteoForecast.decode(Self.sampleJSON())
        XCTAssertEqual(forecast.current.apparentTemperature, 13.2)
        XCTAssertEqual(forecast.current.windSpeed10M, 7.1)
        XCTAssertEqual(forecast.current.weatherCode, 61)
        XCTAssertEqual(forecast.utcOffsetSeconds, Self.offset)
    }

    func testObservedLocalTimeUsesTheCityOffset() throws {
        // 01:30 UTC + 3 h.
        XCTAssertEqual(try OpenMeteoForecast.decode(Self.sampleJSON()).observedLocalTime, "2026-10-19T04:30")
    }

    func testRainWindowStartsAtTheHourContainingNow() throws {
        // Current 01:30Z -> hours 01..06 -> [5, 10, 40, 70, 20, 90] -> 90 over 6 h.
        let forecast = try OpenMeteoForecast.decode(Self.sampleJSON())
        XCTAssertEqual(forecast.rainWindow(lookaheadHours: 6), .init(maximumHourlyProbability: 90, hours: 6))
        XCTAssertEqual(forecast.rainWindow(lookaheadHours: 3), .init(maximumHourlyProbability: 40, hours: 3))
    }

    func testRainWindowShrinksAtEndOfSeriesButReportsItsCoverage() throws {
        let forecast = try OpenMeteoForecast.decode(Self.sampleJSON(currentMinutesAfterMidnight: 5 * 60))
        // Hours 05, 06, 07 only.
        XCTAssertEqual(forecast.rainWindow(lookaheadHours: 6), .init(maximumHourlyProbability: 100, hours: 3))
    }

    func testRainWindowStopsAtANullHour() throws {
        let forecast = try OpenMeteoForecast.decode(Self.sampleJSON(probabilities: "0,5,10,40,null,20,90,100"))
        // Hours 01, 02, 03 then null: max 40 over 3 h; the 90 after the gap is not used.
        XCTAssertEqual(forecast.rainWindow(lookaheadHours: 6), .init(maximumHourlyProbability: 40, hours: 3))
    }

    func testTooFewUsableHoursRejectsTheForecast() throws {
        let forecast = try OpenMeteoForecast.decode(Self.sampleJSON(probabilities: "0,5,null,40,70,20,90,100"))
        XCTAssertNil(forecast.rainWindow(lookaheadHours: 6))
        XCTAssertNil(forecast.report(for: istanbul, fetchedAt: observed))
    }

    func testRepeatedHourBreaksTheWindow() throws {
        // A duplicated hour (fall-back DST or a feed glitch): 01, 02, 02, 03 ...
        let forecast = try OpenMeteoForecast.decode(
            Self.sampleJSON(hours: [0, 1, 2, 2, 3, 4, 5, 6], probabilities: "0,5,10,99,40,70,20,90")
        )
        // Window is 01, 02 then a 0 s step -> only 2 hours -> rejected.
        XCTAssertNil(forecast.rainWindow(lookaheadHours: 6))
    }

    func testSkippedHourBreaksTheWindow() throws {
        // 01, 02, 03, then 05: the window ends at 03.
        let forecast = try OpenMeteoForecast.decode(
            Self.sampleJSON(hours: [0, 1, 2, 3, 5, 6, 7, 8], probabilities: "0,5,10,40,99,99,99,99")
        )
        XCTAssertEqual(forecast.rainWindow(lookaheadHours: 6), .init(maximumHourlyProbability: 40, hours: 3))
    }

    func testCurrentOutsideTheSeriesRejectsTheForecast() throws {
        let forecast = try OpenMeteoForecast.decode(Self.sampleJSON(currentMinutesAfterMidnight: 30 * 60))
        XCTAssertNil(forecast.rainWindow(lookaheadHours: 6))
        let early = try OpenMeteoForecast.decode(Self.sampleJSON(hours: Array(2..<10)))
        XCTAssertNil(early.rainWindow(lookaheadHours: 6))
    }

    func testMismatchedSeriesLengthsAreRejected() throws {
        let forecast = try OpenMeteoForecast.decode(Self.sampleJSON(probabilities: "0,5,10,40,70,20,90"))
        XCTAssertNil(forecast.rainWindow(lookaheadHours: 6))
    }

    func testObservationFarFromFetchTimeIsRejected() throws {
        let forecast = try OpenMeteoForecast.decode(Self.sampleJSON())
        XCTAssertNotNil(forecast.report(for: istanbul, fetchedAt: observed.addingTimeInterval(60 * 60)))
        XCTAssertNil(forecast.report(for: istanbul, fetchedAt: observed.addingTimeInterval(3 * 60 * 60)))
        XCTAssertNil(forecast.report(for: istanbul, fetchedAt: observed.addingTimeInterval(-3 * 60 * 60)))
    }

    func testReportCarriesEngineContextAndCoverage() throws {
        let report = try XCTUnwrap(
            OpenMeteoForecast.decode(Self.sampleJSON()).report(for: istanbul, fetchedAt: observed)
        )
        XCTAssertEqual(report.context, WeatherContext(apparentTemperatureC: 13.2, precipitationProbability: 90, windSpeedKPH: 7.1))
        XCTAssertEqual(report.rainHoursCovered, 6)
        XCTAssertEqual(report.condition, .rain)
        XCTAssertEqual(report.observedAt, observed)
        XCTAssertEqual(report.fetchedAt, observed)
    }

    func testMalformedJSONThrows() {
        XCTAssertThrowsError(try OpenMeteoForecast.decode(Data("{\"current\":{}}".utf8)))
    }

    func testRequestIsAMinimalCookielessGetToOpenMeteo() throws {
        let request = try XCTUnwrap(OpenMeteoWeatherService.request(for: istanbul))
        let url = try XCTUnwrap(request.url)
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "api.open-meteo.com")
        XCTAssertEqual(url.path, "/v1/forecast")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertNil(request.httpBody)
        XCTAssertFalse(request.httpShouldHandleCookies)
        XCTAssertEqual(request.timeoutInterval, OpenMeteoWeatherService.requestTimeout)

        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(Set(items.map(\.name)), [
            "latitude", "longitude", "current", "hourly", "temperature_unit",
            "wind_speed_unit", "timeformat", "timezone", "forecast_days"
        ])
        XCTAssertEqual(items.first { $0.name == "latitude" }?.value, "41.01")
        XCTAssertEqual(items.first { $0.name == "timeformat" }?.value, "unixtime")
    }

    func testServiceMapsTransportErrorToOffline() async {
        let service = OpenMeteoWeatherService(transport: { _ in throw URLError(.notConnectedToInternet) })
        do {
            _ = try await service.forecast(for: istanbul)
            XCTFail("Expected offline failure")
        } catch {
            XCTAssertEqual(error as? WeatherFailure, .offline)
        }
    }

    func testServiceRejectsServerError() async {
        let service = OpenMeteoWeatherService(transport: { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (Self.sampleJSON(), response)
        })
        do {
            _ = try await service.forecast(for: istanbul)
            XCTFail("Expected unusable response")
        } catch {
            XCTAssertEqual(error as? WeatherFailure, .unusableResponse)
        }
    }

    func testServiceReturnsReportOnSuccess() async throws {
        let observed = self.observed
        let service = OpenMeteoWeatherService(
            transport: { request in
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (Self.sampleJSON(), response)
            },
            now: { observed }
        )
        let report = try await service.forecast(for: istanbul)
        XCTAssertEqual(report.city, istanbul)
        XCTAssertEqual(report.precipitationProbability, 90)
    }

    func testConditionCodesMapConservatively() {
        XCTAssertEqual(WeatherCondition(code: 0), .clear)
        XCTAssertEqual(WeatherCondition(code: 3), .cloudy)
        XCTAssertEqual(WeatherCondition(code: 81), .rain)
        XCTAssertEqual(WeatherCondition(code: 75), .snow)
        XCTAssertEqual(WeatherCondition(code: 96), .thunderstorm)
        XCTAssertEqual(WeatherCondition(code: 42), .unknown)
    }

    func testPresetCitiesHaveUniqueIDsAndPlausibleCoordinates() {
        XCTAssertEqual(Set(WeatherCity.presets.map(\.id)).count, WeatherCity.presets.count)
        for city in WeatherCity.presets {
            XCTAssertTrue((35.0...43.0).contains(city.latitude), city.name)
            XCTAssertTrue((25.0...45.0).contains(city.longitude), city.name)
        }
    }
}
