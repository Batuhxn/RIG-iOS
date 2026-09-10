import Foundation
import SwiftData

/// Owns the SwiftData stack. Everything RIG persists is listed here in one place.
enum RIGModelContainer {
    static let schema = Schema([
        ClothingItem.self,
        SavedOutfit.self,
        OutfitFeedback.self
    ])

    /// The on-disk container. Failure is surfaced to the user rather than
    /// trapped, because a wardrobe that cannot be saved must not look saved.
    static func makePersistentContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// Used by previews and unit tests. Never touches the user's store.
    static func makeInMemoryContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
