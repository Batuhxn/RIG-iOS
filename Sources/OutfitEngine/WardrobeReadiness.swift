import Foundation

/// Whether the wardrobe can support a suggestion at all, and what is missing.
///
/// Asked before generating anything, so an under-stocked wardrobe produces a
/// useful sentence rather than an empty list or a nonsensical look.
struct WardrobeReadiness: Hashable, Sendable {
    let canSuggest: Bool
    let missing: [GarmentCategory]

    static func evaluate(_ wardrobe: [GarmentSnapshot]) -> WardrobeReadiness {
        let categories = Set(wardrobe.map(\.category))
        if categories.contains(.dress) {
            return WardrobeReadiness(canSuggest: true, missing: [])
        }
        let hasTop = categories.contains(.top)
        let hasBottom = categories.contains(.bottom)
        if hasTop && hasBottom {
            return WardrobeReadiness(canSuggest: true, missing: [])
        }

        var missing: [GarmentCategory] = []
        if !hasTop { missing.append(.top) }
        if !hasBottom { missing.append(.bottom) }
        return WardrobeReadiness(canSuggest: false, missing: missing)
    }

    var explanation: String {
        guard !canSuggest else { return "" }
        let names = missing.map { $0.displayName.lowercased() }
        switch names.count {
        case 0:
            return "Add a few more garments to start building looks."
        case 1:
            return "Add a \(names[0]) — or a dress — and RIG can start building looks."
        default:
            return "Add a \(names.joined(separator: " and a ")) — or a dress — and RIG can start building looks."
        }
    }
}
