import Foundation
import SwiftData

/// Keeps garment changes in the context only when their save succeeds.
/// The save closure lets tests exercise failure without making a real store fail.
@MainActor
enum GarmentMutations {
    @discardableResult
    static func edit(
        _ item: ClothingItem,
        fields: GarmentMetadataFields,
        in context: ModelContext,
        save: () throws -> Void
    ) throws -> Bool {
        guard fields.apply(to: item) else { return false }
        do {
            try save()
            return true
        } catch {
            context.rollback()
            throw error
        }
    }

    static func toggleFavorite(
        _ item: ClothingItem,
        in context: ModelContext,
        save: () throws -> Void
    ) throws {
        item.isFavorite.toggle()
        item.touch()
        do {
            try save()
        } catch {
            context.rollback()
            throw error
        }
    }

    static func delete(
        _ item: ClothingItem,
        in context: ModelContext,
        save: () throws -> Void,
        removeImages: (UUID) throws -> Void
    ) throws {
        let id = item.id
        context.delete(item)
        do {
            try save()
        } catch {
            context.rollback()
            throw error
        }

        // The row is authoritative. An orphan sweep can retry file cleanup.
        try? removeImages(id)
    }
}
