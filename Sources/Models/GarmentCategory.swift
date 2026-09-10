import Foundation

/// The finite set of garment kinds RIG understands.
///
/// The raw value is the persistence authority and must never change once shipped.
/// Display names are presentation only and may be localized later.
enum GarmentCategory: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case top
    case bottom
    case dress
    case outerwear
    case shoes
    case bag
    case accessory

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .top: return "Top"
        case .bottom: return "Bottom"
        case .dress: return "Dress"
        case .outerwear: return "Outerwear"
        case .shoes: return "Shoes"
        case .bag: return "Bag"
        case .accessory: return "Accessory"
        }
    }

    /// Placeholder SF Symbols. Deliberately restricted to long-standing symbol
    /// names so no category renders as a missing glyph. Worth a design pass later.
    var symbolName: String {
        switch self {
        case .top: return "tshirt"
        case .bottom: return "rectangle.portrait"
        case .dress: return "figure.stand"
        case .outerwear: return "wind"
        case .shoes: return "figure.walk"
        case .bag: return "bag"
        case .accessory: return "eyeglasses"
        }
    }

    /// Categories that can, on their own or in pairs, form a structurally complete outfit.
    static let baseCategories: [GarmentCategory] = [.top, .bottom, .dress]

    /// Categories that only ever decorate an existing base.
    static let optionalCategories: [GarmentCategory] = [.shoes, .outerwear, .bag, .accessory]

    /// How many of this category a single outfit may contain.
    /// Accessories are the only category allowed to repeat, and only modestly.
    var maximumPerOutfit: Int {
        switch self {
        case .accessory: return 3
        default: return 1
        }
    }

    /// Stable presentation order, used wherever garments are listed so that
    /// ordering never implies anything about compatibility.
    var displayOrder: Int {
        switch self {
        case .dress: return 0
        case .top: return 1
        case .bottom: return 2
        case .outerwear: return 3
        case .shoes: return 4
        case .bag: return 5
        case .accessory: return 6
        }
    }
}
