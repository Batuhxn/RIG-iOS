import SwiftUI

/// How a saved look is drawn.
///
/// Deliberately a tidy arrangement of the garment cutouts the user owns. RIG
/// does not render a body, does not simulate fit and does not synthesise
/// photography — a look is the clothes, shown plainly.
struct LookCompositionView: View {
    let items: [ClothingItem]
    var maximumTiles: Int = 6

    private var visibleItems: [ClothingItem] {
        Array(items.prefix(maximumTiles))
    }

    private var overflowCount: Int {
        max(items.count - maximumTiles, 0)
    }

    private var columns: [GridItem] {
        let count = min(max(visibleItems.count, 1), 3)
        return Array(repeating: GridItem(.flexible(), spacing: RIGTheme.Spacing.s), count: count)
    }

    var body: some View {
        VStack(spacing: RIGTheme.Spacing.xs) {
            LazyVGrid(columns: columns, spacing: RIGTheme.Spacing.s) {
                ForEach(visibleItems) { item in
                    GarmentImageView(
                        relativePath: item.thumbnailRelativePath ?? item.preferredImageRelativePath,
                        symbolName: item.category.symbolName
                    )
                    .padding(RIGTheme.Spacing.xs)
                    .aspectRatio(1, contentMode: .fit)
                    .background(RIGTheme.tileBackground)
                    .clipShape(RoundedRectangle(cornerRadius: RIGTheme.Radius.tile, style: .continuous))
                }
            }
            if overflowCount > 0 {
                Text("+\(overflowCount) more")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
}

struct LookCard: View {
    let look: SavedOutfit

    var body: some View {
        VStack(alignment: .leading, spacing: RIGTheme.Spacing.s) {
            LookCompositionView(items: look.itemsInDisplayOrder, maximumTiles: 4)
                .padding(RIGTheme.Spacing.s)
                .background(RIGTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: RIGTheme.Radius.card, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(look.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(look.source.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(look.name), \(look.items.count) garments")
    }
}
