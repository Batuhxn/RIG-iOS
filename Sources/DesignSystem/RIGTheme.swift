import SwiftUI

/// Visual constants. Understated, editorial, system-native.
///
/// Colours come from the system palette so light and dark mode, increased
/// contrast and tinting all work without a second theme to maintain. The only
/// custom colours in the app are the palette swatches below, which have to be
/// literal because they represent actual garment colours.
enum RIGTheme {
    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 36
    }

    enum Radius {
        static let card: CGFloat = 14
        static let tile: CGFloat = 10
        static let control: CGFloat = 12
    }

    static let cardBackground = Color(uiColor: .secondarySystemGroupedBackground)
    static let pageBackground = Color(uiColor: .systemGroupedBackground)
    static let tileBackground = Color(uiColor: .tertiarySystemFill)
    static let hairline = Color(uiColor: .separator)

    /// The wordmark. A serif face is the whole of RIG's editorial character;
    /// everything else is plain system type.
    static func wordmark(_ text: String) -> some View {
        Text(text)
            .font(.system(.largeTitle, design: .serif, weight: .regular))
            .kerning(2)
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
