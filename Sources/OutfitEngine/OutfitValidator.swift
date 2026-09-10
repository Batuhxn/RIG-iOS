import Foundation

/// Why a set of garments is not a structurally meaningful outfit.
enum OutfitValidationIssue: Hashable, Sendable {
    case empty
    case duplicateGarment
    case missingBase
    case conflictingBase
    case tooMany(GarmentCategory, limit: Int)

    var message: String {
        switch self {
        case .empty:
            return "Add at least one garment."
        case .duplicateGarment:
            return "The same garment is used more than once."
        case .missingBase:
            return "A look needs a top and a bottom, or a dress."
        case .conflictingBase:
            return "A dress already covers the top and bottom."
        case .tooMany(let category, let limit):
            if limit == 1 {
                return "Only one \(category.displayName.lowercased()) per look."
            }
            return "At most \(limit) \(category.displayName.lowercased()) items per look."
        }
    }
}

struct OutfitValidation: Hashable, Sendable {
    let issues: [OutfitValidationIssue]

    var isValid: Bool { issues.isEmpty }

    static let valid = OutfitValidation(issues: [])
}

/// The single authority on whether a set of garments is a real outfit.
///
/// RIG owns this. No score from any provider, now or later, may overrule it —
/// a high number on a structurally nonsensical set is still a nonsensical set.
enum OutfitValidator {
    static func validate(_ items: [GarmentSnapshot]) -> OutfitValidation {
        var issues: [OutfitValidationIssue] = []

        guard !items.isEmpty else {
            return OutfitValidation(issues: [.empty])
        }

        if Set(items.map(\.id)).count != items.count {
            issues.append(.duplicateGarment)
        }

        var counts: [GarmentCategory: Int] = [:]
        for item in items {
            counts[item.category, default: 0] += 1
        }

        // Deterministic issue order: iterate the enum, not the dictionary.
        for category in GarmentCategory.allCases {
            let count = counts[category, default: 0]
            let limit = category.maximumPerOutfit
            if count > limit {
                issues.append(.tooMany(category, limit: limit))
            }
        }

        let hasDress = counts[.dress, default: 0] > 0
        let hasTop = counts[.top, default: 0] > 0
        let hasBottom = counts[.bottom, default: 0] > 0

        if hasDress && (hasTop || hasBottom) {
            issues.append(.conflictingBase)
        } else if !hasDress && !(hasTop && hasBottom) {
            issues.append(.missingBase)
        }

        return OutfitValidation(issues: issues)
    }

    static func isValid(_ items: [GarmentSnapshot]) -> Bool {
        validate(items).isValid
    }
}
