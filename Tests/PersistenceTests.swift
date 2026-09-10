import SwiftData
import XCTest
@testable import RIG

/// SwiftData round trips, run against an in-memory container so the user's
/// store is never involved.
@MainActor
final class PersistenceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        try super.setUpWithError()
        container = try RIGModelContainer.makeInMemoryContainer()
        context = ModelContext(container)
    }

    override func tearDownWithError() throws {
        context = nil
        container = nil
        try super.tearDownWithError()
    }

    private func makeItem(_ index: Int, _ category: GarmentCategory, _ color: ColorFamily = .black) -> ClothingItem {
        let item = ClothingItem(
            id: Fixture.id(index),
            displayName: "\(category.rawValue)-\(index)",
            category: category,
            primaryColor: color
        )
        context.insert(item)
        return item
    }

    func testGarmentRoundTrips() throws {
        let item = makeItem(1, .top, .navy)
        item.seasons = [.autumn, .winter]
        item.isFavorite = true
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<ClothingItem>())
        XCTAssertEqual(fetched.count, 1)
        let stored = try XCTUnwrap(fetched.first)
        XCTAssertEqual(stored.category, .top)
        XCTAssertEqual(stored.primaryColor, .navy)
        XCTAssertEqual(stored.seasons, [.autumn, .winter])
        XCTAssertTrue(stored.isFavorite)
    }

    func testUnknownRawValuesDegradeSafely() throws {
        let item = makeItem(1, .top)
        item.categoryRaw = "spacesuit"
        item.primaryColorRaw = "chartreuse"
        try context.save()

        XCTAssertEqual(item.category, .accessory, "An unknown category must not be able to act as a base")
        XCTAssertEqual(item.primaryColor, .multicolor, "An unknown colour must land on the non-confident family")
    }

    func testSnapshotMirrorsTheStoredGarment() {
        let item = makeItem(2, .bottom, .olive)
        item.seasons = [.summer]
        item.isFavorite = true

        let snapshot = item.snapshot
        XCTAssertEqual(snapshot.id, item.id)
        XCTAssertEqual(snapshot.category, .bottom)
        XCTAssertEqual(snapshot.colorFamily, .olive)
        XCTAssertEqual(snapshot.seasons, [.summer])
        XCTAssertTrue(snapshot.isFavorite)
    }

    func testEmptySeasonMaskReadsBackAsAllYear() {
        let item = makeItem(3, .top)
        item.seasonMask = 0
        XCTAssertTrue(item.seasons.isAllSeason)
        XCTAssertTrue(item.snapshot.seasons.isAllSeason)
    }

    func testPreferredImagePathFallsBackToTheOriginal() {
        let item = makeItem(4, .top)
        XCTAssertNil(item.preferredImageRelativePath)

        item.originalImageRelativePath = "Garments/A/original.jpg"
        XCTAssertEqual(item.preferredImageRelativePath, "Garments/A/original.jpg")

        item.cutoutImageRelativePath = "Garments/A/cutout.png"
        XCTAssertEqual(item.preferredImageRelativePath, "Garments/A/cutout.png")
        XCTAssertEqual(item.relativeImagePaths.count, 2)
    }

    func testSavedOutfitRecordsAnOrderIndependentSignature() throws {
        let top = makeItem(1, .top)
        let bottom = makeItem(2, .bottom)

        let first = SavedOutfit(name: "A", source: .manual, items: [top, bottom])
        let second = SavedOutfit(name: "B", source: .suggestion, items: [bottom, top])
        context.insert(first)
        context.insert(second)
        try context.save()

        XCTAssertEqual(first.signature, second.signature)
        XCTAssertEqual(first.source, .manual)
        XCTAssertEqual(second.source, .suggestion)
        XCTAssertFalse(first.hasMissingGarments)
    }

    func testDisplayOrderIsByCategoryNotInsertionOrder() throws {
        let shoes = makeItem(3, .shoes)
        let top = makeItem(1, .top)
        let bottom = makeItem(2, .bottom)
        let outfit = SavedOutfit(name: "A", source: .manual, items: [shoes, bottom, top])
        context.insert(outfit)
        try context.save()

        XCTAssertEqual(
            outfit.itemsInDisplayOrder.map(\.category),
            [.top, .bottom, .shoes]
        )
    }

    func testDeletingAGarmentMarksItsLooksIncomplete() throws {
        let top = makeItem(1, .top)
        let bottom = makeItem(2, .bottom)
        let outfit = SavedOutfit(name: "A", source: .manual, items: [top, bottom])
        context.insert(outfit)
        try context.save()

        context.delete(bottom)
        try context.save()

        XCTAssertTrue(outfit.hasMissingGarments)
        XCTAssertEqual(outfit.items.count, 1)
    }

    func testDeletingALookNeverDeletesItsGarments() throws {
        let top = makeItem(1, .top)
        let bottom = makeItem(2, .bottom)
        let outfit = SavedOutfit(name: "A", source: .manual, items: [top, bottom])
        context.insert(outfit)
        try context.save()

        context.delete(outfit)
        try context.save()

        let remaining = try context.fetch(FetchDescriptor<ClothingItem>())
        XCTAssertEqual(remaining.count, 2, "Both relationships are nullify; neither side may cascade")
        XCTAssertTrue(try context.fetch(FetchDescriptor<SavedOutfit>()).isEmpty)
    }

    func testAGarmentCanBelongToSeveralLooks() throws {
        let top = makeItem(1, .top)
        let bottomA = makeItem(2, .bottom)
        let bottomB = makeItem(3, .bottom)

        let first = SavedOutfit(name: "A", source: .manual, items: [top, bottomA])
        let second = SavedOutfit(name: "B", source: .manual, items: [top, bottomB])
        context.insert(first)
        context.insert(second)
        try context.save()

        XCTAssertEqual(top.outfits.count, 2, "The inverse must populate from the SavedOutfit side")
        XCTAssertEqual(Set(top.outfits.map(\.id)), [first.id, second.id])
        XCTAssertNotEqual(first.signature, second.signature)
    }

    func testDeletingOneLookLeavesTheOtherIntact() throws {
        let top = makeItem(1, .top)
        let bottomA = makeItem(2, .bottom)
        let bottomB = makeItem(3, .bottom)
        let first = SavedOutfit(name: "A", source: .manual, items: [top, bottomA])
        let second = SavedOutfit(name: "B", source: .manual, items: [top, bottomB])
        context.insert(first)
        context.insert(second)
        try context.save()

        context.delete(first)
        try context.save()

        XCTAssertEqual(second.items.count, 2)
        XCTAssertFalse(second.hasMissingGarments)
        XCTAssertEqual(top.outfits.count, 1)
    }

    func testDisplayImagePathPrefersThumbnailThenCutoutThenOriginal() {
        let item = makeItem(6, .top)
        XCTAssertNil(item.displayImageRelativePath)

        item.originalImageRelativePath = "Garments/A/original.jpg"
        XCTAssertEqual(item.displayImageRelativePath, "Garments/A/original.jpg")

        item.cutoutImageRelativePath = "Garments/A/cutout.png"
        XCTAssertEqual(item.displayImageRelativePath, "Garments/A/cutout.png")

        item.thumbnailRelativePath = "Garments/A/thumbnail.png"
        XCTAssertEqual(item.displayImageRelativePath, "Garments/A/thumbnail.png")
    }

    func testFeedbackRoundTripsAndIsQueryableBySignature() throws {
        let signature = OutfitSignature.signature(forGarmentIDs: [Fixture.id(2), Fixture.id(1)])
        context.insert(OutfitFeedback(outfitSignature: signature, rating: .liked))
        try context.save()

        let descriptor = FetchDescriptor<OutfitFeedback>(
            predicate: #Predicate { $0.outfitSignature == signature }
        )
        let stored = try context.fetch(descriptor)
        XCTAssertEqual(stored.count, 1)
        let rating = try XCTUnwrap(stored.first).rating
        XCTAssertEqual(rating, .liked)
    }

    func testFeedbackSignatureIsIndependentOfTheOrderTheOutfitWasBuiltIn() {
        let forward = OutfitSignature.signature(forGarmentIDs: [Fixture.id(1), Fixture.id(2), Fixture.id(3)])
        let shuffled = OutfitSignature.signature(forGarmentIDs: [Fixture.id(3), Fixture.id(1), Fixture.id(2)])
        XCTAssertEqual(forward, shuffled)
    }

    func testUnknownRatingRawValueReadsAsNil() throws {
        let feedback = OutfitFeedback(outfitSignature: "abc", rating: .disliked)
        context.insert(feedback)
        feedback.ratingRaw = "shrugged"
        try context.save()
        XCTAssertNil(feedback.rating)
    }

    func testPreviewFixturesAreUsableAndSelfConsistent() {
        let snapshots = PreviewData.sampleSnapshots()
        XCTAssertEqual(Set(snapshots.map(\.id)).count, snapshots.count)
        XCTAssertTrue(WardrobeReadiness.evaluate(snapshots).canSuggest)
        XCTAssertEqual(PreviewData.sampleItems().count, snapshots.count)
    }
}
