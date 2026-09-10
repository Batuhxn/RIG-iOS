import XCTest
@testable import RIG

final class SeasonCoherenceTests: XCTestCase {
    private let accuracy = 1e-9

    func testSharedSeasonScoresTop() {
        XCTAssertEqual(
            SeasonCoherence.score(for: [.all, .all, .all]),
            SeasonCoherence.sharedSeasonScore,
            accuracy: accuracy
        )
        XCTAssertEqual(
            SeasonCoherence.score(for: [[.spring, .summer], [.summer, .autumn]]),
            SeasonCoherence.sharedSeasonScore,
            accuracy: accuracy
        )
    }

    func testFullyDisjointSeasonsHitTheFloor() {
        let score = SeasonCoherence.score(for: [[.summer], [.winter]])
        XCTAssertEqual(score, SeasonCoherence.partialFloor, accuracy: accuracy)
        XCTAssertLessThan(score, SeasonCoherence.sharedSeasonScore)
    }

    func testPartialOverlapLandsBetween() {
        let score = SeasonCoherence.score(for: [[.summer], [.winter], .all])
        XCTAssertGreaterThan(score, SeasonCoherence.partialFloor)
        XCTAssertLessThan(score, SeasonCoherence.sharedSeasonScore)
    }

    func testEmptySeasonSetIsTreatedAsAllYear() {
        XCTAssertEqual(
            SeasonCoherence.score(for: [SeasonSet(), [.winter]]),
            SeasonCoherence.sharedSeasonScore,
            accuracy: accuracy
        )
    }

    func testSingleGarmentCannotConflict() {
        XCTAssertEqual(
            SeasonCoherence.score(for: [[.summer]]),
            SeasonCoherence.insufficientDataScore,
            accuracy: accuracy
        )
    }

    func testScoreStaysInRange() {
        let combinations: [[SeasonSet]] = [
            [.all, .all],
            [[.summer], [.winter]],
            [[.spring], [.autumn], [.winter]],
            [[.summer], [.summer], [.winter], .all]
        ]
        for combination in combinations {
            let score = SeasonCoherence.score(for: combination)
            XCTAssertGreaterThanOrEqual(score, 0)
            XCTAssertLessThanOrEqual(score, 1)
        }
    }

    func testSeasonSetRoundTripsThroughItsMask() {
        let original: SeasonSet = [.spring, .winter]
        let restored = SeasonSet(rawValue: original.rawValue).normalized
        XCTAssertEqual(restored, original)
        XCTAssertEqual(restored.seasons, [.spring, .winter])
        XCTAssertFalse(restored.isAllSeason)
        XCTAssertTrue(SeasonSet.all.isAllSeason)
    }
}
