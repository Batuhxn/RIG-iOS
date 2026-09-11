import SwiftUI

/// One saved look in the Kombin list.
///
/// The design draws the garments as a fan of overlapping tiles — each one
/// shifted 14pt left of the last and stacked in front-to-back order, with a
/// surface-coloured ring separating them. It reads as "these belong together"
/// in a way a grid of separate thumbnails does not, and it costs a fraction of
/// the row height.
struct LookRow: View {
    let look: SavedOutfit

    var maximumTiles: Int = 4

    private var visibleItems: [ClothingItem] {
        Array(look.itemsInDisplayOrder.prefix(maximumTiles))
    }

    var body: some View {
        HStack(spacing: 14) {
            fan

            VStack(alignment: .leading, spacing: 3) {
                Text(look.name)
                    .font(.system(size: 14))
                    .foregroundStyle(RIGTheme.textPrimary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(RIGTheme.text(50))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 15))
                .foregroundStyle(RIGTheme.text(35))
        }
        .padding(11)
        .background(RIGTheme.cardBackground, in: RoundedRectangle(cornerRadius: RIGTheme.Radius.large, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(look.name), \(look.items.count) parça")
    }

    private var fan: some View {
        HStack(spacing: -14) {
            ForEach(Array(visibleItems.enumerated()), id: \.element.id) { index, item in
                GarmentImageView(
                    relativePath: item.displayImageRelativePath,
                    symbolName: item.category.symbolName
                )
                .padding(4)
                .frame(width: 44, height: 58)
                .background(
                    RadialGradient(
                        colors: [RIGTheme.Neutral.n700, RIGTheme.Neutral.n900],
                        center: UnitPoint(x: 0.35, y: 0.2),
                        startRadius: 0,
                        endRadius: 70
                    ),
                    in: RoundedRectangle(cornerRadius: RIGTheme.Radius.small, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: RIGTheme.Radius.small, style: .continuous)
                        .strokeBorder(RIGTheme.cardBackground, lineWidth: 1.5)
                )
                .zIndex(Double(maximumTiles - index))
            }
        }
        .accessibilityHidden(true)
    }

    private var subtitle: String {
        let count = look.items.count
        var parts = ["\(count) parça", look.source.displayName]
        if look.hasMissingGarments {
            parts.append("eksik parça var")
        }
        return parts.joined(separator: " · ")
    }
}
