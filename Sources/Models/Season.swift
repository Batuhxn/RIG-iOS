import Foundation

/// A single season. Raw values are the persistence authority for UI selections;
/// the stored representation on a garment is the `SeasonSet` bitmask.
enum Season: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case spring
    case summer
    case autumn
    case winter

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .spring: return "Spring"
        case .summer: return "Summer"
        case .autumn: return "Autumn"
        case .winter: return "Winter"
        }
    }

    var set: SeasonSet {
        switch self {
        case .spring: return .spring
        case .summer: return .summer
        case .autumn: return .autumn
        case .winter: return .winter
        }
    }
}

/// Compact multi-season representation. Stored as an `Int` bitmask so the model
/// stays migration friendly and the engine stays cheap.
struct SeasonSet: OptionSet, Hashable, Sendable {
    let rawValue: Int

    init(rawValue: Int) {
        self.rawValue = rawValue
    }

    static let spring = SeasonSet(rawValue: 1 << 0)
    static let summer = SeasonSet(rawValue: 1 << 1)
    static let autumn = SeasonSet(rawValue: 1 << 2)
    static let winter = SeasonSet(rawValue: 1 << 3)

    /// Every season RIG knows about. An "all season" garment stores this value.
    static let all: SeasonSet = [.spring, .summer, .autumn, .winter]

    /// Defensive normalisation. A garment with no seasons recorded — which should
    /// not happen through the UI — is treated as suitable all year rather than
    /// being silently excluded from every suggestion.
    var normalized: SeasonSet {
        let bounded = intersection(SeasonSet.all)
        return bounded.isEmpty ? SeasonSet.all : bounded
    }

    var seasons: [Season] {
        Season.allCases.filter { contains($0.set) }
    }

    var isAllSeason: Bool { normalized == SeasonSet.all }

    init(_ seasons: [Season]) {
        self = seasons.reduce(into: SeasonSet()) { $0.formUnion($1.set) }
    }

    var displayName: String {
        let normalizedSet = normalized
        if normalizedSet.isAllSeason { return "All year" }
        return normalizedSet.seasons.map(\.displayName).joined(separator: ", ")
    }
}
