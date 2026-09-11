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
            return "En az bir parça ekle."
        case .duplicateGarment:
            return "Aynı parça birden fazla kez kullanılmış."
        case .missingBase:
            return "Bir kombinde üst ve alt ya da bir elbise olmalı."
        case .conflictingBase:
            return "Elbise zaten üstü ve altı karşılıyor."
        case .tooMany(let category, let limit):
            if limit == 1 {
                return "Kombin başına yalnızca bir \(category.displayName.lowercased(with: Locale(identifier: "tr_TR")))."
            }
            return "Kombin başına en fazla \(limit) \(category.displayName.lowercased(with: Locale(identifier: "tr_TR")))."
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
