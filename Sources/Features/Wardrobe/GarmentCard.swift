import SwiftUI

/// One garment in the grid. The photograph is the content; the text is support.
///
/// The design's tile is 3:4 with a gradient rising from the bottom, so a
/// cut-out on a dark ground settles into the page rather than sitting on a
/// visible card. The two lines beneath are name and category, small and quiet.
struct GarmentCard: View {
    let item: ClothingItem

    /// Marks the tile as chosen, for multi-select contexts.
    var selectionNumber: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                GarmentImageView(
                    relativePath: item.displayImageRelativePath,
                    symbolName: item.category.symbolName
                )
                .padding(RIGTheme.Spacing.m)
                .frame(maxWidth: .infinity)
                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                .background(tileBackground)
                .overlay(alignment: .bottom) {
                    LinearGradient(
                        colors: [RIGTheme.pageBackground.opacity(0.55), .clear],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                    .frame(height: 60)
                    .allowsHitTesting(false)
                }
                .clipShape(RoundedRectangle(cornerRadius: RIGTheme.Radius.large, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: RIGTheme.Radius.large, style: .continuous)
                        .strokeBorder(
                            selectionNumber == nil ? RIGTheme.Elevation.smallRing : RIGTheme.accent,
                            lineWidth: 1
                        )
                )

                if let selectionNumber {
                    Text("\(selectionNumber)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(RIGTheme.pageBackground)
                        .frame(width: 20, height: 20)
                        .background(RIGTheme.accent, in: Circle())
                        .padding(8)
                } else if item.isFavorite {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(RIGTheme.accent)
                        .padding(10)
                        .accessibilityHidden(true)
                }
            }

            Text(item.displayName)
                .font(.system(size: 13))
                .foregroundStyle(RIGTheme.textPrimary)
                .lineLimit(1)
                .padding(.top, 7)

            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(RIGTheme.text(50))
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    /// A soft radial lift behind the garment, as in the design's tiles. Cut-out
    /// photographs have no ground of their own, so the tile provides one.
    private var tileBackground: some View {
        RadialGradient(
            colors: [RIGTheme.Neutral.n800, RIGTheme.Neutral.n900],
            center: UnitPoint(x: 0.3, y: 0.2),
            startRadius: 0,
            endRadius: 220
        )
    }

    private var subtitle: String {
        let detail = item.subtype.isEmpty ? item.primaryColor.displayName : item.subtype
        return "\(item.category.displayName) · \(detail)"
    }

    private var accessibilityLabel: String {
        var parts = [item.displayName, item.category.displayName, item.primaryColor.displayName]
        if item.isFavorite { parts.append("Favori") }
        if let selectionNumber { parts.append("Seçim \(selectionNumber)") }
        return parts.joined(separator: ", ")
    }
}
