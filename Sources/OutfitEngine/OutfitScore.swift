import Foundation

/// A coarse verdict band. This is what the interface shows — never a percentage,
/// because there is no calibrated probability behind it.
enum MatchBand: String, Hashable, Sendable, CaseIterable {
    case strong
    case good
    case worthTrying
    case different

    var displayName: String {
        switch self {
        case .strong: return "Güçlü uyum"
        case .good: return "İyi uyum"
        case .worthTrying: return "Denemeye değer"
        case .different: return "Farklı bir şey"
        }
    }

    static func band(for total: Double) -> MatchBand {
        if total >= 0.80 { return .strong }
        if total >= 0.65 { return .good }
        if total >= 0.50 { return .worthTrying }
        return .different
    }
}

/// The full arithmetic behind one ranked outfit, kept so the reason a look was
/// ranked where it was is always inspectable rather than mysterious.
struct OutfitScoreBreakdown: Hashable, Sendable {
    let color: Double
    let season: Double
    let completeness: Double
    let preference: Double
    /// Weighted combination of the four rule components, 0...1.
    let ruleTotal: Double
    /// Non-nil only when a compatibility provider is enabled and returned a value.
    let compatibilitySignal: Double?
    /// What ranking actually uses. Equals `ruleTotal` when no signal is present.
    let total: Double

    var band: MatchBand { MatchBand.band(for: total) }

    /// A short, deterministic sentence assembled from the components above.
    /// It describes the rules that fired. It is not an explanation of taste and
    /// makes no claim about what the user personally likes.
    var summary: String {
        var fragments: [String] = []

        if color >= 0.85 {
            fragments.append("Renkler uyuşuyor")
        } else if color >= 0.65 {
            fragments.append("Renkler birlikte çalışıyor")
        } else if color >= 0.50 {
            fragments.append("Karışık palet")
        } else {
            fragments.append("Güçlü renk kontrastı")
        }

        if season >= 1.0 {
            fragments.append("ortak sezon")
        } else if season >= 0.50 {
            fragments.append("kısmi sezon örtüşmesi")
        } else {
            fragments.append("sezonlar ayrışıyor")
        }

        if completeness >= 0.80 {
            fragments.append("tamamlanmış")
        } else if completeness <= 0.60 {
            fragments.append("henüz ayakkabı yok")
        }

        return fragments.joined(separator: " · ")
    }
}

/// One ranked outfit.
struct OutfitSuggestion: Identifiable, Hashable, Sendable {
    let candidate: OutfitCandidate
    let breakdown: OutfitScoreBreakdown

    var id: String { candidate.signature }
    var items: [GarmentSnapshot] { candidate.items }
    var signature: String { candidate.signature }
}
