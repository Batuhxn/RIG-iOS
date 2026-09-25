import SwiftData
import XCTest
@testable import RIG

@MainActor
final class GarmentMutationTests: XCTestCase {
    private enum SimulatedFailure: Error {
        case save
        case cleanup
    }

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

    private func makeSavedGarment() throws -> ClothingItem {
        let item = ClothingItem(
            displayName: "Coat",
            subtype: "Trench",
            category: .outerwear,
            primaryColor: .beige,
            seasons: [.spring, .autumn],
            notes: "Original",
            originalImageRelativePath: "Garments/original.jpg"
        )
        context.insert(item)
        try context.save()
        return item
    }

    private func changedFields() -> GarmentMetadataFields {
        var fields = GarmentMetadataFields()
        fields.displayName = "Blue jacket"
        fields.subtype = "Denim"
        fields.category = .top
        fields.colorFamily = .blue
        fields.seasons = [.summer]
        fields.isFavorite = true
        fields.notes = "Changed"
        return fields
    }

    func testEditSuccessKeepsAllChangedValues() throws {
        let item = try makeSavedGarment()
        let changed = try GarmentMutations.edit(item, fields: changedFields(), in: context, save: context.save)

        XCTAssertTrue(changed)
        XCTAssertEqual(item.displayName, "Blue jacket")
        XCTAssertEqual(item.subtype, "Denim")
        XCTAssertEqual(item.category, .top)
        XCTAssertEqual(item.primaryColor, .blue)
        XCTAssertEqual(item.seasons, [.summer])
        XCTAssertTrue(item.isFavorite)
        XCTAssertEqual(item.notes, "Changed")
        let stored = try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<ClothingItem>()).first)
        XCTAssertEqual(stored.displayName, "Blue jacket")
        XCTAssertEqual(stored.category, .top)
        XCTAssertEqual(stored.primaryColor, .blue)
    }

    func testEditFailureRestoresEveryEditableValueAndTimestamp() throws {
        let item = try makeSavedGarment()
        let originalUpdate = item.updatedAt
        let originalID = item.id

        XCTAssertThrowsError(try GarmentMutations.edit(item, fields: changedFields(), in: context) {
            throw SimulatedFailure.save
        })

        XCTAssertEqual(item.id, originalID)
        XCTAssertEqual(item.displayName, "Coat")
        XCTAssertEqual(item.subtype, "Trench")
        XCTAssertEqual(item.category, .outerwear)
        XCTAssertEqual(item.primaryColor, .beige)
        XCTAssertEqual(item.seasons, [.spring, .autumn])
        XCTAssertFalse(item.isFavorite)
        XCTAssertEqual(item.notes, "Original")
        XCTAssertEqual(item.updatedAt, originalUpdate)
        XCTAssertEqual(item.originalImageRelativePath, "Garments/original.jpg")
        XCTAssertFalse(context.hasChanges)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ClothingItem>()).count, 1)
    }

    func testFavoriteSuccessPersistsNewValue() throws {
        let item = try makeSavedGarment()
        try GarmentMutations.toggleFavorite(item, in: context, save: context.save)

        XCTAssertTrue(item.isFavorite)
        XCTAssertTrue(try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<ClothingItem>()).first).isFavorite)
    }

    func testFavoriteFailureRestoresValueAndTimestamp() throws {
        let item = try makeSavedGarment()
        let originalUpdate = item.updatedAt

        XCTAssertThrowsError(try GarmentMutations.toggleFavorite(item, in: context) {
            throw SimulatedFailure.save
        })

        XCTAssertFalse(item.isFavorite)
        XCTAssertEqual(item.updatedAt, originalUpdate)
        XCTAssertFalse(context.hasChanges)
        XCTAssertFalse(try XCTUnwrap(context.fetch(FetchDescriptor<ClothingItem>()).first).isFavorite)
    }

    func testDeleteSuccessRemovesRowAfterSavingAndLeavesLook() throws {
        let item = try makeSavedGarment()
        let look = SavedOutfit(name: "Saved look", source: .manual, items: [item])
        context.insert(look)
        try context.save()
        let id = item.id
        var cleanedID: UUID?
        var rowMissingAtCleanup = false

        try GarmentMutations.delete(item, in: context, save: context.save) { id in
            rowMissingAtCleanup = try context.fetch(FetchDescriptor<ClothingItem>()).isEmpty
            cleanedID = id
        }

        XCTAssertEqual(cleanedID, id)
        XCTAssertTrue(rowMissingAtCleanup)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ClothingItem>()).isEmpty)
        XCTAssertEqual(try context.fetch(FetchDescriptor<SavedOutfit>()).count, 1)
        XCTAssertTrue(look.hasMissingGarments)
    }

    func testDeleteFailureKeepsGarmentAndDoesNotTouchImages() throws {
        let item = try makeSavedGarment()
        let look = SavedOutfit(name: "Saved look", source: .manual, items: [item])
        context.insert(look)
        try context.save()
        var cleanupCalled = false

        XCTAssertThrowsError(try GarmentMutations.delete(item, in: context, save: {
            throw SimulatedFailure.save
        }, removeImages: { _ in
            cleanupCalled = true
        }))

        XCTAssertFalse(cleanupCalled)
        XCTAssertFalse(context.hasChanges)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ClothingItem>()).map(\.id), [item.id])
        XCTAssertFalse(look.hasMissingGarments)
        XCTAssertEqual(look.items.count, 1)
    }

    func testCleanupFailureDoesNotUndoCommittedDeletion() throws {
        let item = try makeSavedGarment()

        try GarmentMutations.delete(item, in: context, save: context.save) { _ in
            throw SimulatedFailure.cleanup
        }

        XCTAssertTrue(try context.fetch(FetchDescriptor<ClothingItem>()).isEmpty)
    }
}
