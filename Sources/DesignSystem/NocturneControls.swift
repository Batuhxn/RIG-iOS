import SwiftUI

/// The two-option segmented control, as used for Önce/Sonra on the review
/// screen. A hairline box, one accent-ringed option, no fill.
struct RIGSegmentedControl<Value: Hashable>: View {
    let options: [(value: Value, label: String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                if index > 0 {
                    Rectangle()
                        .fill(RIGTheme.hairline)
                        .frame(width: 1)
                }
                Button {
                    selection = option.value
                } label: {
                    Text(option.label)
                        .font(.system(size: 13))
                        .foregroundStyle(selection == option.value ? RIGTheme.accent : RIGTheme.textPrimary)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .overlay(
                            Rectangle()
                                .strokeBorder(
                                    selection == option.value ? RIGTheme.accent : .clear,
                                    lineWidth: 1
                                )
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == option.value ? [.isButton, .isSelected] : .isButton)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: RIGTheme.Radius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: RIGTheme.Radius.medium, style: .continuous)
                .strokeBorder(RIGTheme.hairline, lineWidth: 1)
        )
        .animation(NocturneMotion.control, value: selection)
    }
}

/// The sheet grabber: a 38x4 rounded bar, centred.
///
/// iOS draws its own grabber on a presented sheet, but the design's sheets are
/// surface-coloured with a 26pt top radius and their own header row, so the
/// system chrome is hidden and this stands in its place.
struct RIGSheetGrabber: View {
    var body: some View {
        Capsule()
            .fill(RIGTheme.text(28))
            .frame(width: 38, height: 4)
            .padding(.top, 8)
            .accessibilityHidden(true)
    }
}

/// The header row shared by the picker and the confirmation sheets: a leading
/// action, a centred title, a trailing action.
struct RIGSheetHeader: View {
    let title: String
    var leadingTitle: String? = nil
    var leadingAction: (() -> Void)? = nil
    var trailingTitle: String? = nil
    var trailingAction: (() -> Void)? = nil
    var isTrailingEnabled: Bool = true

    var body: some View {
        ZStack {
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .accessibilityAddTraits(.isHeader)

            HStack {
                if let leadingTitle, let leadingAction {
                    Button(leadingTitle, action: leadingAction)
                        .font(.system(size: 15))
                        .foregroundStyle(RIGTheme.text(65))
                }
                Spacer(minLength: 0)
                if let trailingTitle, let trailingAction {
                    Button(trailingTitle, action: trailingAction)
                        .font(.system(size: 15))
                        .foregroundStyle(isTrailingEnabled ? RIGTheme.accent : RIGTheme.text(30))
                        .disabled(!isTrailingEnabled)
                }
            }
        }
        .frame(minHeight: 44)
        .padding(.horizontal, RIGTheme.Spacing.xl)
    }
}

/// The in-flow screen header: a back button, a centred title, and a spacer
/// that keeps the title optically centred.
struct RIGFlowHeader: View {
    let title: String
    var detail: String? = nil
    var backTitle: String = "Geri"
    var onBack: (() -> Void)? = nil

    var body: some View {
        ZStack {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                if let detail {
                    Text("· \(detail)")
                        .font(.system(size: 15))
                        .foregroundStyle(RIGTheme.text(45))
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            HStack {
                if let onBack {
                    Button(action: onBack) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.left")
                            Text(backTitle)
                        }
                        .font(.system(size: 15))
                        .foregroundStyle(RIGTheme.text(65))
                    }
                }
                Spacer(minLength: 0)
                Color.clear.frame(width: 56, height: 1)
            }
        }
        .frame(minHeight: 44)
        .padding(.horizontal, RIGTheme.Spacing.xl)
    }
}

/// The checkerboard ground behind a cut-out garment — the conventional "this
/// is transparent" signal, drawn at the design's 22pt square.
struct RIGCheckerboard: View {
    var square: CGFloat = 22

    var body: some View {
        Canvas { context, size in
            let columns = Int(ceil(size.width / square))
            let rows = Int(ceil(size.height / square))
            for row in 0..<max(rows, 1) {
                for column in 0..<max(columns, 1) {
                    guard (row + column).isMultiple(of: 2) else { continue }
                    let rect = CGRect(
                        x: CGFloat(column) * square,
                        y: CGFloat(row) * square,
                        width: square,
                        height: square
                    )
                    context.fill(Path(rect), with: .color(RIGTheme.Neutral.n900))
                }
            }
        }
        .background(Color(nocturne: 0x1C1E2B))
        .accessibilityHidden(true)
    }
}

/// A selectable colour circle, as on the details screen.
struct RIGColorDot: View {
    let colour: Color
    let isOn: Bool
    var label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(colour)
                .frame(width: 34, height: 34)
                .overlay(Circle().strokeBorder(RIGTheme.text(12), lineWidth: isOn ? 0 : 1))
                .overlay(
                    Circle()
                        .strokeBorder(RIGTheme.accent, lineWidth: isOn ? 2 : 0)
                        .padding(-4)
                )
                .scaleEffect(isOn ? 1.08 : 1)
        }
        .buttonStyle(.plain)
        .animation(NocturneMotion.control, value: isOn)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}

/// A labelled text field in the design's form style.
struct RIGField<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(RIGTheme.text(70))
            content
        }
    }
}

/// The design's text input: surface fill, hairline border, 44pt tall.
struct RIGTextField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        TextField(placeholder, text: $text)
            .font(.system(size: 15))
            .foregroundStyle(RIGTheme.textPrimary)
            .tint(RIGTheme.accent)
            .padding(.horizontal, 10)
            .frame(minHeight: 44)
            .background(RIGTheme.cardBackground, in: RoundedRectangle(cornerRadius: RIGTheme.Radius.medium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: RIGTheme.Radius.medium, style: .continuous)
                    .strokeBorder(RIGTheme.hairline, lineWidth: 1)
            )
    }
}

/// One of the three numbers on the profile screen.
struct RIGStatTile: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 22, weight: .medium))
                .tracking(-0.4)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(RIGTheme.text(50))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 13)
        .padding(.horizontal, 12)
        .background(RIGTheme.cardBackground, in: RoundedRectangle(cornerRadius: RIGTheme.Radius.medium, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }
}

/// The gradient that lifts a floating action clear of scrolling content at the
/// bottom of the wardrobe and outfit tabs.
struct RIGBottomScrim: View {
    var height: CGFloat = 106

    var body: some View {
        LinearGradient(
            stops: [
                .init(color: RIGTheme.pageBackground, location: 0),
                .init(color: RIGTheme.pageBackground, location: 0.46),
                .init(color: .clear, location: 1)
            ],
            startPoint: .bottom,
            endPoint: .top
        )
        .frame(height: height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
