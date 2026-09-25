import Foundation
import SwiftData

/// One garment the user owns.
///
/// Enumerations are persisted as raw strings rather than as Codable enum values
/// so that adding a case later cannot invalidate an existing store. Image bytes
/// are never stored here — only relative paths into the garment image store.
@Model
final class ClothingItem {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var displayName: String
    var subtype: String
    var categoryRaw: String
    var primaryColorRaw: String
    var seasonMask: Int
    var isFavorite: Bool
    var notes: String
    var originalImageRelativePath: String?
    var cutoutImageRelativePath: String?
    var thumbnailRelativePath: String?
    /// True when the user chose the cutout for display. False when they chose
    /// the original, including when no cutout could be produced.
    var isBackgroundRemoved: Bool

    /// Looks that use this garment. Annotated explicitly, and with the delete
    /// rule spelled out, so no later edit can turn this into a cascade:
    /// deleting a garment must never delete the looks it appeared in.
    /// The inverse is declared once, on `SavedOutfit.items`.
    @Relationship(deleteRule: .nullify)
    var outfits: [SavedOutfit] = []

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        displayName: String,
        subtype: String = "",
        category: GarmentCategory,
        primaryColor: ColorFamily,
        seasons: SeasonSet = .all,
        isFavorite: Bool = false,
        notes: String = "",
        originalImageRelativePath: String? = nil,
        cutoutImageRelativePath: String? = nil,
        thumbnailRelativePath: String? = nil,
        isBackgroundRemoved: Bool = false
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.displayName = displayName
        self.subtype = subtype
        self.categoryRaw = category.rawValue
        self.primaryColorRaw = primaryColor.rawValue
        self.seasonMask = seasons.normalized.rawValue
        self.isFavorite = isFavorite
        self.notes = notes
        self.originalImageRelativePath = originalImageRelativePath
        self.cutoutImageRelativePath = cutoutImageRelativePath
        self.thumbnailRelativePath = thumbnailRelativePath
        self.isBackgroundRemoved = isBackgroundRemoved
    }
}

extension ClothingItem {
    /// Unknown raw values fall back to `.accessory`, which is the category with
    /// the least structural authority, so a corrupt row can never masquerade as
    /// the base of an outfit.
    var category: GarmentCategory {
        get { GarmentCategory(rawValue: categoryRaw) ?? .accessory }
        set { categoryRaw = newValue.rawValue }
    }

    /// Unknown raw values fall back to `.multicolor`, which the harmony rules
    /// deliberately score in the middle rather than confidently.
    var primaryColor: ColorFamily {
        get { ColorFamily(rawValue: primaryColorRaw) ?? .multicolor }
        set { primaryColorRaw = newValue.rawValue }
    }

    var seasons: SeasonSet {
        get { SeasonSet(rawValue: seasonMask).normalized }
        set { seasonMask = newValue.normalized.rawValue }
    }

    /// The user's chosen image. A cutout file may be retained even when the
    /// original is selected, so the flag must decide which path wins.
    var preferredImageRelativePath: String? {
        isBackgroundRemoved
            ? (cutoutImageRelativePath ?? originalImageRelativePath)
            : (originalImageRelativePath ?? cutoutImageRelativePath)
    }

    /// What a grid or a card should draw: the thumbnail when one exists, then
    /// the cutout, then the original photograph.
    ///
    /// Written as a single property rather than chained `??` at each call site.
    /// Chaining on an optional garment produces a doubly-optional value whose
    /// `??` collapses the wrong layer, which silently swallows the fallback.
    var displayImageRelativePath: String? {
        thumbnailRelativePath ?? preferredImageRelativePath
    }

    var relativeImagePaths: [String] {
        [originalImageRelativePath, cutoutImageRelativePath, thumbnailRelativePath].compactMap { $0 }
    }

    var snapshot: GarmentSnapshot {
        GarmentSnapshot(
            id: id,
            category: category,
            colorFamily: primaryColor,
            seasons: seasons,
            displayName: displayName,
            isFavorite: isFavorite
        )
    }

    func touch(_ now: Date = Date()) {
        updatedAt = now
    }
}
