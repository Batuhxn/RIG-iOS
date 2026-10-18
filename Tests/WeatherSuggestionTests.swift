import Foundation
import XCTest
@testable import RIG

final class WeatherSuggestionTests: XCTestCase {
    private let base = [
        Fixture.garment(1, .top, .white),
        Fixture.garment(2, .bottom, .black)
    ]
    private var layered: [GarmentSnapshot] { base + [Fixture.garment(3, .outerwear, .navy)] }

    func testColdLookWithoutLayerSaysSoPlainly() {
        let notes = WeatherOutfitNote.notes(for: base, weather: WeatherContext(apparentTemperatureC: 6))
        XCTAssertEqual(notes.first, "No outer layer here, and it feels like 6°C outside.")
    }

    func testColdLookWithLayerNamesTheLayerNotItsWarmth() {
        let notes = WeatherOutfitNote.notes(for: layered, weather: WeatherContext(apparentTemperatureC: 6))
        XCTAssertEqual(notes.first, "Includes an outer layer for a feels-like 6°C.")
    }

    func testWarmLookWithoutLayer() {
        let notes = WeatherOutfitNote.notes(for: base, weather: WeatherContext(apparentTemperatureC: 29))
        XCTAssertEqual(notes, ["No extra layer for a feels-like 29°C."])
    }

    func testMildDryCalmWeatherAddsNothing() {
        XCTAssertTrue(WeatherOutfitNote.notes(for: base, weather: WeatherContext(apparentTemperatureC: 20)).isEmpty)
    }

    func testWindAloneTriggersLayerNoteWhenCool() {
        let windy = WeatherContext(apparentTemperatureC: 16, windSpeedKPH: 32)
        XCTAssertEqual(
            WeatherOutfitNote.notes(for: base, weather: windy),
            ["No outer layer here, and it feels like 16°C outside.", "Windy at 32 km/h."]
        )
    }

    func testRainNoteNeverClaimsProtection() {
        let wet = WeatherContext(apparentTemperatureC: 8, precipitationProbability: 80, windSpeedKPH: 40)
        let notes = WeatherOutfitNote.notes(for: layered, weather: wet)
        XCTAssertEqual(notes.count, WeatherOutfitNote.maximumNotes)
        XCTAssertTrue(notes[1].hasPrefix("80% chance of rain"))
        let banned = ["waterproof", "water-resistant", "warm enough", "keeps you", "protects", "dry"]
        for note in notes {
            for word in banned {
                XCTAssertFalse(note.lowercased().contains(word), "\"\(note)\" contains \"\(word)\"")
            }
        }
    }

    func testUnusableForecastProducesNoNotes() {
        XCTAssertTrue(WeatherOutfitNote.notes(for: base, weather: WeatherContext(apparentTemperatureC: .nan)).isEmpty)
        XCTAssertTrue(WeatherOutfitNote.notes(for: [], weather: WeatherContext(apparentTemperatureC: 5)).isEmpty)
    }

    func testTemperatureFormattingAvoidsNegativeZero() {
        XCTAssertEqual(WeatherOutfitNote.formattedTemperature(-0.3), "0°C")
        XCTAssertEqual(WeatherOutfitNote.formattedTemperature(-4.6), "-5°C")
        XCTAssertEqual(WeatherOutfitNote.formattedTemperature(12.5), "13°C")
    }

    /// The note and the ranking must agree: in cold weather the top weather
    /// ranked look carries an outer layer whenever the wardrobe has one.
    func testColdRankingAndNotesAgree() {
        let engine = OutfitEngine()
        let cold = WeatherContext(apparentTemperatureC: 3, precipitationProbability: 10, windSpeedKPH: 5)
        let top = engine.weatherRankedSuggestions(from: Fixture.smallWardrobe(), weather: cold, limit: 1)
        let first = try? XCTUnwrap(top.first)
        XCTAssertNotNil(first)
        if let first {
            XCTAssertTrue(first.items.contains { $0.category == .outerwear })
            XCTAssertEqual(
                WeatherOutfitNote.notes(for: first.items, weather: cold).first,
                "Includes an outer layer for a feels-like 3°C."
            )
        }
    }

    func testRankingContextOnlyFromUsableStates() {
        let city = WeatherCity.presets[0]
        let report = WeatherFixture.report(apparent: 5)
        XCTAssertEqual(WeatherState.ready(report, .stale).rankingContext, report.context)
        XCTAssertNil(WeatherState.loading(city).rankingContext)
        XCTAssertNil(WeatherState.noCity.rankingContext)
        XCTAssertNil(WeatherState.unavailable(city, .offline).rankingContext)
    }
}
