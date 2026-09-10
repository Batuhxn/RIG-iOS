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
    /// False when background removal did not isolate the garment and the
    /// original photograph is being shown instead.
    var isBackgroundRemoved: Bool

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

    /// The image to show in the interface: the cutout when we have one,
    /// otherwise the original photograph.
    var preferredImageRelativePath: String? {
        cutoutImageRelativePath ?? originalImageRelativePath
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
