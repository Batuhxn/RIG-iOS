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


    func testTemperatureSeasonThresholdsAtEightSeventeenAndTwentyFive() {
        func outfit(_ season: SeasonSet) -> [GarmentSnapshot] {
            [
                Fixture.garment(10, .top, .black, seasons: season),
                Fixture.garment(11, .bottom, .gray, seasons: season)
            ]
        }
        func comfort(_ items: [GarmentSnapshot], at temperature: Double) -> Double {
            WeatherComfort.score(for: items, weather: WeatherContext(apparentTemperatureC: temperature))
        }

        let autumn = outfit([.autumn])
        XCTAssertGreaterThan(comfort(autumn, at: 8.0), comfort(autumn, at: 7.999))

        let winter = outfit([.winter])
        XCTAssertGreaterThan(comfort(winter, at: 16.999), comfort(winter, at: 17.0))

        let spring = outfit([.spring])
        XCTAssertGreaterThan(comfort(spring, at: 24.999), comfort(spring, at: 25.0))
    }

    func testTwelveDegreeLayeringThresholdIsInclusive() {
        let base = [
            Fixture.garment(10, .top, .black, seasons: [.winter]),
            Fixture.garment(11, .bottom, .gray, seasons: [.winter])
        ]
        let atTwelve = WeatherComfort.score(for: base, weather: WeatherContext(apparentTemperatureC: 12))
        let justAbove = WeatherComfort.score(for: base, weather: WeatherContext(apparentTemperatureC: 12.001))
        XCTAssertLessThan(atTwelve, justAbove)
    }

    func testWindThresholdRequiresTwentyFiveKphAtMostEighteenDegrees() {
        let base = [
            Fixture.garment(10, .top, .black, seasons: [.autumn]),
            Fixture.garment(11, .bottom, .gray, seasons: [.autumn])
        ]
        let layered = base + [Fixture.garment(12, .outerwear, .beige, seasons: [.autumn])]

        func comfort(_ items: [GarmentSnapshot], temperature: Double, wind: Double) -> Double {
            WeatherComfort.score(
                for: items,
                weather: WeatherContext(apparentTemperatureC: temperature, windSpeedKPH: wind)
            )
        }

        XCTAssertGreaterThan(
            comfort(layered, temperature: 18, wind: 25),
            comfort(layered, temperature: 18, wind: 24.999)
        )
        XCTAssertLessThan(
            comfort(base, temperature: 18, wind: 25),
            comfort(base, temperature: 18, wind: 24.999)
        )
        XCTAssertGreaterThan(
            comfort(base, temperature: 18.001, wind: 25),
            comfort(base, temperature: 18, wind: 25)
        )
    }

    func testAllSeasonMetadataIsNeutralRatherThanPerfect() {
        let neutral = [
            Fixture.garment(10, .top, .white, seasons: .all),
            Fixture.garment(11, .bottom, .black, seasons: .all)
        ]
        let explicitSummer = [
            Fixture.garment(20, .top, .white, seasons: [.summer]),
            Fixture.garment(21, .bottom, .black, seasons: [.summer])
        ]
        let weather = WeatherContext(apparentTemperatureC: 28)
        XCTAssertLessThan(
            WeatherComfort.score(for: neutral, weather: weather),
            WeatherComfort.score(for: explicitSummer, weather: weather)
        )
    }

    func testInvalidWeatherAndPrecipitationClamping() {
        let items = [
            Fixture.garment(10, .top),
            Fixture.garment(11, .bottom)
        ]
        XCTAssertFalse(WeatherContext(apparentTemperatureC: .infinity).isUsable)
        XCTAssertFalse(WeatherContext(apparentTemperatureC: 18, windSpeedKPH: -.infinity).isUsable)
        XCTAssertEqual(
            WeatherComfort.score(for: items, weather: WeatherContext(apparentTemperatureC: .nan)),
            0.5
        )
        XCTAssertEqual(WeatherContext(apparentTemperatureC: 18, precipitationProbability: -10).precipitationProbability, 0)
        XCTAssertEqual(WeatherContext(apparentTemperatureC: 18, precipitationProbability: 120).precipitationProbability, 100)
    }
}
