import SwiftUI

/// Visual constants — the Nocturne design system, in Swift.
///
/// Nocturne is a dark-only system: a near-neutral blue-grey ground, Inter at
/// medium weight, compact 0.7x spacing, and a single blurple accent used as a
/// line and a glow rather than a flood. Every value below is transcribed from
/// the design system's `styles.css`, which is the source of truth for the look.
///
/// Two consequences worth stating, because they are not obvious:
///
/// **The palette is literal, not semantic.** RIG previously took its colours
/// from the system palette so that light mode, increased contrast and tinting
/// came for free. Nocturne specifies exact values on a dark ground and has no
/// light variant, so the app pins itself to `.dark` and paints its own colours.
/// The design's own next-steps note asks for a light variant; when one exists,
/// it belongs here and nowhere else.
///
/// **Primary actions are outlined, never filled.** The system's guide says so
/// twice. `RIGPrimaryButtonStyle` implements it.
enum RIGTheme {
    // MARK: - Ground

    /// The page ground. `--color-bg`.
    static let pageBackground = Color(nocturne: 0x161826)
    /// Raised surfaces: cards, rows, sheets, inputs. `--color-surface`.
    static let cardBackground = Color(nocturne: 0x232532)
    /// Alias kept for call sites that mean "a filled tile".
    static let tileBackground = Color(nocturne: 0x232532)
    /// Body text. `--color-text`.
    static let textPrimary = Color(nocturne: 0xE9E9ED)
    /// The single accent. `--color-accent`.
    static let accent = Color(nocturne: 0x9184D9)
    /// `--color-divider`: the text colour at 16%.
    static let hairline = Color(nocturne: 0xE9E9ED).opacity(0.16)

    // MARK: - Tonal ramps
    //
    // Generated in OKLCH on one shared lightness scale, so the same step of any
    // ramp carries the same visual weight. On this dark ground: 700-900 for
    // tinted fills, hovers and subtle borders; 500 as the role's base; 100-300
    // for text on those tints. Prefer a ramp step over an ad-hoc opacity.

    enum Neutral {
        static let n100 = Color(nocturne: 0xF3F5FE)
        static let n200 = Color(nocturne: 0xE4E7F5)
        static let n300 = Color(nocturne: 0xCFD3E5)
        static let n400 = Color(nocturne: 0xB2B6CA)
        static let n500 = Color(nocturne: 0x9397AB)
        static let n600 = Color(nocturne: 0x75798C)
        static let n700 = Color(nocturne: 0x595D6C)
        static let n800 = Color(nocturne: 0x3F424D)
        static let n900 = Color(nocturne: 0x292B31)
    }

    enum Accent {
        static let a100 = Color(nocturne: 0xF5F4FF)
        static let a200 = Color(nocturne: 0xE7E5FE)
        static let a300 = Color(nocturne: 0xD2CEFD)
        static let a400 = Color(nocturne: 0xB5ABFC)
        static let a500 = Color(nocturne: 0x968AE0)
        static let a600 = Color(nocturne: 0x796CBF)
        static let a700 = Color(nocturne: 0x5D5294)
        static let a800 = Color(nocturne: 0x423A6A)
        static let a900 = Color(nocturne: 0x2B2741)
    }

    /// Text at a fraction of its full strength. The design expresses secondary
    /// text as `color-mix(in srgb, var(--color-text) N%, transparent)`; this is
    /// the same thing, and the percentages used here are the ones it uses.
    static func text(_ percent: Int) -> Color {
        Color(nocturne: 0xE9E9ED).opacity(Double(percent) / 100)
    }

    // MARK: - Spacing
    //
    // Nocturne is dense on purpose (density 0.7x). The `--space-*` scale is
    // carried verbatim; the named steps are what call sites use.

    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 26

        /// Horizontal gutter for every full-screen layout in the design.
        static let screen: CGFloat = 20

        /// The design system's own scale, for cases that should track it.
        static let space1: CGFloat = 2.8
        static let space2: CGFloat = 5.6
        static let space3: CGFloat = 8.4
        static let space4: CGFloat = 11.2
        static let space6: CGFloat = 16.8
        static let space8: CGFloat = 22.4
    }

    // MARK: - Radius

    enum Radius {
        /// `--radius-sm`: thumbnails and queue tiles.
        static let small: CGFloat = 4
        /// `--radius-md`: inputs, rows, medium tiles.
        static let medium: CGFloat = 8
        /// `--radius-lg`: cards, primary buttons, garment tiles.
        static let large: CGFloat = 14
        /// The bottom-sheet top corners.
        static let sheet: CGFloat = 26

        // Names the pre-Nocturne call sites use, remapped onto the scale above.
        static let card: CGFloat = 14
        static let tile: CGFloat = 8
        static let control: CGFloat = 14
    }

    // MARK: - Elevation
    //
    // On a dark ground elevation is a hairline edge plus ambient darkness, and
    // shadows are never stacked. Each group below is one `--shadow-*` token.

    enum Elevation {
        /// `--shadow-sm`: a hairline ring, no cast shadow.
        static let smallRing = Color(nocturne: 0x3F424D)
        /// `--shadow-md`.
        static let mediumRing = Color(nocturne: 0x595D6C)
        static let mediumShadow = Color.black.opacity(0.55)
        static let mediumRadius: CGFloat = 9
        static let mediumY: CGFloat = 6
        /// `--shadow-lg`.
        static let largeRing = Color(nocturne: 0x9397AB)
        static let largeShadow = Color.black.opacity(0.65)
        static let largeRadius: CGFloat = 20
        static let largeY: CGFloat = 16
    }

    // MARK: - Type
    //
    // Inter is the design's face. It is not a system font on iOS and is not
    // bundled, so the app uses the system face at the design's sizes, weights
    // and tracking. Headings never go past weight 500 — in this system
    // hierarchy is size and space, not weight.

    /// 30pt screen title ("128 parça").
    static func title(_ value: String) -> Text {
        Text(value).font(.system(size: 30, weight: .medium)).tracking(-0.6)
    }

    /// The wordmark. Retained for the pre-Nocturne home screen while its
    /// responsibilities are relocated; the Nocturne tabs open with
    /// `RIGScreenHeading` instead.
    static func wordmark(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 30, weight: .medium))
            .tracking(2)
            .foregroundStyle(textPrimary)
    }

    /// The uppercase, letter-spaced accent label that opens most screens
    /// ("DOLABIM", "KOMBİNLER", "ÜST GİYİM").
    static func kicker(_ value: String, size: CGFloat = 10, tracking: CGFloat = 1.4) -> some View {
        Text(value.uppercased(with: Locale(identifier: "tr_TR")))
            .font(.system(size: size))
            .tracking(tracking)
            .foregroundStyle(accent)
    }

    /// Approximate swatches for the colour picker. These illustrate a family;
    /// they are not the garment's measured colour.
    static func swatch(for family: ColorFamily) -> Color {
        switch family {
        case .black: return Color(red: 0.09, green: 0.09, blue: 0.10)
        case .white: return Color(red: 0.97, green: 0.97, blue: 0.96)
        case .gray: return Color(red: 0.55, green: 0.56, blue: 0.58)
        case .beige: return Color(red: 0.85, green: 0.78, blue: 0.66)
        case .brown: return Color(red: 0.45, green: 0.32, blue: 0.22)
        case .navy: return Color(red: 0.11, green: 0.16, blue: 0.32)
        case .blue: return Color(red: 0.20, green: 0.44, blue: 0.78)
        case .green: return Color(red: 0.20, green: 0.52, blue: 0.34)
        case .olive: return Color(red: 0.45, green: 0.46, blue: 0.26)
        case .red: return Color(red: 0.76, green: 0.20, blue: 0.20)
        case .burgundy: return Color(red: 0.44, green: 0.13, blue: 0.20)
        case .pink: return Color(red: 0.90, green: 0.62, blue: 0.68)
        case .purple: return Color(red: 0.44, green: 0.31, blue: 0.62)
        case .orange: return Color(red: 0.87, green: 0.49, blue: 0.20)
        case .yellow: return Color(red: 0.91, green: 0.76, blue: 0.25)
        case .metallic: return Color(red: 0.71, green: 0.72, blue: 0.74)
        case .multicolor: return Color(red: 0.62, green: 0.55, blue: 0.72)
        }
    }
}

extension Color {
    /// A literal design-system colour. Nocturne specifies exact values, so the
    /// app carries exact values; there is no semantic equivalent to fall back on.
    init(nocturne hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

extension View {
    /// `--shadow-sm`: a hairline ring at the given radius.
    func nocturneElevationSmall(radius: CGFloat) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(RIGTheme.Elevation.smallRing, lineWidth: 1)
        )
    }

    /// `--shadow-md`: hairline ring plus ambient darkness.
    func nocturneElevationMedium(radius: CGFloat) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(RIGTheme.Elevation.mediumRing, lineWidth: 1)
        )
        .shadow(
            color: RIGTheme.Elevation.mediumShadow,
            radius: RIGTheme.Elevation.mediumRadius,
            y: RIGTheme.Elevation.mediumY
        )
    }

    /// `--shadow-lg`: the top elevation, for sheets and lifted cards.
    func nocturneElevationLarge(radius: CGFloat) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(RIGTheme.Elevation.largeRing, lineWidth: 1)
        )
        .shadow(
            color: RIGTheme.Elevation.largeShadow,
            radius: RIGTheme.Elevation.largeRadius,
            y: RIGTheme.Elevation.largeY
        )
    }
}
