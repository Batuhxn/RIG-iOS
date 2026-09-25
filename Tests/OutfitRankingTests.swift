import XCTest
@testable import RIG

final class OutfitRankingTests: XCTestCase {
    private let accuracy = 1e-9

    /// Neutral palette, every garment all-season, shoes present, all favourites.
    private var strongOutfit: [GarmentSnapshot] {
        [
            Fixture.garment(1, .top, .white, favorite: true),
            Fixture.garment(2, .bottom, .gray, favorite: true),
            Fixture.garment(3, .shoes, .black, favorite: true)
        ]
    }

    /// Clashing accents, disjoint seasons, no shoes, nothing favourited.
    private var weakOutfit: [GarmentSnapshot] {
        [
            Fixture.garment(4, .top, .red, seasons: [.summer]),
            Fixture.garment(5, .bottom, .green, seasons: [.winter])
        ]
    }

    func testStrongFixtureOutranksWeakFixture() {
        let engine = OutfitEngine()
        XCTAssertGreaterThan(
            engine.score(strongOutfit).total,
            engine.score(weakOutfit).total
        )
    }

    func testBandsMatchTheDocumentedThresholds() {
        let engine = OutfitEngine()
        XCTAssertEqual(engine.score(strongOutfit).band, .strong)
        XCTAssertEqual(engine.score(weakOutfit).band, .different)
        XCTAssertEqual(MatchBand.band(for: 0.80), .strong)
        XCTAssertEqual(MatchBand.band(for: 0.79), .good)
        XCTAssertEqual(MatchBand.band(for: 0.65), .good)
        XCTAssertEqual(MatchBand.band(for: 0.50), .worthTrying)
        XCTAssertEqual(MatchBand.band(for: 0.49), .different)
    }

    func testScoreStaysInRangeAcrossTheWholeCandidateSet() {
        let engine = OutfitEngine()
        for candidate in engine.generator.candidates(from: Fixture.largeWardrobe()) {
            let breakdown = engine.score(candidate.items)
            XCTAssertGreaterThanOrEqual(breakdown.total, 0)
            XCTAssertLessThanOrEqual(breakdown.total, 1)
            XCTAssertEqual(breakdown.total, breakdown.ruleTotal, accuracy: accuracy)
            XCTAssertNil(breakdown.compatibilitySignal)
        }
    }

    func testWeightsSumToOne() {
        let configuration = OutfitEngineConfiguration.default
        let sum = configuration.colorWeight
            + configuration.seasonWeight
            + configuration.completenessWeight
            + configuration.preferenceWeight
        XCTAssertEqual(sum, 1.0, accuracy: accuracy)
    }

    func testShoesImproveCompleteness() {
        let engine = OutfitEngine()
        let bare = [Fixture.garment(1, .top, .white), Fixture.garment(2, .bottom, .gray)]
        let shod = bare + [Fixture.garment(3, .shoes, .black)]
        XCTAssertGreaterThan(engine.score(shod).completeness, engine.score(bare).completeness)
    }

    func testRankingIsDeterministicAndDiversified() {
        let engine = OutfitEngine()
        let wardrobe = Fixture.smallWardrobe()
        let first = engine.rankedSuggestions(from: wardrobe, limit: 3).map(\.signature)
        let second = engine.rankedSuggestions(from: wardrobe, limit: 3).map(\.signature)
        XCTAssertEqual(first, second)
        XCTAssertEqual(Set(first).count, first.count)

        let bases = engine.rankedSuggestions(from: wardrobe, limit: 3).map(\.candidate.baseSignature)
        XCTAssertEqual(Set(bases).count, bases.count, "Each suggestion should use a different base")
    }

    func testRankedSuggestionsRespectTheLimit() {
        let engine = OutfitEngine()
        XCTAssertEqual(engine.rankedSuggestions(from: Fixture.largeWardrobe(), limit: 3).count, 3)
        XCTAssertTrue(engine.rankedSuggestions(from: Fixture.smallWardrobe(), limit: 0).isEmpty)
    }

    func testExclusionMovesFurtherDownTheRanking() {
        let engine = OutfitEngine()
        let wardrobe = Fixture.smallWardrobe()
        let firstPass = engine.rankedSuggestions(from: wardrobe, limit: 3)
        let excluded = Set(firstPass.map(\.signature))
        let secondPass = engine.rankedSuggestions(from: wardrobe, limit: 3, excluding: excluded)
        XCTAssertTrue(secondPass.allSatisfy { !excluded.contains($0.signature) })
    }

    func testEveryRankedSuggestionIsValid() {
        let engine = OutfitEngine()
        for suggestion in engine.rankedSuggestions(from: Fixture.largeWardrobe(), limit: 10) {
            XCTAssertTrue(OutfitValidator.isValid(suggestion.items))
        }
    }

    // MARK: - The compatibility seam

    func testCompatibilitySignalIsCapped() {
        let engine = OutfitEngine()
        let ruleOnly = engine.score(weakOutfit)
        let boosted = engine.score(weakOutfit, compatibilitySignal: 1.0)
        let suppressed = engine.score(weakOutfit, compatibilitySignal: 0.0)

        XCTAssertGreaterThan(boosted.total, ruleOnly.total)
        XCTAssertLessThan(suppressed.total, ruleOnly.total)

        let cap = OutfitEngineConfiguration.maximumAllowedCompatibilitySignalWeight
        XCTAssertLessThanOrEqual(abs(boosted.total - ruleOnly.total), cap + accuracy)
        XCTAssertLessThanOrEqual(abs(suppressed.total - ruleOnly.total), cap + accuracy)
        XCTAssertEqual(boosted.ruleTotal, ruleOnly.ruleTotal, accuracy: accuracy)
    }

    func testConfiguredSignalWeightCannotExceedTheCeiling() {
        var configuration = OutfitEngineConfiguration.default
        configuration.compatibilitySignalWeight = 0.9
        XCTAssertEqual(
            configuration.effectiveCompatibilitySignalWeight,
            OutfitEngineConfiguration.maximumAllowedCompatibilitySignalWeight,
            accuracy: accuracy
        )

        configuration.compatibilitySignalWeight = -1
        XCTAssertEqual(configuration.effectiveCompatibilitySignalWeight, 0, accuracy: accuracy)
    }

    func testOutOfRangeSignalIsClamped() {
        let engine = OutfitEngine()
        let high = engine.score(weakOutfit, compatibilitySignal: 42)
        let low = engine.score(weakOutfit, compatibilitySignal: -42)
        XCTAssertEqual(high.compatibilitySignal ?? -1, 1.0, accuracy: accuracy)
        XCTAssertEqual(low.compatibilitySignal ?? -1, 0.0, accuracy: accuracy)
        XCTAssertGreaterThanOrEqual(high.total, 0)
        XCTAssertLessThanOrEqual(high.total, 1)
    }

    func testDisabledProviderIsNeverConsulted() async {
        let engine = OutfitEngine(compatibilityProvider: DisabledCompatibilityProvider())
        let wardrobe = Fixture.smallWardrobe()
        let asyncResult = await engine.suggestions(from: wardrobe, limit: 3)
        let ruleResult = engine.rankedSuggestions(from: wardrobe, limit: 3)
        XCTAssertEqual(asyncResult.map(\.signature), ruleResult.map(\.signature))
        XCTAssertTrue(asyncResult.allSatisfy { $0.breakdown.compatibilitySignal == nil })
    }

    func testProviderReturningNilLeavesRuleScoresStanding() async {
        let engine = OutfitEngine(compatibilityProvider: ConstantCompatibilityProvider(value: nil))
        let result = await engine.suggestions(from: Fixture.smallWardrobe(), limit: 3)
        XCTAssertTrue(result.allSatisfy { $0.breakdown.compatibilitySignal == nil })
    }

    func testFailingProviderDoesNotBreakSuggestions() async {
        let engine = OutfitEngine(compatibilityProvider: ThrowingCompatibilityProvider())
        let result = await engine.suggestions(from: Fixture.smallWardrobe(), limit: 3)
        XCTAssertEqual(result.count, 3)
        XCTAssertTrue(result.allSatisfy { OutfitValidator.isValid($0.items) })
        XCTAssertTrue(result.allSatisfy { $0.breakdown.compatibilitySignal == nil })
    }

    func testProviderCannotIntroduceAnInvalidOutfit() async {
        let engine = OutfitEngine(compatibilityProvider: ConstantCompatibilityProvider(value: 1.0))
        let result = await engine.suggestions(from: Fixture.largeWardrobe(), limit: 5)
        XCTAssertFalse(result.isEmpty)
        for suggestion in result {
            XCTAssertTrue(OutfitValidator.isValid(suggestion.items))
        }
    }

    func testSummaryNeverContainsANumber() {
        let engine = OutfitEngine()
        for candidate in engine.generator.candidates(from: Fixture.smallWardrobe()) {
            let summary = engine.score(candidate.items).summary
            XCTAssertFalse(
                summary.contains(where: \.isNumber),
                "Summaries must not imply a measured quantity: \(summary)"
            )
        }
    }

    func testWardrobeReadiness() {
        XCTAssertTrue(WardrobeReadiness.evaluate(Fixture.smallWardrobe()).canSuggest)
        XCTAssertTrue(WardrobeReadiness.evaluate([Fixture.garment(1, .dress)]).canSuggest)

        let missingBottom = WardrobeReadiness.evaluate([Fixture.garment(1, .top)])
        XCTAssertFalse(missingBottom.canSuggest)
        XCTAssertEqual(missingBottom.missing, [.bottom])
        XCTAssertFalse(missingBottom.explanation.isEmpty)

        let empty = WardrobeReadiness.evaluate([])
        XCTAssertFalse(empty.canSuggest)
        XCTAssertEqual(empty.missing, [.top, .bottom])
    }

    func testFirstLookNextStepMatchesWardrobeReadiness() {
        func nextStep(_ categories: [GarmentCategory]) -> WardrobeReadiness.NextStep? {
            let wardrobe = categories.enumerated().map { index, category in
                Fixture.garment(index + 1, category)
            }
            return WardrobeReadiness.evaluate(wardrobe).nextStep
        }

        XCTAssertEqual(nextStep([])?.actionTitle, "Add a garment")
        XCTAssertEqual(nextStep([.top])?.message, "Add a bottom to build your first look.")
        XCTAssertEqual(nextStep([.top])?.actionTitle, "Add a bottom")
        XCTAssertEqual(nextStep([.bottom])?.message, "Add a top to build your first look.")
        XCTAssertEqual(nextStep([.bottom])?.actionTitle, "Add a top")
        XCTAssertEqual(nextStep([.shoes])?.actionTitle, "Add a garment")
        XCTAssertEqual(nextStep([.outerwear, .accessory])?.actionTitle, "Add a garment")
        XCTAssertEqual(
            nextStep([.shoes])?.message,
            "Add a top and a bottom, or a dress, to build your first look."
        )
        XCTAssertNil(nextStep([.dress]))
        XCTAssertNil(nextStep([.top, .bottom]))
        XCTAssertNil(nextStep([.top, .bottom, .shoes]))
    }
}
