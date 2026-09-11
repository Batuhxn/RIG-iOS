import SwiftUI

// MARK: - Buttons

/// The primary action: an accent outline on transparent, never a fill.
///
/// This is the design system's most explicit rule — its guide states it in the
/// Direction section and again in the component table. On a dark ground a
/// flooded accent would be the one saturated field in the interface, which is
/// exactly what Nocturne forbids; the accent carries its chroma in lines.
struct RIGPrimaryButtonStyle: ButtonStyle {
    /// Full-width, as in every screen's bottom action. Set false for a pill.
    var isBlock: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(RIGTheme.accent)
            .frame(maxWidth: isBlock ? .infinity : nil, minHeight: 50)
            .padding(.horizontal, RIGTheme.Spacing.xl)
            .background(
                RIGTheme.accent.opacity(configuration.isPressed ? 0.22 : 0),
                in: RoundedRectangle(cornerRadius: RIGTheme.Radius.large, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: RIGTheme.Radius.large, style: .continuous)
                    .strokeBorder(RIGTheme.accent, lineWidth: 1)
            )
            .contentShape(Rectangle())
            .animation(NocturneMotion.control, value: configuration.isPressed)
    }
}

/// The secondary action: a divider-coloured outline, no accent.
struct RIGSecondaryButtonStyle: ButtonStyle {
    var isBlock: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(RIGTheme.textPrimary)
            .frame(maxWidth: isBlock ? .infinity : nil, minHeight: 48)
            .padding(.horizontal, RIGTheme.Spacing.xl)
            .background(
                RIGTheme.text(configuration.isPressed ? 14 : 0),
                in: RoundedRectangle(cornerRadius: RIGTheme.Radius.large, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: RIGTheme.Radius.large, style: .continuous)
                    .strokeBorder(RIGTheme.hairline, lineWidth: 1)
            )
            .contentShape(Rectangle())
            .animation(NocturneMotion.control, value: configuration.isPressed)
    }
}

/// The quiet third action — "Kırpmadan devam et", "Yeniden dene", "Atla".
///
/// The design gives every decisive screen exactly one of these below the
/// primary: no border, no fill, dimmed text. It is how the flow offers a way
/// past a step without advertising it as an equal choice.
struct RIGQuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15))
            .foregroundStyle(RIGTheme.text(configuration.isPressed ? 90 : 62))
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
            .animation(NocturneMotion.control, value: configuration.isPressed)
    }
}

/// A circular icon button, as in the wardrobe header and the item-detail hero.
struct RIGIconButtonStyle: ButtonStyle {
    var background: Color = .clear
    var diameter: CGFloat = 44

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17))
            .foregroundStyle(RIGTheme.textPrimary)
            .frame(width: diameter, height: diameter)
            .background(background, in: Circle())
            .overlay(Circle().strokeBorder(RIGTheme.hairline, lineWidth: background == .clear ? 1 : 0))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Circle())
            .animation(NocturneMotion.control, value: configuration.isPressed)
    }
}

/// The floating pill action at the bottom of the wardrobe and outfit tabs.
struct RIGPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(RIGTheme.textPrimary)
            .padding(.horizontal, RIGTheme.Spacing.xxl)
            .frame(minHeight: 48)
            .background(RIGTheme.Accent.a900, in: Capsule())
            .overlay(Capsule().strokeBorder(RIGTheme.accent, lineWidth: 1))
            .shadow(color: .black.opacity(0.6), radius: 14, y: 8)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .contentShape(Capsule())
            .animation(NocturneMotion.control, value: configuration.isPressed)
    }
}

// MARK: - Tags and chips

/// A small tinted label. `.accent` for live state, `.neutral` for settled
/// state, `.outline` for something the user can still act on.
struct RIGTag: View {
    enum Kind { case accent, neutral, outline }

    let text: String
    var kind: Kind = .neutral

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .tracking(0.2)
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(background, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(kind == .outline ? RIGTheme.accent : .clear, lineWidth: 1)
            )
    }

    private var foreground: Color {
        switch kind {
        case .accent: return RIGTheme.Accent.a100
        case .neutral: return RIGTheme.Neutral.n100
        case .outline: return RIGTheme.accent
        }
    }

    private var background: Color {
        switch kind {
        case .accent: return RIGTheme.Accent.a800
        case .neutral: return RIGTheme.Neutral.n800
        case .outline: return .clear
        }
    }
}

/// A selectable pill — filter chips, crop ratios, category choices.
struct RIGChip: View {
    let title: String
    let isOn: Bool
    var size: CGFloat = 13
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(isOn ? RIGTheme.accent : RIGTheme.text(62))
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .background(isOn ? RIGTheme.accent.opacity(0.14) : .clear, in: Capsule())
                .overlay(Capsule().strokeBorder(isOn ? RIGTheme.accent : RIGTheme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .animation(NocturneMotion.control, value: isOn)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Structure

/// A calm, explanatory empty state. Every list in RIG has one.
struct RIGEmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: RIGTheme.Spacing.l) {
            RoundedRectangle(cornerRadius: RIGTheme.Radius.large, style: .continuous)
                .strokeBorder(RIGTheme.text(16), lineWidth: 1)
                .frame(width: 132, height: 168)
                .overlay(
                    Image(systemName: symbol)
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(RIGTheme.text(30))
                )
                .accessibilityHidden(true)

            Text(title)
                .font(.system(size: 22, weight: .medium))
                .multilineTextAlignment(.center)

            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(RIGTheme.text(55))
                .multilineTextAlignment(.center)

            if let actionTitle, let action {
                Button(action: action) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                        Text(actionTitle)
                    }
                }
                .buttonStyle(RIGPillButtonStyle())
                .padding(.top, RIGTheme.Spacing.xs)
            }
        }
        .frame(maxWidth: 420)
        .padding(.horizontal, 42)
        .accessibilityElement(children: .contain)
    }
}

/// A dismissible, recoverable error. Errors in RIG explain and offer a way on;
/// they never dead-end a flow.
struct RIGErrorBanner: View {
    let message: String
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: RIGTheme.Spacing.s) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(RIGTheme.Neutral.n400)
                .accessibilityHidden(true)
            Text(message)
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let onDismiss {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(RIGTheme.text(62))
                }
                .accessibilityLabel("Mesajı kapat")
            }
        }
        .padding(RIGTheme.Spacing.l)
        .frame(minHeight: 44)
        .background(RIGTheme.cardBackground, in: RoundedRectangle(cornerRadius: RIGTheme.Radius.medium, style: .continuous))
        .nocturneElevationSmall(radius: RIGTheme.Radius.medium)
    }
}

struct RIGSectionHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 17, weight: .medium))
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(RIGTheme.text(52))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(.isHeader)
    }
}

/// The screen title block the design opens most tabs with: an accent kicker
/// above a 30pt count.
struct RIGScreenHeading: View {
    let kicker: String
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            RIGTheme.kicker(kicker)
            RIGTheme.title(title)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// A rule that fades to transparent at both ends over 48pt — a Nocturne
/// signature. Box outlines and in-control separators stay solid; freestanding
/// rules fade.
struct RIGFadingRule: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: RIGTheme.hairline, location: 0.18),
                .init(color: RIGTheme.hairline, location: 0.82),
                .init(color: .clear, location: 1)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: 1)
        .accessibilityHidden(true)
    }
}

/// The verdict label for an outfit. Deliberately words, never a percentage:
/// there is no calibrated probability behind outfit ranking and the interface
/// must not imply one. (The duplicate comparison is a separate case — see
/// `SimilarityBadge`.)
struct MatchBadge: View {
    let band: MatchBand

    var body: some View {
        RIGTag(text: band.displayName, kind: .neutral)
            .accessibilityLabel("Değerlendirme: \(band.displayName)")
    }
}
