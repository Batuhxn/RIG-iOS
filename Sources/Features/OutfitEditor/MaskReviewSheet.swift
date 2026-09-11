import SwiftUI
import UIKit

/// Shown after EdgeSAM proposes a mask for a manually drawn box.
///
/// "This is what RIG thinks the garment is." The mask is drawn as an overlay
/// on top of the plain rectangular crop, not as an isolated cutout floating
/// on its own — the user should be able to see exactly what was kept and
/// what was dropped against the photograph they recognise. Manual rectangular
/// crop is one tap away at every point; nothing here is the only way through,
/// and it never will be — see `docs/DECISIONS.md`.
struct MaskReviewSheet: View {
    let rawCropImage: UIImage
    /// The normalized region, in outfit-source space, that produced
    /// `rawCropImage` — needed only to place `mask.boundingRegion` correctly
    /// on top of it.
    let cropRegion: NormalizedCropRect
    let mask: SegmentationMaskResult
    let onUseMask: () -> Void
    let onAdjustSelection: () -> Void
    let onUseRectangularCrop: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: RIGTheme.Spacing.m) {
            overlay
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: RIGTheme.Radius.card, style: .continuous))
                .padding(.horizontal, RIGTheme.Spacing.m)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Proposed garment mask, overlaid on the cropped photo")

            Text("This is what RIG found in the box you drew.")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("Accept it, adjust the box, or use the plain crop instead.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: RIGTheme.Spacing.s) {
                Button("Use mask", action: onUseMask)
                    .buttonStyle(RIGPrimaryButtonStyle())
                Button("Adjust selection", action: onAdjustSelection)
                    .buttonStyle(RIGSecondaryButtonStyle())
                Button("Use rectangular crop instead", action: onUseRectangularCrop)
                    .buttonStyle(RIGSecondaryButtonStyle())
                Button("Skip this garment", role: .destructive, action: onSkip)
                    .font(.footnote)
            }
            .padding(.horizontal, RIGTheme.Spacing.m)
            .padding(.bottom, RIGTheme.Spacing.l)
        }
        .padding(.top, RIGTheme.Spacing.m)
    }

    @ViewBuilder
    private var overlay: some View {
        GeometryReader { proxy in
            let imageRect = CropGeometry.imageRect(for: rawCropImage.size, in: proxy.size)
            ZStack(alignment: .topLeading) {
                Image(uiImage: rawCropImage)
                    .resizable()
                    .frame(width: imageRect.width, height: imageRect.height)
                    .position(x: imageRect.midX, y: imageRect.midY)

                if let maskImage, let localRegion {
                    let overlayRect = CropGeometry.viewRect(for: localRegion, in: imageRect)
                    Image(uiImage: maskImage)
                        .resizable()
                        .frame(width: overlayRect.width, height: overlayRect.height)
                        .position(x: overlayRect.midX, y: overlayRect.midY)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private var maskImage: UIImage? { UIImage(data: mask.cutoutData) }

    private var localRegion: NormalizedCropRect? {
        MaskOverlayGeometry.localRegion(for: mask.boundingRegion, within: cropRegion)
    }
}

/// Shown while EdgeSAM is proposing a mask for the box the user just drew.
/// A distinct, small screen rather than reusing the ordinary "Separating the
/// garment…" processing screen, so a slow decode never reads as the import
/// pipeline itself having started — nothing is written to disk yet.
struct MaskProposingScreen: View {
    var body: some View {
        VStack(spacing: RIGTheme.Spacing.m) {
            ProgressView()
            Text("Looking at that area…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Proposing a garment mask")
    }
}
