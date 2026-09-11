import SwiftUI
import UIKit

/// The mandatory side-by-side comparison before a new garment is created,
/// whenever RIG believes the wardrobe might already have it.
///
/// The user is never asked a blind "existing or new?" — they see both
/// photographs, the shared category, and a plain-language similarity label,
/// and only then choose. Nothing here merges or discards a garment on its
/// own; every path out of this screen is a decision the user made, and
/// "not a match" or "skip" leave the wardrobe exactly as it was.
struct DuplicateComparisonSheet: View {
    /// The freshly extracted candidate's own bytes — not yet any garment's
    /// file, so this is drawn from `Data` directly rather than through
    /// `GarmentImageView`, which reads from the store by relative path.
    let candidateImageData: Data
    let candidateCategory: GarmentCategory
    let state: DuplicateReviewState
    /// Resolves an existing garment's own stored image for the right-hand
    /// side. Injected so this view stays free of SwiftData, the same reason
    /// `WardrobeSimilarityCandidateItem` stays free of `ClothingItem`.
    let existingItemImagePath: (UUID) -> String?
    let existingItemName: (UUID) -> String?

    let onUseExisting: (UUID) -> Void
    let onAddAsNew: () -> Void
    let onShowAnother: () -> Void
    let onAdjustCandidate: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: RIGTheme.Spacing.m) {
            Text("RIG found something similar")
                .font(.headline)
                .padding(.top, RIGTheme.Spacing.m)

            if let match = state.current {
                comparison(for: match)
                    .padding(.horizontal, RIGTheme.Spacing.m)

                HStack(spacing: RIGTheme.Spacing.s) {
                    Text(candidateCategory.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    SimilarityBadge(band: match.band)
                }

                Text("Comparing your own photos, on this device. RIG does not know these are the same garment — you do.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, RIGTheme.Spacing.l)

                VStack(spacing: RIGTheme.Spacing.s) {
                    Button("Use this existing item") { onUseExisting(match.garmentID) }
                        .buttonStyle(RIGPrimaryButtonStyle())
                    Button("Add as new item", action: onAddAsNew)
                        .buttonStyle(RIGSecondaryButtonStyle())
                    if state.hasAnother {
                        Button("Not a match — show another", action: onShowAnother)
                            .font(.footnote)
                    }
                    HStack(spacing: RIGTheme.Spacing.m) {
                        Button("Adjust candidate", action: onAdjustCandidate)
                        Button("Skip", role: .destructive, action: onSkip)
                    }
                    .font(.footnote)
                    .padding(.top, RIGTheme.Spacing.xs)
                }
                .padding(.horizontal, RIGTheme.Spacing.m)
                .padding(.bottom, RIGTheme.Spacing.l)
            } else {
                // Reached only if a caller presents this sheet with an
                // already-exhausted state; the intended path is that the
                // caller checks `state.isExhausted` first and skips straight
                // to the ordinary add-as-new flow instead.
                Text("Nothing left to compare.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Add as new item", action: onAddAsNew)
                    .buttonStyle(RIGPrimaryButtonStyle())
                    .padding(.horizontal, RIGTheme.Spacing.m)
                    .padding(.bottom, RIGTheme.Spacing.l)
            }
        }
    }

    private func comparison(for match: WardrobeSimilarityMatch) -> some View {
        HStack(spacing: RIGTheme.Spacing.m) {
            VStack(spacing: RIGTheme.Spacing.xs) {
                Text("New photo")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                candidateImage
                    .frame(height: 200)
                    .frame(maxWidth: .infinity)
                    .background(RIGTheme.tileBackground)
                    .clipShape(RoundedRectangle(cornerRadius: RIGTheme.Radius.tile, style: .continuous))
            }
            VStack(spacing: RIGTheme.Spacing.xs) {
                Text(existingItemName(match.garmentID) ?? "In your wardrobe")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                GarmentImageView(
                    relativePath: existingItemImagePath(match.garmentID),
                    symbolName: candidateCategory.symbolName
                )
                .frame(height: 200)
                .frame(maxWidth: .infinity)
                .background(RIGTheme.tileBackground)
                .clipShape(RoundedRectangle(cornerRadius: RIGTheme.Radius.tile, style: .continuous))
            }
        }
    }

    @ViewBuilder
    private var candidateImage: some View {
        if let uiImage = UIImage(data: candidateImageData) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .accessibilityHidden(true)
        } else {
            Image(systemName: candidateCategory.symbolName)
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.tertiary)
        }
    }
}

/// The similarity verdict label. Words only, exactly like `MatchBadge` —
/// there is no calibrated probability behind this ranking either, so a
/// percentage here would be exactly the lie `docs/DECISIONS.md` already
/// rules out for outfit suggestions.
struct SimilarityBadge: View {
    let band: SimilarityBand

    var body: some View {
        Text(band.displayLabel)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, RIGTheme.Spacing.s)
            .padding(.vertical, RIGTheme.Spacing.xs)
            .background(RIGTheme.tileBackground)
            .clipShape(Capsule())
            .accessibilityLabel("Rated \(band.displayLabel)")
    }
}
