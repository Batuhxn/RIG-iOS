import Foundation

/// Coarse tone classification used by the colour harmony rules.
enum ColorTone: String, Hashable, Sendable {
    /// Combines broadly with almost anything.
    case neutral
    /// Carries a hue that participates in adjacency and complement rules.
    case accent
    /// Cannot be reasoned about with a single hue.
    case unclassified
}

/// A bounded palette the user picks from. RIG v0.1 does not infer colour from
/// pixels; the user tells us, and the raw value is the persistence authority.
enum ColorFamily: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case black
    case white
    case gray
    case beige
    case brown
    case navy
    case blue
    case green
    case olive
    case red
    case burgundy
    case pink
    case purple
    case orange
    case yellow
    case metallic
    case multicolor

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .black: return "Siyah"
        case .white: return "Beyaz"
        case .gray: return "Gri"
        case .beige: return "Bej"
        case .brown: return "Kahverengi"
        case .navy: return "Lacivert"
        case .blue: return "Mavi"
        case .green: return "Yeşil"
        case .olive: return "Haki"
        case .red: return "Kırmızı"
        case .burgundy: return "Bordo"
        case .pink: return "Pembe"
        case .purple: return "Mor"
        case .orange: return "Turuncu"
        case .yellow: return "Sarı"
        case .metallic: return "Metalik"
        case .multicolor: return "Çok renkli"
        }
    }

    var tone: ColorTone {
        switch self {
        case .black, .white, .gray, .beige, .brown, .navy, .metallic:
            return .neutral
        case .multicolor:
            return .unclassified
        case .blue, .green, .olive, .red, .burgundy, .pink, .purple, .orange, .yellow:
            return .accent
        }
    }

    var isNeutral: Bool { tone == .neutral }

    /// Approximate position on a colour wheel, in degrees, for accent families only.
    /// These are coarse anchors for the adjacency and complement rules, not colorimetry.
    var hueAngle: Double? {
        switch self {
        case .red: return 0
        case .orange: return 30
        case .yellow: return 55
        case .olive: return 80
        case .green: return 130
        case .blue: return 220
        case .purple: return 280
        case .pink: return 330
        case .burgundy: return 350
        case .black, .white, .gray, .beige, .brown, .navy, .metallic, .multicolor:
            return nil
        }
    }

    /// Vivid families read as loud when several unrelated ones appear together.
    /// Muted accents (olive, burgundy) are deliberately excluded.
    var isVivid: Bool {
        switch self {
        case .red, .orange, .yellow, .green, .blue, .purple, .pink:
            return true
        default:
            return false
        }
    }
}
