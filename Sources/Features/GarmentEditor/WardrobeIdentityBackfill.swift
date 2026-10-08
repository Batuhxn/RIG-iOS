import Foundation
import SwiftData

/// v0.4 lazy backfill. When a duplicate check had to embed an existing garment (saved before
/// v0.4, or under another encoder), that identity is stored on the garment so the same photo
/// is never embedded again. Best effort and invisible: a failed save is rolled back and the
/// check, and the garment being added, carry on exactly as before.
@MainActor
enum WardrobeIdentityBackfill {
    static func store(_ computed: [UUID: GarmentVisualIdentity], on items: [ClothingItem], in context: ModelContext) {
        guard !computed.isEmpty else { return }
        var changed = false
        for item in items {
            guard let identity = computed[item.id], item.visualIdentity != identity else { continue }
            item.visualIdentity = identity
            changed = true
        }
        guard changed else { return }
        do {
            try context.save()
        } catch {
            context.rollback()
        }
    }
}
