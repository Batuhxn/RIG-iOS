import Foundation

/// Whether the wardrobe can support a suggestion at all, and what is missing.
///
/// Asked before generating anything, so an under-stocked wardrobe produces a
/// useful sentence rather than an empty list or a nonsensical look.
struct WardrobeReadiness: Hashable, Sendable {
    struct NextStep: Hashable, Sendable {
        let message: String
        let actionTitle: String
    }

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

    var nextStep: NextStep? {
        guard !canSuggest else { return nil }
        if missing == [.bottom] {
            return NextStep(
                message: "Add a bottom to build your first look.",
                actionTitle: "Add a bottom"
            )
        }
        if missing == [.top] {
            return NextStep(
                message: "Add a top to build your first look.",
                actionTitle: "Add a top"
            )
        }
        return NextStep(
            message: "Add a top and a bottom, or a dress, to build your first look.",
            actionTitle: "Add a garment"
        )
    }
}
