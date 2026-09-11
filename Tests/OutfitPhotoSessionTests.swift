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

    // MARK: - v0.4 Slice 2: AI-proposed masks

    private func mask(quality: Double? = 0.8) -> SegmentationMaskResult {
        SegmentationMaskResult(cutoutData: Data([0x01]), boundingRegion: .centeredDefault, qualityScore: quality)
    }

    func testProposingAMaskSetsOriginToAIAssisted() {
        var session = OutfitPhotoSession()
        session.beginCandidate(id: Fixture.id(1))
        session.proposeMask(mask())

        XCTAssertEqual(session.active?.origin, .aiAssistedCrop)
        XCTAssertNotNil(session.active?.proposedMask)
    }

    func testClearingAProposedMaskRevertsOriginToManual() {
        var session = OutfitPhotoSession()
        session.beginCandidate(id: Fixture.id(1))
        session.proposeMask(mask())
        session.proposeMask(nil)

        XCTAssertEqual(session.active?.origin, .manualCrop)
        XCTAssertNil(session.active?.proposedMask)
    }

    func testUpdatingRegionClearsAPreviouslyProposedMask() {
        var session = OutfitPhotoSession()
        session.beginCandidate(id: Fixture.id(1))
        session.proposeMask(mask())
        session.updateRegion(NormalizedCropRect(x: 0.1, y: 0.1, width: 0.3, height: 0.3))

        XCTAssertNil(session.active?.proposedMask, "a mask proposed for the old rectangle must not survive a redrawn one")
        XCTAssertEqual(session.active?.origin, .manualCrop)
    }

    func testRecropClearsAProposedMask() {
        var session = OutfitPhotoSession()
        let id = Fixture.id(1)
        session.beginCandidate(id: id)
        session.proposeMask(mask())
        session.markReady(result(id))
        session.recrop()

        XCTAssertNil(session.active?.proposedMask)
        XCTAssertEqual(session.active?.origin, .manualCrop)
    }

    func testProposingNilMaskWithNoActiveCandidateIsANoOp() {
        var session = OutfitPhotoSession()
        session.proposeMask(mask())
        XCTAssertTrue(session.isIdle)
    }

    // MARK: - v0.4 Slice 2: resolving to an existing wardrobe item

    func testMarkLinkedExistingResolvesTheCandidateWithoutCreatingAGarment() {
        var session = OutfitPhotoSession()
        let id = Fixture.id(1)
        session.beginCandidate(id: id)
        session.markReady(result(id))
        let existingID = Fixture.id(99)

        XCTAssertTrue(session.markLinkedExisting(existingID))
        XCTAssertTrue(session.isIdle)
        XCTAssertEqual(session.savedCount, 0)
        XCTAssertEqual(session.linkedCount, 1)
        XCTAssertEqual(session.resolvedCount, 1)
        XCTAssertEqual(session.candidates.first?.linkedGarmentID, existingID)
    }

    func testALinkedCandidatesOwnFilesAreCleanedUpLikeADiscardedOnes() {
        var session = OutfitPhotoSession()
        let id = Fixture.id(1)
        session.beginCandidate(id: id)
        session.markReady(result(id))
        session.markLinkedExisting(Fixture.id(99))

        XCTAssertEqual(
            session.garmentIDsPendingCleanup, [id],
            "a candidate linked to an existing item never became a garment of its own"
        )
    }

    func testAnUnprocessedCandidateCannotBeLinked() {
        var session = OutfitPhotoSession()
        session.beginCandidate(id: Fixture.id(1))

        XCTAssertFalse(session.markLinkedExisting(Fixture.id(99)))
        XCTAssertEqual(session.linkedCount, 0)
        XCTAssertFalse(session.isIdle)
    }

    func testALinkedCandidateCannotBeLinkedTwice() {
        var session = OutfitPhotoSession()
        let id = Fixture.id(1)
        session.beginCandidate(id: id)
        session.markReady(result(id))
        session.markLinkedExisting(Fixture.id(99))

        XCTAssertFalse(session.markLinkedExisting(Fixture.id(100)), "nothing is active to link a second time")
        XCTAssertEqual(session.linkedCount, 1)
    }

    func testALinkedGarmentCannotBeSentBackToCropping() {
        var session = OutfitPhotoSession()
        let id = Fixture.id(1)
        session.beginCandidate(id: id)
        session.markReady(result(id))
        session.markLinkedExisting(Fixture.id(99))
        session.recrop()

        XCTAssertTrue(session.isIdle)
        XCTAssertEqual(session.linkedCount, 1)
    }

    func testResolvedCountCombinesNewAndLinkedGarments() {
        var session = OutfitPhotoSession()
        saveOne(&session, 1)

        let id2 = Fixture.id(2)
        session.beginCandidate(id: id2)
        session.markReady(result(id2))
        session.markLinkedExisting(Fixture.id(50))

        XCTAssertEqual(session.savedCount, 1)
        XCTAssertEqual(session.linkedCount, 1)
        XCTAssertEqual(session.resolvedCount, 2)
    }

    // MARK: - v0.4 Slice 2.1: refinement points

    private func point(_ x: Double, isPositive: Bool = true) -> EdgeSAMGeometry.PromptPoint {
        EdgeSAMGeometry.PromptPoint(x: x, y: 0.5, isPositive: isPositive)
    }

    func testANewCandidateStartsWithNoRefinementPoints() {
        var session = OutfitPhotoSession()
        session.beginCandidate(id: Fixture.id(1))

        XCTAssertTrue(session.active?.refinementPoints.isEmpty ?? false)
    }

    func testSetRefinementPointsAppliesToTheActiveCandidate() {
        var session = OutfitPhotoSession()
        session.beginCandidate(id: Fixture.id(1))
        session.setRefinementPoints([point(0.2), point(0.3, isPositive: false)])

        XCTAssertEqual(session.active?.refinementPoints, [point(0.2), point(0.3, isPositive: false)])
    }

    func testUpdatingRegionClearsRefinementPoints() {
        var session = OutfitPhotoSession()
        session.beginCandidate(id: Fixture.id(1))
        session.setRefinementPoints([point(0.2)])
        session.updateRegion(NormalizedCropRect(x: 0.1, y: 0.1, width: 0.3, height: 0.3))

        XCTAssertTrue(
            session.active?.refinementPoints.isEmpty ?? false,
            "a point placed against the old rectangle must not survive a redrawn one"
        )
    }

    func testRecropClearsRefinementPoints() {
        var session = OutfitPhotoSession()
        let id = Fixture.id(1)
        session.beginCandidate(id: id)
        session.setRefinementPoints([point(0.2)])
        session.markReady(result(id))
        session.recrop()

        XCTAssertTrue(session.active?.refinementPoints.isEmpty ?? false)
    }

    /// The real-device finding this addresses: a second garment from the
    /// same photo must start clean. Storing `refinementPoints` on the
    /// candidate struct itself, not the view, makes this provable by
    /// Swift's value semantics — `beginCandidate` always appends a fresh
    /// `OutfitGarmentCandidate`, which can only start with its own empty
    /// default.
    func testARefinementPointOnOneCandidateDoesNotLeakIntoTheNextCandidate() {
        var session = OutfitPhotoSession()
        let firstID = Fixture.id(1)
        session.beginCandidate(id: firstID)
        session.setRefinementPoints([point(0.2), point(0.4, isPositive: false)])
        session.markReady(result(firstID))
        XCTAssertTrue(session.markSaved())

        session.beginCandidate(id: Fixture.id(2))

        XCTAssertTrue(
            session.active?.refinementPoints.isEmpty ?? false,
            "a fresh candidate must never inherit a previous candidate's refinement points"
        )
        // The first candidate's own accumulated points are untouched by the
        // second candidate existing — nothing here rewrote history.
        XCTAssertEqual(session.candidates.first?.refinementPoints, [point(0.2), point(0.4, isPositive: false)])
    }
}
