import Foundation
import XCTest
@testable import RIG

/// The bulk-import review queue.
///
/// Everything worth asserting about bulk import lives here rather than in the
/// view: ordering, what advances the cursor, that one bad photograph cannot
/// take the batch down with it, and — the one that protects the user's disk —
/// exactly which identifiers must be swept when the sheet closes.
final class BulkImportQueueTests: XCTestCase {
    private func result(_ id: UUID, isolated: Bool = false) -> GarmentImportResult {
        GarmentImportResult(
            garmentID: id,
            originalRelativePath: GarmentImagePaths.relativePath(for: id, kind: .original),
            cutoutRelativePath: isolated ? GarmentImagePaths.relativePath(for: id, kind: .cutout) : nil,
            thumbnailRelativePath: GarmentImagePaths.relativePath(for: id, kind: .thumbnail),
            isBackgroundRemoved: isolated,
            backgroundRemovalMessage: isolated ? nil : "no foreground"
        )
    }

    private func queue(_ count: Int) -> BulkImportQueue {
        BulkImportQueue(garmentIDs: (1...count).map { Fixture.id($0) })
    }

    private func advanceBySaving(_ queue: inout BulkImportQueue) {
        guard let current = queue.current else { return XCTFail("No current item") }
        queue.markReady(result(current.id))
        XCTAssertTrue(queue.markSaved())
    }

    // MARK: - Ordering

    func testQueuePreservesSelectionOrder() {
        let queue = self.queue(3)
        XCTAssertEqual(queue.items.map(\.id), [Fixture.id(1), Fixture.id(2), Fixture.id(3)])
        XCTAssertEqual(queue.items.map(\.position), [0, 1, 2])
        XCTAssertEqual(queue.current?.id, Fixture.id(1))
    }

    func testReservingCapsAtTheSelectionLimit() {
        let overrun = BulkImportQueue.reserving(BulkImportQueue.maximumSelectionCount + 7)
        XCTAssertEqual(overrun.count, BulkImportQueue.maximumSelectionCount)
        XCTAssertEqual(Set(overrun.items.map(\.id)).count, BulkImportQueue.maximumSelectionCount)
        XCTAssertTrue(BulkImportQueue.reserving(-3).isEmpty)
    }

    func testEmptyQueueIsImmediatelyComplete() {
        let queue = BulkImportQueue()
        XCTAssertTrue(queue.isComplete)
        XCTAssertNil(queue.current)
        XCTAssertEqual(queue.progressLabel, "0 of 0")
        XCTAssertFalse(queue.canGoBack)
    }

    // MARK: - Advancing

    func testProgressLabelTracksTheCursor() {
        var queue = self.queue(3)
        XCTAssertEqual(queue.progressLabel, "1 of 3")
        advanceBySaving(&queue)
        XCTAssertEqual(queue.progressLabel, "2 of 3")
        queue.skip()
        advanceBySaving(&queue)
        XCTAssertEqual(queue.progressLabel, "3 of 3")
        XCTAssertTrue(queue.isComplete)
    }

    func testSavingAdvancesAndRecordsTheGarment() {
        var queue = self.queue(2)
        advanceBySaving(&queue)

        XCTAssertEqual(queue.savedGarmentIDs, [Fixture.id(1)])
        XCTAssertEqual(queue.savedCount, 1)
        XCTAssertEqual(queue.current?.id, Fixture.id(2))
        XCTAssertFalse(queue.isComplete)
    }

    func testAnUnreviewedItemCannotBeSaved() {
        var queue = self.queue(2)
        XCTAssertFalse(queue.markSaved())
        XCTAssertEqual(queue.current?.id, Fixture.id(1))
        XCTAssertTrue(queue.savedGarmentIDs.isEmpty)
    }

    func testSkipAdvancesWithoutSaving() {
        var queue = self.queue(2)
        queue.skip()

        XCTAssertEqual(queue.skippedCount, 1)
        XCTAssertTrue(queue.savedGarmentIDs.isEmpty)
        XCTAssertEqual(queue.current?.id, Fixture.id(2))
    }

    func testQueueIsCompleteOnlyAfterTheLastItemIsResolved() {
        var queue = self.queue(2)
        queue.skip()
        XCTAssertFalse(queue.isComplete)
        queue.skip()
        XCTAssertTrue(queue.isComplete)
        XCTAssertNil(queue.current)
    }

    // MARK: - Failure isolation

    func testAFailedItemHoldsTheCursorAndSparesTheRest() {
        var queue = self.queue(3)
        queue.markFailed("unreadable")

        XCTAssertEqual(queue.current?.id, Fixture.id(1))
        XCTAssertEqual(queue.current?.failureMessage, "unreadable")
        XCTAssertEqual(queue.failedCount, 1)
        XCTAssertEqual(queue.items.dropFirst().map(\.status), [.pending, .pending])

        queue.skip()
        advanceBySaving(&queue)
        XCTAssertEqual(queue.savedGarmentIDs, [Fixture.id(2)])
        XCTAssertEqual(queue.current?.id, Fixture.id(3))
    }

    func testRetryReturnsAFailedItemToPendingInPlace() {
        var queue = self.queue(2)
        queue.markFailed("unreadable")
        queue.retry()

        XCTAssertEqual(queue.current?.id, Fixture.id(1))
        XCTAssertEqual(queue.current?.status, .pending)
        XCTAssertEqual(queue.failedCount, 0)
    }

    func testRetryDoesNothingToAReviewedItem() {
        var queue = self.queue(2)
        let ready = result(Fixture.id(1))
        queue.markReady(ready)
        queue.retry()

        XCTAssertEqual(queue.current?.importResult, ready)
    }

    // MARK: - Going back

    func testBackIsRefusedOntoASavedGarment() {
        var queue = self.queue(2)
        advanceBySaving(&queue)

        XCTAssertFalse(queue.canGoBack)
        queue.goBack()
        XCTAssertEqual(queue.current?.id, Fixture.id(2))
        XCTAssertEqual(queue.savedGarmentIDs, [Fixture.id(1)])
    }

    func testBackOntoASkippedItemMakesItPendingAgain() {
        var queue = self.queue(2)
        queue.skip()
        XCTAssertTrue(queue.canGoBack)

        queue.goBack()
        XCTAssertEqual(queue.current?.id, Fixture.id(1))
        XCTAssertEqual(queue.current?.status, .pending)
        XCTAssertEqual(queue.skippedCount, 0)
    }

    // MARK: - Cancellation

    func testEverythingUnsavedIsSweptAndSavedGarmentsAreNot() {
        var queue = self.queue(4)
        advanceBySaving(&queue)          // 1 saved
        queue.skip()                      // 2 skipped
        queue.markReady(result(Fixture.id(3)))  // 3 reviewed, never confirmed

        let sweep = queue.garmentIDsPendingCleanup
        XCTAssertFalse(sweep.contains(Fixture.id(1)))
        XCTAssertEqual(sweep, [Fixture.id(2), Fixture.id(3), Fixture.id(4)])
    }

    func testCancellingBeforeAnySaveSweepsTheWholeSelection() {
        let queue = self.queue(3)
        XCTAssertEqual(queue.garmentIDsPendingCleanup.count, 3)
        XCTAssertTrue(queue.savedGarmentIDs.isEmpty)
    }

    func testEachItemOwnsItsOwnGarmentDirectory() {
        let queue = self.queue(3)
        for item in queue.items {
            let path = GarmentImagePaths.relativePath(for: item.id, kind: .original)
            XCTAssertEqual(GarmentImagePaths.garmentID(fromRelativePath: path), item.id)
        }
    }
}
