import Foundation
import SwiftData

/// v0.4 lazy backfill. When a duplicate check had to embed an existing garment (saved before
/// v0.4, or under another encoder), that identity is stored on the garment so the same photo
/// is never embedded again. Best effort and invisible: a failed save is rolled back and the
/// check, and the garment being added, carry on exactly as before.
///
/// The write goes through its own `ModelContext` on the same container, never the shared
/// environment context: a rollback here can only discard identity changes, never another
/// screen's pending edits, and a successful save never commits those edits early.
@MainActor
enum WardrobeIdentityBackfill {
    static func store(_ computed: [UUID: GarmentVisualIdentity], on items: [ClothingItem], in context: ModelContext) {
        guard !computed.isEmpty else { return }
        store(computed, in: context.container)
    }

    static func store(_ computed: [UUID: GarmentVisualIdentity], in container: ModelContainer) {
        guard !computed.isEmpty else { return }
        let isolated = ModelContext(container)
        isolated.autosaveEnabled = false
        let ids = Array(computed.keys)
        let descriptor = FetchDescriptor<ClothingItem>(predicate: #Predicate { ids.contains($0.id) })
        guard let items = try? isolated.fetch(descriptor) else { return }
        var changed = false
        for item in items {
            guard let identity = computed[item.id], item.visualIdentity != identity else { continue }
            item.visualIdentity = identity
            changed = true
        }
        guard changed else { return }
        do {
            try isolated.save()
        } catch {
            isolated.rollback()
        }
    }
}
