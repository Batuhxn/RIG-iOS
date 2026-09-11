import Foundation
import XCTest
@testable import RIG

/// The outfit extraction session.
///
/// What matters here is that one photograph can produce several garments
/// without any of them interfering: a failure is local, a save happens once,
/// and whatever the user abandons leaves nothing behind on disk.
final class OutfitPhotoSessionTests: XCTestCase {
    private func result(_ id: UUID, isolated: Bool = true) -> GarmentImportResult {
        GarmentImportResult(
            garmentID: id,
            originalRelativePath: GarmentImagePaths.relativePath(for: id, kind: .original),
            cutoutRelativePath: isolated ? GarmentImagePaths.relativePath(for: id, kind: .cutout) : nil,
            thumbnailRelativePath: GarmentImagePaths.relativePath(for: id, kind: .thumbnail),
            isBackgroundRemoved: isolated,
            backgroundRemovalMessage: isolated ? nil : "no foreground"
        )
    }

    /// Crop, process and confirm one garment.
    private func saveOne(_ session: inout OutfitPhotoSession, _ index: Int) {
        let id = Fixture.id(index)
        session.beginCandidate(id: id)
        session.markReady(result(id))
        XCTAssertTrue(session.markSaved())
    }

    // MARK: - Lifecycle

    func testANewSessionIsLookingAtTheWholePhoto() {
        let session = OutfitPhotoSession()
        XCTAssertTrue(session.isIdle)
        XCTAssertNil(session.active)
        XCTAssertTrue(session.candidates.isEmpty)
        XCTAssertEqual(session.savedCount, 0)
        XCTAssertTrue(session.garmentIDsPendingCleanup.isEmpty)
    }

    func testBeginningAGarmentOpensOneAtTheDefaultRegion() {
        var session = OutfitPhotoSession()
        let id = session.beginCandidate(id: Fixture.id(1))

        XCTAssertFalse(session.isIdle)
        XCTAssertEqual(session.active?.id, id)
        XCTAssertEqual(session.active?.region, .centeredDefault)
        XCTAssertEqual(session.active?.stage, .drafting)
        XCTAssertEqual(session.active?.origin, .manualCrop)
        XCTAssertNil(session.active?.suggestedCategory)
    }

    func testASecondBeginWhileOneIsOpenDoesNotStackANewCandidate() {
        var session = OutfitPhotoSession()
        let first = session.beginCandidate(id: Fixture.id(1))
        let second = session.beginCandidate(id: Fixture.id(2))

        XCTAssertEqual(first, second)
        XCTAssertEqual(session.candidates.count, 1)
    }

    func testTheRegionIsClampedIntoThePhotograph() {
        var session = OutfitPhotoSession()
        session.beginCandidate(id: Fixture.id(1))
        session.updateRegion(NormalizedCropRect(x: 0.9, y: 0.9, width: 0.5, height: 0.5))

        XCTAssertEqual(
            session.active?.region,
            NormalizedCropRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
        )
    }

    // MARK: - Saving

    func testSavingRecordsTheGarmentAndReturnsToThePhoto() {
        var session = OutfitPhotoSession()
        saveOne(&session, 1)

        XCTAssertTrue(session.isIdle)
        XCTAssertEqual(session.savedCount, 1)
        XCTAssertEqual(session.savedGarmentIDs, [Fixture.id(1)])
    }

    func testAGarmentCannotBeSavedTwice() {
        var session = OutfitPhotoSession()
        saveOne(&session, 1)

        XCTAssertFalse(session.markSaved())
        XCTAssertEqual(session.savedCount, 1)
        XCTAssertEqual(session.candidates.count, 1)
    }

    func testAnUnprocessedGarmentCannotBeSaved() {
        var session = OutfitPhotoSession()
        session.beginCandidate(id: Fixture.id(1))

        XCTAssertFalse(session.markSaved())
        XCTAssertEqual(session.savedCount, 0)
        XCTAssertFalse(session.isIdle)
    }

    func testSeveralGarmentsComeOutOfOnePhotograph() {
        var session = OutfitPhotoSession()
        saveOne(&session, 1)
        saveOne(&session, 2)
        saveOne(&session, 3)

        XCTAssertEqual(session.savedGarmentIDs, [Fixture.id(1), Fixture.id(2), Fixture.id(3)])
        XCTAssertTrue(session.isIdle)
    }

    // MARK: - Re-crop and retry

    func testCroppingAgainSendsAReviewedGarmentBackToItsRectangle() {
        var session = OutfitPhotoSession()
        let id = Fixture.id(1)
        session.beginCandidate(id: id)
        session.markReady(result(id))
        session.recrop()

        XCTAssertEqual(session.active?.id, id)
        XCTAssertEqual(session.active?.stage, .drafting)
        XCTAssertNil(session.active?.importResult)
        XCTAssertEqual(session.candidates.count, 1, "re-cropping reuses the identifier")
    }

    func testCroppingAgainRecoversAFailedGarment() {
        var session = OutfitPhotoSession()
        session.beginCandidate(id: Fixture.id(1))
        session.markFailed("that area could not be cropped")
        session.recrop()

        XCTAssertEqual(session.active?.stage, .drafting)
        XCTAssertEqual(session.failedCount, 0)
    }

    func testASavedGarmentCannotBeSentBackToCropping() {
        var session = OutfitPhotoSession()
        saveOne(&session, 1)
        session.recrop()

        XCTAssertTrue(session.isIdle)
        XCTAssertEqual(session.savedGarmentIDs, [Fixture.id(1)])
    }

    // MARK: - Failure isolation

    func testAFailedGarmentLeavesTheSessionAndItsSavedGarmentsIntact() {
        var session = OutfitPhotoSession()
        saveOne(&session, 1)

        session.beginCandidate(id: Fixture.id(2))
        session.markFailed("that garment could not be processed")

        XCTAssertEqual(session.savedCount, 1)
        XCTAssertEqual(session.failedCount, 1)
        XCTAssertEqual(session.active?.id, Fixture.id(2))

        session.discardActive()
        saveOne(&session, 3)

        XCTAssertEqual(session.savedGarmentIDs, [Fixture.id(1), Fixture.id(3)])
        XCTAssertTrue(session.isIdle)
    }

    // MARK: - Cancellation

    func testDiscardingReturnsToThePhotoAndMarksTheFilesForRemoval() {
        var session = OutfitPhotoSession()
        let id = Fixture.id(1)
        session.beginCandidate(id: id)
        session.markReady(result(id))
        session.discardActive()

        XCTAssertTrue(session.isIdle)
        XCTAssertEqual(session.savedCount, 0)
        XCTAssertEqual(session.garmentIDsPendingCleanup, [id])
    }

    func testOnlySavedGarmentsKeepTheirFiles() {
        var session = OutfitPhotoSession()
        saveOne(&session, 1)

        session.beginCandidate(id: Fixture.id(2))
        session.discardActive()

        session.beginCandidate(id: Fixture.id(3))
        session.markFailed("processing failed")
        session.discardActive()

        let id = Fixture.id(4)
        session.beginCandidate(id: id)
        session.markReady(result(id))

        XCTAssertEqual(
            session.garmentIDsPendingCleanup,
            [Fixture.id(2), Fixture.id(3), Fixture.id(4)]
        )
        XCTAssertFalse(session.garmentIDsPendingCleanup.contains(Fixture.id(1)))
    }

    func testLeavingBeforeSavingAnythingSweepsEverything() {
        var session = OutfitPhotoSession()
        session.beginCandidate(id: Fixture.id(1))

        XCTAssertEqual(session.garmentIDsPendingCleanup, [Fixture.id(1)])
        XCTAssertTrue(session.savedGarmentIDs.isEmpty)
    }

    func testEachCandidateOwnsItsOwnGarmentDirectory() {
        var session = OutfitPhotoSession()
        saveOne(&session, 1)
        saveOne(&session, 2)

        for candidate in session.candidates {
            let path = GarmentImagePaths.relativePath(for: candidate.id, kind: .original)
            XCTAssertEqual(GarmentImagePaths.garmentID(fromRelativePath: path), candidate.id)
        }
    }
}
