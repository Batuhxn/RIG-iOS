import SwiftUI

/// A calm, explanatory empty state. Every list in RIG has one.
struct RIGEmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    /// A second way out of an empty state, when there genuinely is one. Left
    /// nil everywhere it does not apply, so no caller has to opt out.
    var secondaryActionTitle: String? = nil
    var secondaryAction: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: RIGTheme.Spacing.m) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(RIGPrimaryButtonStyle())
                    .padding(.top, RIGTheme.Spacing.xs)
            }
            if let secondaryActionTitle, let secondaryAction {
                Button(secondaryActionTitle, action: secondaryAction)
                    .buttonStyle(RIGSecondaryButtonStyle())
            }
        }
        .frame(maxWidth: 420)
        .padding(RIGTheme.Spacing.l)
        .accessibilityElement(children: .contain)
    }
}

struct RIGPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 50)
            .padding(.horizontal, RIGTheme.Spacing.m)
            .background(Color.accentColor.opacity(configuration.isPressed ? 0.75 : 1))
            .foregroundStyle(Color(uiColor: .systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: RIGTheme.Radius.control, style: .continuous))
            .contentShape(Rectangle())
    }
}

struct RIGSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .frame(maxWidth: .infinity, minHeight: 48)
            .padding(.horizontal, RIGTheme.Spacing.m)
            .background(RIGTheme.tileBackground.opacity(configuration.isPressed ? 0.6 : 1))
            .foregroundStyle(Color.primary)
            .clipShape(RoundedRectangle(cornerRadius: RIGTheme.Radius.control, style: .continuous))
            .contentShape(Rectangle())
    }
}

/// The verdict label. Deliberately words, never a percentage: there is no
/// calibrated probability behind the ranking and the interface must not imply one.
struct MatchBadge: View {
    let band: MatchBand

    var body: some View {
        Text(band.displayName)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, RIGTheme.Spacing.s)
            .padding(.vertical, RIGTheme.Spacing.xs)
            .background(RIGTheme.tileBackground)
            .clipShape(Capsule())
            .accessibilityLabel("Rated \(band.displayName)")
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
                .accessibilityHidden(true)
            Text(message)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let onDismiss {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.semibold))
                }
                .accessibilityLabel("Dismiss message")
            }
        }
        .padding(RIGTheme.Spacing.m)
        .frame(minHeight: 44)
        .background(RIGTheme.tileBackground)
        .clipShape(RoundedRectangle(cornerRadius: RIGTheme.Radius.tile, style: .continuous))
    }
}

struct RIGSectionHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline)
            if let subtitle {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(.isHeader)
    }
}
