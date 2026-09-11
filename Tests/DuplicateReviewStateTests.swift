import XCTest
@testable import RIG

/// `DuplicateReviewState` is the pure state the comparison sheet is a thin
/// presentation over — cycling logic tested directly, no SwiftUI needed.
final class DuplicateReviewStateTests: XCTestCase {
    private func match(_ index: Int, band: SimilarityBand = .verySimilar) -> WardrobeSimilarityMatch {
        WardrobeSimilarityMatch(garmentID: Fixture.id(index), band: band, distance: Float(index) * 0.1)
    }

    func testInitCapsToTheThreeStrongestMatchesEvenWhenMoreAreGiven() {
        let matches = (1...5).map { match($0) }
        let state = DuplicateReviewState(matches: matches)

        XCTAssertEqual(state.matches.count, 3)
        XCTAssertEqual(state.matches.map(\.garmentID), matches.prefix(3).map(\.garmentID))
    }

    func testCurrentReturnsTheFirstMatchInitially() {
        let state = DuplicateReviewState(matches: [match(1), match(2)])
        XCTAssertEqual(state.current?.garmentID, Fixture.id(1))
    }

    func testShowAnotherCyclesToTheNextMatchInOrder() {
        var state = DuplicateReviewState(matches: [match(1), match(2), match(3)])
        state.showAnother()
        XCTAssertEqual(state.current?.garmentID, Fixture.id(2))
        state.showAnother()
        XCTAssertEqual(state.current?.garmentID, Fixture.id(3))
    }

    func testHasAnotherIsFalseOnTheLastMatch() {
        var state = DuplicateReviewState(matches: [match(1), match(2)])
        XCTAssertTrue(state.hasAnother)
        state.showAnother()
        XCTAssertFalse(state.hasAnother)
    }

    func testIsExhaustedIsTrueForAnEmptyInput() {
        let state = DuplicateReviewState(matches: [])
        XCTAssertTrue(state.isExhausted)
        XCTAssertNil(state.current)
    }

    func testIsExhaustedBecomesTrueAfterCyclingPastTheLastMatch() {
        var state = DuplicateReviewState(matches: [match(1)])
        XCTAssertFalse(state.isExhausted)
        state.showAnother()
        XCTAssertTrue(state.isExhausted)
    }

    func testShowAnotherPastTheEndDoesNotCrashAndCurrentBecomesNil() {
        var state = DuplicateReviewState(matches: [match(1)])
        state.showAnother()
        state.showAnother()
        state.showAnother()
        XCTAssertNil(state.current)
        XCTAssertTrue(state.isExhausted)
    }
}
