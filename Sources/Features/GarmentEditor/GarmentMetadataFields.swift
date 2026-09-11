import SwiftUI

/// The metadata RIG asks for. Deliberately short.
///
/// The ML spike found that coarse category information carried nearly all of
/// the useful signal while free-text descriptions carried the rest of the cost,
/// so RIG asks for a category and a colour family and does not ask anyone to
/// write prose about their trousers.
struct GarmentMetadataFields: Equatable {
    var displayName: String = ""
    var subtype: String = ""
    var category: GarmentCategory = .top
    var colorFamily: ColorFamily = .black
    var seasons: SeasonSet = .all
    var isFavorite: Bool = false
    var notes: String = ""

    var trimmedName: String {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isValid: Bool {
        !trimmedName.isEmpty && !seasons.normalized.isEmpty
    }

    init() {}

    init(item: ClothingItem) {
        displayName = item.displayName
        subtype = item.subtype
        category = item.category
        colorFamily = item.primaryColor
        seasons = item.seasons
        isFavorite = item.isFavorite
        notes = item.notes
    }

    func apply(to item: ClothingItem, now: Date = Date()) {
        item.displayName = trimmedName
        item.subtype = subtype.trimmingCharacters(in: .whitespacesAndNewlines)
        item.category = category
        item.primaryColor = colorFamily
        item.seasons = seasons
        item.isFavorite = isFavorite
        item.notes = notes
        item.touch(now)
    }
}
