import Foundation
import SwiftData

/// Keeps garment changes in the context only when their save succeeds.
/// The save closure lets tests exercise failure without making a real store fail.
@MainActor
enum GarmentMutations {
    private struct EditableState {
        let displayName: String
        let subtype: String
        let categoryRaw: String
        let primaryColorRaw: String
        let seasonMask: Int
        let isFavorite: Bool
        let notes: String
        let updatedAt: Date

        init(_ item: ClothingItem) {
            displayName = item.displayName
            subtype = item.subtype
            categoryRaw = item.categoryRaw
            primaryColorRaw = item.primaryColorRaw
            seasonMask = item.seasonMask
            isFavorite = item.isFavorite
            notes = item.notes
            updatedAt = item.updatedAt
        }

        func restore(_ item: ClothingItem) {
            item.displayName = displayName
            item.subtype = subtype
            item.categoryRaw = categoryRaw
            item.primaryColorRaw = primaryColorRaw
            item.seasonMask = seasonMask
            item.isFavorite = isFavorite
            item.notes = notes
            item.updatedAt = updatedAt
        }
    }

    @discardableResult
    static func edit(
        _ item: ClothingItem,
        fields: GarmentMetadataFields,
        in context: ModelContext,
        save: () throws -> Void
    ) throws -> Bool {
        let previous = EditableState(item)
        guard fields.apply(to: item) else { return false }
        do {
            try save()
            return true
        } catch {
            previous.restore(item)
            context.rollback()
            throw error
        }
    }

    static func toggleFavorite(
        _ item: ClothingItem,
        in context: ModelContext,
        save: () throws -> Void
    ) throws {
        let previousFavorite = item.isFavorite
        let previousUpdate = item.updatedAt
        item.isFavorite.toggle()
        item.touch()
        do {
            try save()
        } catch {
            item.isFavorite = previousFavorite
            item.updatedAt = previousUpdate
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
