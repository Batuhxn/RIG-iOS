import SwiftData
import XCTest
@testable import RIG

/// Codex v0.4 review, P2: the backfill saved and rolled back the shared context, so it could
/// commit, or discard, another screen's unrelated pending changes.
@MainActor
final class WardrobeIdentityBackfillTests: XCTestCase {
    func testBackfillStoresIdentitiesWithoutCommittingOtherPendingChanges() throws {
        let container = try RIGModelContainer.makeInMemoryContainer()
        let shared = ModelContext(container)
        let existing = ClothingItem(id: Fixture.id(1), displayName: "Shirt", category: .top, primaryColor: .white)
        shared.insert(existing)
        try shared.save()

        // Another screen's edits, not yet saved.
        let pending = ClothingItem(id: Fixture.id(2), displayName: "Unsaved", category: .bottom, primaryColor: .black)
        shared.insert(pending)
        existing.displayName = "Renamed but unsaved"

        let identity = try XCTUnwrap(GarmentVisualIdentity(modelID: "m1", vector: [1, 0]))
        WardrobeIdentityBackfill.store([existing.id: identity], on: [existing], in: shared)

        let fresh = ModelContext(container)
        let stored = try fresh.fetch(FetchDescriptor<ClothingItem>())
        XCTAssertEqual(stored.map(\.id), [existing.id], "the unsaved insert was not committed by the backfill")
        XCTAssertEqual(stored.first?.visualIdentity, identity, "the identity itself was stored")
        XCTAssertEqual(stored.first?.displayName, "Shirt", "the unsaved rename was not committed either")
        XCTAssertTrue(shared.hasChanges, "the other screen's edits are still pending, not rolled back")
    }

    /// Codex follow-up: the screens hold objects from the container's main context. After an
    /// isolated backfill, that already-loaded object must see the identity, and a later save
    /// of an unrelated edit through the main context must not erase it.
    func testMainContextSeesTheBackfilledIdentityAndKeepsItAfterItsOwnSave() throws {
        let container = try RIGModelContainer.makeInMemoryContainer()
        let main = container.mainContext
        let item = ClothingItem(id: Fixture.id(3), displayName: "Jeans", category: .bottom, primaryColor: .navy)
        main.insert(item)
        try main.save()
        XCTAssertNil(item.visualIdentity)

        let identity = try XCTUnwrap(GarmentVisualIdentity(modelID: "m1", vector: [0, 1]))
        WardrobeIdentityBackfill.store([item.id: identity], on: [item], in: main)

        let seen = try main.fetch(FetchDescriptor<ClothingItem>()).first
        XCTAssertEqual(seen?.visualIdentity, identity, "the main context sees the stored identity")

        item.displayName = "Dark jeans"
        try main.save()
        let fresh = try ModelContext(container).fetch(FetchDescriptor<ClothingItem>()).first
        XCTAssertEqual(fresh?.displayName, "Dark jeans")
        XCTAssertEqual(fresh?.visualIdentity, identity, "a later main-context save keeps the identity")
    }

    func testBackfillOfUnknownGarmentsChangesNothing() throws {
        let container = try RIGModelContainer.makeInMemoryContainer()
        let identity = try XCTUnwrap(GarmentVisualIdentity(modelID: "m1", vector: [1, 0]))
        WardrobeIdentityBackfill.store([UUID(): identity], in: container)
        XCTAssertTrue(try ModelContext(container).fetch(FetchDescriptor<ClothingItem>()).isEmpty)
    }
}
