import SwiftUI

/// One garment in the grid. The photograph is the content; the text is support.
struct GarmentCard: View {
    let item: ClothingItem

    var body: some View {
        VStack(alignment: .leading, spacing: RIGTheme.Spacing.s) {
            ZStack(alignment: .topTrailing) {
                GarmentImageView(
                    relativePath: item.thumbnailRelativePath ?? item.preferredImageRelativePath,
                    symbolName: item.category.symbolName
                )
                .padding(RIGTheme.Spacing.s)
                .frame(height: 150)
                .frame(maxWidth: .infinity)
                .background(RIGTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: RIGTheme.Radius.card, style: .continuous))

                if item.isFavorite {
                    Image(systemName: "heart.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(RIGTheme.Spacing.s)
                        .accessibilityHidden(true)
                }
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(item.displayName)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(item.subtype.isEmpty ? item.category.displayName : item.subtype)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        var parts = [item.displayName, item.category.displayName, item.primaryColor.displayName]
        if item.isFavorite { parts.append("Favourite") }
        return parts.joined(separator: ", ")
    }
}
