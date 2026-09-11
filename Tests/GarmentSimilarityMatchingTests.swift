import XCTest
@testable import RIG

/// Pure logic only: banding, ranking and candidate-set construction. None of
/// this touches `VNGenerateImageFeaturePrintRequest` — `VisionFeaturePrintSimilarityMatcher`
/// itself is unverified (it has never run), the same caveat class as
/// `VisionBackgroundRemover`, but everything it delegates to for ordering and
/// thresholds lives here and is fully testable without Vision.
final class GarmentSimilarityMatchingTests: XCTestCase {
    // MARK: - SimilarityThresholds.band(forDistance:)

    func testDistanceAtOrBelowVerySimilarThresholdBandsAsVerySimilar() {
        let thresholds = SimilarityThresholds.conservativeDefault
        XCTAssertEqual(thresholds.band(forDistance: 0), .verySimilar)
        XCTAssertEqual(thresholds.band(forDistance: thresholds.verySimilar), .verySimilar)
    }

    func testDistanceJustAboveVerySimilarBandsAsSimilar() {
        let thresholds = SimilarityThresholds.conservativeDefault
        let justAbove = thresholds.verySimilar.nextUp
        XCTAssertEqual(thresholds.band(forDistance: justAbove), .similar)
    }

    func testDistanceAtSimilarThresholdBandsAsSimilar() {
        let thresholds = SimilarityThresholds.conservativeDefault
        XCTAssertEqual(thresholds.band(forDistance: thresholds.similar), .similar)
    }

    func testDistanceAtPossibleMatchThresholdBandsAsPossibleMatch() {
        let thresholds = SimilarityThresholds.conservativeDefault
        let justAboveSimilar = thresholds.similar.nextUp
        XCTAssertEqual(thresholds.band(forDistance: justAboveSimilar), .possibleMatch)
        XCTAssertEqual(thresholds.band(forDistance: thresholds.possibleMatch), .possibleMatch)
    }

    func testDistanceJustAbovePossibleMatchThresholdSurfacesNothing() {
        let thresholds = SimilarityThresholds.conservativeDefault
        let justAbove = thresholds.possibleMatch.nextUp
        XCTAssertNil(thresholds.band(forDistance: justAbove))
    }

    func testNegativeOrNonFiniteDistancesSurfaceNothing() {
        let thresholds = SimilarityThresholds.conservativeDefault
        XCTAssertNil(thresholds.band(forDistance: -0.1))
        XCTAssertNil(thresholds.band(forDistance: .nan))
        XCTAssertNil(thresholds.band(forDistance: .infinity))
    }

    // MARK: - WardrobeSimilarityRanking.rank

    func testRankOrdersMostSimilarFirst() {
        let a = Fixture.id(1)
        let b = Fixture.id(2)
        let c = Fixture.id(3)
        let ranked = WardrobeSimilarityRanking.rank(distances: [
            (garmentID: a, distance: 0.6),
            (garmentID: b, distance: 0.1),
            (garmentID: c, distance: 0.35),
        ])

        XCTAssertEqual(ranked.map(\.garmentID), [b, c, a])
        XCTAssertEqual(ranked.map(\.band), [.verySimilar, .similar, .possibleMatch])
    }

    func testRankDropsDistancesThatDoNotClearTheWeakestThreshold() {
        let kept = Fixture.id(1)
        let dropped = Fixture.id(2)
        let ranked = WardrobeSimilarityRanking.rank(distances: [
            (garmentID: kept, distance: 0.4),
            (garmentID: dropped, distance: 0.9),
        ])

        XCTAssertEqual(ranked.map(\.garmentID), [kept])
    }

    func testRankOfEmptyInputIsEmptyOutput() {
        XCTAssertTrue(WardrobeSimilarityRanking.rank(distances: []).isEmpty)
    }

    func testRankHonoursCustomThresholds() {
        let id = Fixture.id(1)
        let tight = SimilarityThresholds(verySimilar: 0.05, similar: 0.1, possibleMatch: 0.15)
        XCTAssertNil(WardrobeSimilarityRanking.rank(distances: [(id, 0.2)], thresholds: tight).first)
        let ranked = WardrobeSimilarityRanking.rank(distances: [(id, 0.12)], thresholds: tight)
        XCTAssertEqual(ranked.first?.band, .possibleMatch)
    }

    // MARK: - WardrobeSimilarityQuery.candidates

    func testCandidatesFiltersToTheConfirmedCategoryOnly() {
        let items = [
            WardrobeSimilarityCandidateItem(garmentID: Fixture.id(1), category: .top, imageData: Data([1])),
            WardrobeSimilarityCandidateItem(garmentID: Fixture.id(2), category: .bottom, imageData: Data([2])),
            WardrobeSimilarityCandidateItem(garmentID: Fixture.id(3), category: .top, imageData: Data([3])),
        ]

        let candidates = WardrobeSimilarityQuery.candidates(from: items, category: .top)

        XCTAssertEqual(Set(candidates.map(\.garmentID)), Set([Fixture.id(1), Fixture.id(3)]))
    }

    func testCandidatesExcludesTheGivenGarmentIDEvenWhenItsCategoryMatches() {
        let selfID = Fixture.id(1)
        let items = [
            WardrobeSimilarityCandidateItem(garmentID: selfID, category: .top, imageData: Data([1])),
            WardrobeSimilarityCandidateItem(garmentID: Fixture.id(2), category: .top, imageData: Data([2])),
        ]

        let candidates = WardrobeSimilarityQuery.candidates(from: items, category: .top, excluding: selfID)

        XCTAssertEqual(candidates.map(\.garmentID), [Fixture.id(2)])
    }

    func testCandidatesOfAnEmptyWardrobeIsEmpty() {
        XCTAssertTrue(WardrobeSimilarityQuery.candidates(from: [], category: .top).isEmpty)
    }

    // MARK: - PassthroughSimilarityMatcher

    func testPassthroughMatcherAlwaysAnswersNoSuggestion() async {
        let matcher = PassthroughSimilarityMatcher()
        let result = await matcher.rankSimilarItems(to: Data([1]), among: [
            WardrobeSimilarityCandidateItem(garmentID: Fixture.id(1), category: .top, imageData: Data([2])),
        ])
        XCTAssertTrue(result.isEmpty)
    }
}
