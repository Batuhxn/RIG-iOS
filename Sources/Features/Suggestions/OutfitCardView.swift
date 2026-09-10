import SwiftUI

/// One ranked look.
///
/// It shows a band and a short rule summary, never a percentage and never a
/// claim about the user's taste.
struct OutfitCardView: View {
    let suggestion: OutfitSuggestion
    let garments: [UUID: ClothingItem]
    let recordedRating: OutfitRating?
    let isSaved: Bool
    let onSave: () -> Void
    let onRate: (OutfitRating) -> Void

    private let columns = [GridItem(.adaptive(minimum: 76), spacing: RIGTheme.Spacing.s)]

    var body: some View {
        VStack(alignment: .leading, spacing: RIGTheme.Spacing.m) {
            HStack {
                MatchBadge(band: suggestion.breakdown.band)
                Spacer()
                if isSaved {
                    Label("Saved", systemImage: "checkmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .labelStyle(.titleAndIcon)
                }
            }

            LazyVGrid(columns: columns, spacing: RIGTheme.Spacing.s) {
                ForEach(suggestion.items) { snapshot in
                    VStack(spacing: RIGTheme.Spacing.xs) {
                        GarmentImageView(
                            relativePath: garments[snapshot.id]?.thumbnailRelativePath
                                ?? garments[snapshot.id]?.preferredImageRelativePath,
                            symbolName: snapshot.category.symbolName
                        )
                        .padding(RIGTheme.Spacing.xs)
                        .frame(height: 86)
                        .background(RIGTheme.tileBackground)
                        .clipShape(RoundedRectangle(cornerRadius: RIGTheme.Radius.tile, style: .continuous))

                        Text(snapshot.displayName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Text(suggestion.breakdown.summary)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: RIGTheme.Spacing.s) {
                Button {
                    onSave()
                } label: {
                    Label(isSaved ? "Saved" : "Save", systemImage: isSaved ? "checkmark" : "square.and.arrow.down")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .background(RIGTheme.tileBackground)
                .clipShape(RoundedRectangle(cornerRadius: RIGTheme.Radius.control, style: .continuous))
                .disabled(isSaved)
                .accessibilityLabel(isSaved ? "Already saved" : "Save this look")

                Button {
                    onRate(.liked)
                } label: {
                    Image(systemName: recordedRating == .liked ? "hand.thumbsup.fill" : "hand.thumbsup")
                        .frame(width: 52, height: 44)
                }
                .buttonStyle(.plain)
                .background(RIGTheme.tileBackground)
                .clipShape(RoundedRectangle(cornerRadius: RIGTheme.Radius.control, style: .continuous))
                .accessibilityLabel("Like this look")

                Button {
                    onRate(.disliked)
                } label: {
                    Image(systemName: recordedRating == .disliked ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                        .frame(width: 52, height: 44)
                }
                .buttonStyle(.plain)
                .background(RIGTheme.tileBackground)
                .clipShape(RoundedRectangle(cornerRadius: RIGTheme.Radius.control, style: .continuous))
                .accessibilityLabel("Dislike this look")
            }
        }
        .padding(RIGTheme.Spacing.m)
        .background(RIGTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: RIGTheme.Radius.card, style: .continuous))
    }
}
