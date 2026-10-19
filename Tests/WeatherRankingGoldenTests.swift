import Foundation
import XCTest
@testable import RIG

/// Reviewed, intentionally small weather-ranking golden matrix.
///
/// The wardrobe is constructed to isolate *weather* from style and preference:
/// three black tops (winter, summer, unknown/all-season), one black all-season
/// bottom, and one black all-season outer layer. Colour harmony and explicit
/// favourites are therefore identical across base looks. No footwear/fabric
/// assumption is made. The differences below should come from temperature,
/// wind, precipitation, and the documented structural completeness bonus.
///
/// These are behaviour-regression fixtures, NOT claims about what humans
/// should wear at a given temperature. Review the expected signatures when
/// changing weather rules rather than blindly regenerating them.
///
/// Issue #7 (resolved): weather-aware ranking no longer counts the
/// OutfitCompleteness outerwear bonus, so an optional layer is WeatherComfort's
/// decision alone. 'mild' and 'mild-rain' were re-reviewed after that change:
/// the top look is now without the jacket; rain still lifts a layered look to
/// second place in 'mild-rain' through WeatherComfort's small rain term.
final class WeatherRankingGoldenTests: XCTestCase {
    private struct Scenario {
        let label: String
        let temperature: Double
        let windKPH: Double
        let rainProbability: Int
        /// Ranked structural bases (IDs of the selected top garments).
        let expectedTopIDs: [Int]
        /// Whether each ranked look includes the outer layer, in rank order.
        let expectedOuterwear: [Bool]
        /// Expected WeatherComfort of the *top-ranked* outfit, not the total
        /// outfit rule score and not a calibrated fit probability.
        let expectedTopComfort: Double
    }

    private var wardrobe: [GarmentSnapshot] {
        [
            Fixture.garment(1, .top, .black, seasons: [.winter]),
            Fixture.garment(2, .top, .black, seasons: [.summer]),
            Fixture.garment(3, .top, .black, seasons: .all),
            Fixture.garment(4, .bottom, .black, seasons: .all),
            Fixture.garment(5, .outerwear, .black, seasons: .all)
        ]
    }

    private let cases: [Scenario] = [
        Scenario(label: "very-cold", temperature: -5, windKPH: 10, rainProbability: 10,
                 expectedTopIDs: [1, 3, 2], expectedOuterwear: [true, true, true],
                 expectedTopComfort: 0.7946666666666666),
        Scenario(label: "cold-rain", temperature: 5, windKPH: 15, rainProbability: 85,
                 expectedTopIDs: [1, 3, 2], expectedOuterwear: [true, true, true],
                 expectedTopComfort: 0.8066666666666666),
        Scenario(label: "cool-wind", temperature: 12, windKPH: 35, rainProbability: 20,
                 expectedTopIDs: [1, 3, 2], expectedOuterwear: [true, true, true],
                 expectedTopComfort: 0.7946666666666666),
        Scenario(label: "mild", temperature: 18, windKPH: 10, rainProbability: 10,
                 expectedTopIDs: [2, 3, 1], expectedOuterwear: [false, false, true],
                 expectedTopComfort: 0.776),
        Scenario(label: "mild-rain", temperature: 20, windKPH: 15, rainProbability: 75,
                 expectedTopIDs: [2, 3, 1], expectedOuterwear: [false, true, true],
                 expectedTopComfort: 0.772),
        Scenario(label: "warm", temperature: 27, windKPH: 8, rainProbability: 5,
                 expectedTopIDs: [2, 3, 1], expectedOuterwear: [false, false, false],
                 expectedTopComfort: 0.836),
        Scenario(label: "very-hot", temperature: 35, windKPH: 12, rainProbability: 5,
                 expectedTopIDs: [2, 3, 1], expectedOuterwear: [false, false, false],
                 expectedTopComfort: 0.836),
        Scenario(label: "windy-transition", temperature: 17, windKPH: 25, rainProbability: 60,
                 expectedTopIDs: [2, 3, 1], expectedOuterwear: [true, true, true],
                 expectedTopComfort: 0.8066666666666666)
    ]

    func testTopThreeSignaturesAreStableAcrossEightWeatherScenarios() {
        let engine = OutfitEngine()
        for scenario in cases {
            let weather = context(for: scenario)
            let actual = engine.weatherRankedSuggestions(from: wardrobe, weather: weather, limit: 3)
            let expected = zip(scenario.expectedTopIDs, scenario.expectedOuterwear).map { topID, layered in
                var ids = [Fixture.id(topID), Fixture.id(4)]
                if layered { ids.append(Fixture.id(5)) }
                return OutfitSignature.signature(forGarmentIDs: ids)
            }
            XCTAssertEqual(actual.map(\.signature), expected, scenario.label)
            XCTAssertTrue(actual.allSatisfy { OutfitValidator.isValid($0.items) },
                          "Invalid look: \(scenario.label)")
        }
    }

    func testTopComfortScoresMatchReviewedWeatherPolicy() throws {
        let engine = OutfitEngine()
        for scenario in cases {
            let weather = context(for: scenario)
            let top = try XCTUnwrap(
                engine.weatherRankedSuggestions(from: wardrobe, weather: weather, limit: 1).first,
                scenario.label
            )
            XCTAssertEqual(
                WeatherComfort.score(for: top.items, weather: weather),
                scenario.expectedTopComfort,
                accuracy: 1e-9,
                scenario.label
            )
        }
    }

    func testColdAndHotScenariosFavorOppositeLayerProfiles() throws {
        let engine = OutfitEngine()
        let cold = try XCTUnwrap(cases.first { $0.label == "very-cold" })
        let hot = try XCTUnwrap(cases.first { $0.label == "very-hot" })
        let coldTop = try XCTUnwrap(engine.weatherRankedSuggestions(
            from: wardrobe, weather: context(for: cold), limit: 1
        ).first)
        let hotTop = try XCTUnwrap(engine.weatherRankedSuggestions(
            from: wardrobe, weather: context(for: hot), limit: 1
        ).first)

        XCTAssertTrue(coldTop.candidate.contains(.outerwear))
        XCTAssertFalse(hotTop.candidate.contains(.outerwear))
        XCTAssertTrue(coldTop.items.contains { $0.id == Fixture.id(1) })
        XCTAssertTrue(hotTop.items.contains { $0.id == Fixture.id(2) })
    }

    /// Acceptance (issue #7): in mild weather without strong wind, the top look
    /// must not carry the jacket merely because completeness rewards it.
    func testMildWeatherTopLookIsNotPushedIntoAJacket() throws {
        let engine = OutfitEngine()
        for temperature in stride(from: 18.0, through: 24.0, by: 1.0) {
            for rain in [10, 75] {
                let weather = WeatherContext(apparentTemperatureC: temperature,
                                             precipitationProbability: rain, windSpeedKPH: 10)
                let top = try XCTUnwrap(engine.weatherRankedSuggestions(from: wardrobe, weather: weather, limit: 1).first)
                XCTAssertFalse(top.candidate.contains(.outerwear), "\(temperature)°C, rain \(rain)%")
            }
        }
    }

    /// The no-forecast path keeps its original completeness scoring.
    func testRankingWithoutWeatherStillCountsOuterwearCompleteness() {
        let items = [Fixture.garment(1, .top), Fixture.garment(4, .bottom), Fixture.garment(5, .outerwear)]
        XCTAssertEqual(OutfitCompleteness.score(for: items), 0.70, accuracy: 1e-9)
        XCTAssertEqual(OutfitCompleteness.score(for: items, countingOuterwear: false), 0.60, accuracy: 1e-9)
        XCTAssertEqual(OutfitEngine().score(items).completeness, 0.70, accuracy: 1e-9)
    }

    func testGoldenRankIsInsensitiveToWardrobeInputOrder() {
        let engine = OutfitEngine()
        for scenario in cases {
            let weather = context(for: scenario)
            let ordered = engine.weatherRankedSuggestions(from: wardrobe, weather: weather)
            let reversed = engine.weatherRankedSuggestions(from: wardrobe.reversed(), weather: weather)
            XCTAssertEqual(ordered.map(\.signature), reversed.map(\.signature), scenario.label)
        }
    }

    private func context(for scenario: Scenario) -> WeatherContext {
        WeatherContext(
            apparentTemperatureC: scenario.temperature,
            precipitationProbability: scenario.rainProbability,
            windSpeedKPH: scenario.windKPH
        )
    }
}
