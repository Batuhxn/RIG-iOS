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

    func testBackfillOfUnknownGarmentsChangesNothing() throws {
        let container = try RIGModelContainer.makeInMemoryContainer()
        let identity = try XCTUnwrap(GarmentVisualIdentity(modelID: "m1", vector: [1, 0]))
        WardrobeIdentityBackfill.store([UUID(): identity], in: container)
        XCTAssertTrue(try ModelContext(container).fetch(FetchDescriptor<ClothingItem>()).isEmpty)
    }
}
