import Foundation

/// An immutable, framework-free view of one garment.
///
/// The outfit engine works exclusively on snapshots. That keeps every scoring
/// rule testable without SwiftData, SwiftUI or a running app, and it is also the
/// shape a future compatibility provider would receive.
struct GarmentSnapshot: Identifiable, Hashable, Sendable {
    let id: UUID
    let category: GarmentCategory
    let colorFamily: ColorFamily
    let seasons: SeasonSet
    let displayName: String
    let isFavorite: Bool

    init(
        id: UUID,
        category: GarmentCategory,
        colorFamily: ColorFamily,
        seasons: SeasonSet,
        displayName: String,
        isFavorite: Bool = false
    ) {
        self.id = id
        self.category = category
        self.colorFamily = colorFamily
        self.seasons = seasons.normalized
        self.displayName = displayName
        self.isFavorite = isFavorite
    }
}

extension Array where Element == GarmentSnapshot {
    /// Deterministic presentation order. Category first, then name, then id so
    /// that two runs over the same wardrobe always agree.
    var inDisplayOrder: [GarmentSnapshot] {
        sorted { lhs, rhs in
            if lhs.category.displayOrder != rhs.category.displayOrder {
                return lhs.category.displayOrder < rhs.category.displayOrder
            }
            if lhs.displayName != rhs.displayName {
                return lhs.displayName < rhs.displayName
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}
