import SwiftUI
import UIKit

/// The mandatory side-by-side comparison before a new garment is created,
/// whenever RIG believes the wardrobe might already have it.
///
/// The user is never asked a blind "existing or new?" — they see both
/// photographs, the shared category, and how close the two are, and only then
/// choose. Nothing here merges or discards a garment on its own; every path
/// out of this screen is a decision the user made, and "not a match" or
/// "discard" leave the wardrobe exactly as it was.
struct DuplicateComparisonSheet: View {
    /// The freshly imported candidate's own bytes — not yet any garment's
    /// row, so this is drawn from `Data` directly rather than through
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
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            RIGSheetGrabber()

            if let match = state.current {
                content(for: match)
            } else {
                // Reached only if a caller presents this sheet with an
                // already-exhausted state; the intended path is that the
                // caller checks `state.isExhausted` first and skips straight
                // to the ordinary add-as-new flow instead.
                exhausted
            }
        }
        .frame(maxWidth: .infinity)
        .background(RIGTheme.cardBackground)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: RIGTheme.Radius.sheet,
                topTrailingRadius: RIGTheme.Radius.sheet,
                style: .continuous
            )
        )
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .presentationBackground(RIGTheme.cardBackground)
    }

    @ViewBuilder
    private func content(for match: WardrobeSimilarityMatch) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "square.on.square")
                    .font(.system(size: 11))
                RIGTheme.kicker("Benzer parça", size: 11, tracking: 1.1)
            }
            .foregroundStyle(RIGTheme.accent)
            .padding(.top, 16)

            Text("Dolabında buna çok benzeyen bir parça var")
                .font(.system(size: 22, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            Text("%\(SimilarityScore.percent(for: match.distance)) benzerlik · \(candidateCategory.displayName)")
                .font(.system(size: 13))
                .foregroundStyle(RIGTheme.text(58))
                .padding(.top, 6)

            comparison(for: match)
                .padding(.top, 18)

            Text("Karşılaştırma tamamen bu cihazda, kendi fotoğraflarınla yapılır. Bu oran bir benzerlik puanıdır — aynı parça olduğunun kanıtı değil. Buna sen karar verirsin.")
                .font(.system(size: 11))
                .foregroundStyle(RIGTheme.text(50))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)

            Spacer(minLength: RIGTheme.Spacing.l)

            actions(for: match)
        }
        .padding(.horizontal, RIGTheme.Spacing.xl)
        .padding(.bottom, RIGTheme.Spacing.xl)
    }

    private func actions(for match: WardrobeSimilarityMatch) -> some View {
        VStack(spacing: RIGTheme.Spacing.s) {
            Button("Yine de ekle", action: onAddAsNew)
                .buttonStyle(RIGPrimaryButtonStyle())

            // The design labels this "update the existing item". RIG does not
            // update anything here — it keeps the existing garment untouched
            // and discards this candidate's files — so the label says that.
            Button("Mevcut parçayı kullan") { onUseExisting(match.garmentID) }
                .buttonStyle(RIGQuietButtonStyle())

            if state.hasAnother {
                Button("Eşleşmiyor — başkasını göster", action: onShowAnother)
                    .buttonStyle(RIGQuietButtonStyle())
            }

            Button("Bu fotoğrafı at", role: .destructive, action: onSkip)
                .font(.system(size: 13))
                .foregroundStyle(RIGTheme.Neutral.n400)
                .frame(minHeight: 44)
        }
    }

    private func comparison(for match: WardrobeSimilarityMatch) -> some View {
        ZStack {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    candidateImage
                        .padding(RIGTheme.Spacing.s)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(3.0 / 4.0, contentMode: .fit)
                        .background(RIGTheme.pageBackground, in: RoundedRectangle(cornerRadius: RIGTheme.Radius.medium, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: RIGTheme.Radius.medium, style: .continuous)
                                .strokeBorder(RIGTheme.accent, lineWidth: 1)
                        )
                    Text("Yeni parça")
                        .font(.system(size: 12))
                        .padding(.top, 7)
                    Text("Bugün eklendi")
                        .font(.system(size: 11))
                        .foregroundStyle(RIGTheme.text(48))
                }

                VStack(alignment: .leading, spacing: 0) {
                    GarmentImageView(
                        relativePath: existingItemImagePath(match.garmentID),
                        symbolName: candidateCategory.symbolName
                    )
                    .padding(RIGTheme.Spacing.s)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(3.0 / 4.0, contentMode: .fit)
                    .background(RIGTheme.pageBackground, in: RoundedRectangle(cornerRadius: RIGTheme.Radius.medium, style: .continuous))
                    .nocturneElevationSmall(radius: RIGTheme.Radius.medium)

                    Text(existingItemName(match.garmentID) ?? "Dolabında")
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .padding(.top, 7)
                    Text(match.band.displayLabel)
                        .font(.system(size: 11))
                        .foregroundStyle(RIGTheme.text(48))
                }
            }

            scoreRing(for: match)
                .offset(y: -22)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Benzerlik puanı yüzde \(SimilarityScore.percent(for: match.distance)). "
            + "Yeni parça ile \(existingItemName(match.garmentID) ?? "dolabındaki parça") karşılaştırılıyor."
        )
    }

    private func scoreRing(for match: WardrobeSimilarityMatch) -> some View {
        Text("\(SimilarityScore.percent(for: match.distance))")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(RIGTheme.accent)
            .frame(width: 34, height: 34)
            .background(RIGTheme.pageBackground, in: Circle())
            .overlay(Circle().strokeBorder(RIGTheme.Accent.a700, lineWidth: 1))
            .accessibilityHidden(true)
    }

    private var exhausted: some View {
        VStack(spacing: RIGTheme.Spacing.l) {
            Text("Karşılaştırılacak bir şey kalmadı.")
                .font(.system(size: 15))
                .foregroundStyle(RIGTheme.text(55))
            Button("Yine de ekle", action: onAddAsNew)
                .buttonStyle(RIGPrimaryButtonStyle())
        }
        .padding(.horizontal, RIGTheme.Spacing.xl)
        .padding(.vertical, RIGTheme.Spacing.xl)
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
                .foregroundStyle(RIGTheme.text(35))
        }
    }
}

/// Turns a feature-print distance into the percentage the comparison shows.
///
/// This is a **similarity score**, not a confidence and not a probability.
/// Vision's feature-print distance is an uncalibrated metric: 0 means the two
/// images produced identical descriptors, and larger means further apart. The
/// percentage is simply `1 - distance`, so it is monotonic in the thing it
/// reports and honest about being a distance readout — which is why the sheet
/// says "benzerlik puanı" next to it and why nothing in the app treats it as
/// odds that two garments are the same.
///
/// Outfit ranking is a separate case and still shows words, never numbers.
enum SimilarityScore {
    static func percent(for distance: Float) -> Int {
        let clamped = min(max(distance, 0), 1)
        return Int(((1 - clamped) * 100).rounded())
    }
}
