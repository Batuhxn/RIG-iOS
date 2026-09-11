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
        let names = missing.map { $0.displayName.lowercased(with: Locale(identifier: "tr_TR")) }
        switch names.count {
        case 0:
            return "Kombin oluşturmaya başlamak için birkaç parça daha ekle."
        case 1:
            return "Bir \(names[0]) — ya da bir elbise — ekle, RIG kombin kurmaya başlasın."
        default:
            return "Bir \(names.joined(separator: " ve bir ")) — ya da bir elbise — ekle, RIG kombin kurmaya başlasın."
        }
    }
}
