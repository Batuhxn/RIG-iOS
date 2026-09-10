import Foundation
import SwiftData

/// Fixtures for SwiftUI previews and development only.
///
/// Nothing here is ever inserted into the user's store. `container()` always
/// builds an in-memory container, so a real wardrobe can never acquire a
/// garment nobody owns.
enum PreviewData {
    static func sampleSnapshots() -> [GarmentSnapshot] {
        [
            GarmentSnapshot(id: id(1), category: .top, colorFamily: .white, seasons: .all, displayName: "Oxford shirt", isFavorite: true),
            GarmentSnapshot(id: id(2), category: .top, colorFamily: .navy, seasons: [.autumn, .winter], displayName: "Merino crewneck"),
            GarmentSnapshot(id: id(3), category: .bottom, colorFamily: .gray, seasons: .all, displayName: "Wool trousers"),
            GarmentSnapshot(id: id(4), category: .bottom, colorFamily: .blue, seasons: [.spring, .summer, .autumn], displayName: "Straight jeans"),
            GarmentSnapshot(id: id(5), category: .shoes, colorFamily: .white, seasons: [.spring, .summer], displayName: "Leather sneakers"),
            GarmentSnapshot(id: id(6), category: .shoes, colorFamily: .brown, seasons: [.autumn, .winter], displayName: "Derby shoes"),
            GarmentSnapshot(id: id(7), category: .outerwear, colorFamily: .beige, seasons: [.spring, .autumn], displayName: "Trench coat"),
            GarmentSnapshot(id: id(8), category: .dress, colorFamily: .black, seasons: [.spring, .summer, .autumn], displayName: "Slip dress"),
            GarmentSnapshot(id: id(9), category: .bag, colorFamily: .brown, seasons: .all, displayName: "Leather tote"),
            GarmentSnapshot(id: id(10), category: .accessory, colorFamily: .metallic, seasons: .all, displayName: "Thin belt")
        ]
    }

    static func sampleItems() -> [ClothingItem] {
        sampleSnapshots().map { snapshot in
            ClothingItem(
                id: snapshot.id,
                displayName: snapshot.displayName,
                subtype: snapshot.category.displayName,
                category: snapshot.category,
                primaryColor: snapshot.colorFamily,
                seasons: snapshot.seasons,
                isFavorite: snapshot.isFavorite
            )
        }
    }

    /// An in-memory container for previews and tests.
    ///
    /// This never opens the user's store. It is also the only place in RIG that
    /// stops on failure rather than recovering: a preview with no SwiftData at
    /// all has nothing to draw, and the production launch path in `RIGApp`
    /// handles the same failure by explaining it to the user instead.
    @MainActor
    static func container(populated: Bool = true) -> ModelContainer {
        guard let container = try? RIGModelContainer.makeInMemoryContainer() else {
            preconditionFailure("Preview-only: in-memory model container could not be created")
        }
        if populated {
            for item in sampleItems() {
                container.mainContext.insert(item)
            }
        }
        return container
    }

    private static func id(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value)) ?? UUID()
    }
}
