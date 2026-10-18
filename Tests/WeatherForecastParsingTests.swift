import Foundation
import XCTest
@testable import RIG

final class WeatherForecastParsingTests: XCTestCase {
    private let istanbul = WeatherCity.presets[0]
    private let fetchedAt = Date(timeIntervalSince1970: 1_800_000_000)

    /// Trimmed from a real Open-Meteo response (Istanbul, timezone=auto).
    static func sampleJSON(
        currentTime: String = "2026-10-19T01:30",
        apparent: String = "13.2",
        probabilities: String = "0,5,10,null,70,20,90,100"
    ) -> Data {
        let hours = (0..<8).map { String(format: "\"2026-10-19T%02d:00\"", $0) }.joined(separator: ",")
        let json = """
        {"latitude":41.02,"longitude":28.94,"utc_offset_seconds":10800,"timezone":"Europe/Istanbul",
         "current":{"time":"\(currentTime)","interval":900,"temperature_2m":13.8,
                    "apparent_temperature":\(apparent),"weather_code":61,"wind_speed_10m":7.1},
         "hourly":{"time":[\(hours)],"precipitation_probability":[\(probabilities)]}}
        """
        return Data(json.utf8)
    }

    func testDecodesCurrentReadings() throws {
        let forecast = try OpenMeteoForecast.decode(Self.sampleJSON())
        XCTAssertEqual(forecast.current.apparentTemperature, 13.2)
        XCTAssertEqual(forecast.current.windSpeed10M, 7.1)
        XCTAssertEqual(forecast.current.weatherCode, 61)
    }

    func testRainLookaheadStartsAtCurrentHourAndSkipsNulls() throws {
        // Current 01:30 -> hours 01..06 -> [5, 10, null, 70, 20, 90] -> 90.
        let forecast = try OpenMeteoForecast.decode(Self.sampleJSON())
        XCTAssertEqual(forecast.precipitationProbability(lookaheadHours: 6), 90)
        XCTAssertEqual(forecast.precipitationProbability(lookaheadHours: 2), 10)
    }

    func testRainLookaheadIsClippedAtEndOfSeries() throws {
        let forecast = try OpenMeteoForecast.decode(Self.sampleJSON(currentTime: "2026-10-19T07:00"))
        XCTAssertEqual(forecast.precipitationProbability(lookaheadHours: 6), 100)
    }

    func testMissingCurrentHourRejectsTheForecast() throws {
        let forecast = try OpenMeteoForecast.decode(Self.sampleJSON(currentTime: "2026-10-20T12:00"))
        XCTAssertNil(forecast.precipitationProbability(lookaheadHours: 6))
        XCTAssertNil(forecast.report(for: istanbul, fetchedAt: fetchedAt))
    }

    func testAllNullRainIsNotTreatedAsDry() throws {
        let forecast = try OpenMeteoForecast.decode(
            Self.sampleJSON(probabilities: "null,null,null,null,null,null,null,null")
        )
        XCTAssertNil(forecast.report(for: istanbul, fetchedAt: fetchedAt))
    }

    func testReportCarriesEngineContext() throws {
        let report = try XCTUnwrap(
            OpenMeteoForecast.decode(Self.sampleJSON()).report(for: istanbul, fetchedAt: fetchedAt)
        )
        XCTAssertEqual(report.context, WeatherContext(apparentTemperatureC: 13.2, precipitationProbability: 90, windSpeedKPH: 7.1))
        XCTAssertEqual(report.condition, .rain)
        XCTAssertEqual(report.observedLocalTime, "2026-10-19T01:30")
        XCTAssertEqual(report.fetchedAt, fetchedAt)
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
        let names = Set(items.map(\.name))
        XCTAssertEqual(names, [
            "latitude", "longitude", "current", "hourly", "temperature_unit",
            "wind_speed_unit", "timezone", "forecast_days"
        ])
        XCTAssertEqual(items.first { $0.name == "latitude" }?.value, "41.01")
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
        let fetchedAt = self.fetchedAt
        let service = OpenMeteoWeatherService(
            transport: { request in
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (Self.sampleJSON(), response)
            },
            now: { fetchedAt }
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
