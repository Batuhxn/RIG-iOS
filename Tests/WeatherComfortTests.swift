import XCTest
@testable import RIG

final class WeatherComfortTests: XCTestCase {
    func testColdConditionsPreferLayering() {
        let base = [
            Fixture.garment(1, .top, .black, seasons: [.winter]),
            Fixture.garment(2, .bottom, .gray, seasons: [.winter])
        ]
        let layered = base + [Fixture.garment(3, .outerwear, .black, seasons: [.winter])]
        let weather = WeatherContext(apparentTemperatureC: 3)
        XCTAssertGreaterThan(
            WeatherComfort.score(for: layered, weather: weather),
            WeatherComfort.score(for: base, weather: weather)
        )
    }

    func testWarmConditionsPreferLightOutfitOverExtraLayer() {
        let base = [
            Fixture.garment(1, .top, .white, seasons: [.summer]),
            Fixture.garment(2, .bottom, .blue, seasons: [.summer])
        ]
        let layered = base + [Fixture.garment(3, .outerwear, .black, seasons: [.winter])]
        let weather = WeatherContext(apparentTemperatureC: 31)
        XCTAssertGreaterThan(
            WeatherComfort.score(for: base, weather: weather),
            WeatherComfort.score(for: layered, weather: weather)
        )
    }

    func testInvalidForecastFallsBackToUnchangedRanking() {
        let wardrobe = Fixture.smallWardrobe()
        let engine = OutfitEngine()
        let invalid = WeatherContext(apparentTemperatureC: .nan)
        XCTAssertEqual(
            engine.weatherRankedSuggestions(from: wardrobe, weather: invalid).map(\.signature),
            engine.rankedSuggestions(from: wardrobe).map(\.signature)
        )
    }

    func testWeatherRankingIsDeterministicAndValid() {
        let engine = OutfitEngine()
        let wardrobe = Fixture.largeWardrobe()
        let weather = WeatherContext(apparentTemperatureC: 6, precipitationProbability: 80, windSpeedKPH: 30)
        let first = engine.weatherRankedSuggestions(from: wardrobe, weather: weather, limit: 3)
        let second = engine.weatherRankedSuggestions(from: wardrobe, weather: weather, limit: 3)
        XCTAssertEqual(first.map(\.signature), second.map(\.signature))
        XCTAssertTrue(first.allSatisfy { OutfitValidator.isValid($0.items) })
    }

    func testPrecipitationIsNotTreatedAsWaterproofMetadata() {
        let outfit = [
            Fixture.garment(1, .top, .white),
            Fixture.garment(2, .bottom, .black)
        ]
        let dry = WeatherComfort.score(for: outfit, weather: WeatherContext(apparentTemperatureC: 15))
        let wet = WeatherComfort.score(for: outfit, weather: WeatherContext(apparentTemperatureC: 15, precipitationProbability: 90))
        XCTAssertLessThan(abs(dry - wet), 0.1)
    }
}
