import Foundation
import SwiftData

/// How a saved look came into existence.
enum OutfitSource: String, Codable, Hashable, Sendable {
    case manual
    case suggestion

    var displayName: String {
        switch self {
        case .manual: return "Built by you"
        case .suggestion: return "Saved suggestion"
        }
    }
}

/// A look the user chose to keep.
///
/// Garment order is never persisted, because order carries no meaning here and
/// storing it would invite someone to treat position as compatibility. The UI
/// sorts by category at display time instead.
@Model
final class SavedOutfit {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var name: String
    var sourceRaw: String
    /// Recorded at save time so a look keeps a stable identity even after a
    /// garment is deleted from the wardrobe.
    var signature: String

    /// Many-to-many with `ClothingItem`. `nullify` in both directions:
    /// deleting a look leaves every garment in the wardrobe, and deleting a
    /// garment leaves the look standing with one fewer item — which
    /// `hasMissingGarments` then detects against the signature recorded at
    /// save time. The inverse is declared here and only here.
    @Relationship(deleteRule: .nullify, inverse: \ClothingItem.outfits)
    var items: [ClothingItem]

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        name: String,
        source: OutfitSource,
        items: [ClothingItem]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.name = name
        self.sourceRaw = source.rawValue
        self.items = items
        self.signature = OutfitSignature.signature(forGarmentIDs: items.map(\.id))
    }
}

extension SavedOutfit {
    /// The name a look gets when the user does not type one.
    static func defaultName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        return "Look · \(formatter.string(from: date))"
    }

    var source: OutfitSource {
        get { OutfitSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    var itemsInDisplayOrder: [ClothingItem] {
        items.sorted { lhs, rhs in
            if lhs.category.displayOrder != rhs.category.displayOrder {
                return lhs.category.displayOrder < rhs.category.displayOrder
            }
            if lhs.displayName != rhs.displayName {
                return lhs.displayName < rhs.displayName
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    var snapshots: [GarmentSnapshot] {
        items.map(\.snapshot)
    }

    /// True when garments that were part of this look have since been deleted
    /// from the wardrobe. The look is kept; the interface says what happened.
    var hasMissingGarments: Bool {
        OutfitSignature.signature(forGarmentIDs: items.map(\.id)) != signature
    }
}
