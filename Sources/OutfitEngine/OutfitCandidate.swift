import Foundation

/// A set of garments being considered as a look.
///
/// Item order is presentation only. Nothing in the engine reads position as
/// meaning, and the signature deliberately discards it.
struct OutfitCandidate: Identifiable, Hashable, Sendable {
    let items: [GarmentSnapshot]

    init(items: [GarmentSnapshot]) {
        self.items = items.inDisplayOrder
    }

    var id: String { signature }

    var signature: String { OutfitSignature.signature(for: items) }

    /// Identity of the structural base alone. Used to keep a batch of
    /// suggestions from being the same trousers five times with different shoes.
    var baseSignature: String {
        OutfitSignature.signature(for: items.filter { GarmentCategory.baseCategories.contains($0.category) })
    }

    func items(in category: GarmentCategory) -> [GarmentSnapshot] {
        items.filter { $0.category == category }
    }

    func contains(_ category: GarmentCategory) -> Bool {
        items.contains { $0.category == category }
    }

    var colorFamilies: [ColorFamily] { items.map(\.colorFamily) }

    var seasonSets: [SeasonSet] { items.map(\.seasons) }
}
