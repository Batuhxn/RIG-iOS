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
///
/// **v0.4 Slice 2.1** adds interactive refinement: the user can tap the
/// image to add a positive ("include this area") or negative ("exclude this
/// area") point, which re-runs the decoder against the same cached
/// embedding and shows an updated mask — never accepted automatically, the
/// user still has to tap "Use mask" themselves regardless of how many
/// refinements they made.
struct MaskReviewSheet: View {
    let rawCropImage: UIImage
    /// The normalized region, in outfit-source space, that produced
    /// `rawCropImage` — needed to place `mask.boundingRegion` and every
    /// point marker correctly on top of it.
    let cropRegion: NormalizedCropRect
    let mask: SegmentationMaskResult
    /// Every refinement point accumulated for this candidate so far, in
    /// RIG source-space — drawn as markers, and the source of truth for
    /// what the next `onAddPoint` call appends to.
    let refinementPoints: [EdgeSAMGeometry.PromptPoint]
    /// True while a refinement re-decode is in flight. The sheet stays on
    /// screen and interactive throughout — this only disables adding
    /// another point mid-decode, never hides the current mask.
    let isRefining: Bool
    let onUseMask: () -> Void
    let onAdjustSelection: () -> Void
    let onUseRectangularCrop: () -> Void
    let onSkip: () -> Void
    /// A point the user tapped, already converted to RIG source-space and
    /// labelled by the sheet's own positive/negative toggle.
    let onAddPoint: (EdgeSAMGeometry.PromptPoint) -> Void
    let onResetPoints: () -> Void

    @State private var placementMode: PlacementMode = .positive

    enum PlacementMode {
        case positive
        case negative
    }

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
            Text("Tap the photo to include or exclude an area, accept it, adjust the box, or use the plain crop instead.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            refinementControls

            VStack(spacing: RIGTheme.Spacing.s) {
                Button("Use mask", action: onUseMask)
                    .buttonStyle(RIGPrimaryButtonStyle())
                    .disabled(isRefining)
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

    private var refinementControls: some View {
        HStack(spacing: RIGTheme.Spacing.s) {
            Picker("Tap to", selection: $placementMode) {
                Text("Include").tag(PlacementMode.positive)
                Text("Exclude").tag(PlacementMode.negative)
            }
            .pickerStyle(.segmented)

            if isRefining {
                ProgressView().controlSize(.small)
            } else if refinementPoints.count > 1 {
                // The first point is always the automatic box-center anchor
                // (see `EdgeSAMGeometry.centerPoint`) — "Reset points" only
                // has something to undo once the user has added their own.
                Button("Reset points", action: onResetPoints)
                    .font(.footnote)
            }
        }
        .padding(.horizontal, RIGTheme.Spacing.m)
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
                        .opacity(isRefining ? 0.5 : 1)
                }

                ForEach(Array(pointMarkers(in: imageRect).enumerated()), id: \.offset) { _, marker in
                    Circle()
                        .fill(marker.isPositive ? Color.green : Color.red)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                        .position(marker.location)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        guard !isRefining, imageRect.contains(value.location) else { return }
                        let localX = Double((value.location.x - imageRect.minX) / imageRect.width)
                        let localY = Double((value.location.y - imageRect.minY) / imageRect.height)
                        guard let source = MaskOverlayGeometry.sourcePoint(
                            forLocalX: localX, localY: localY, within: cropRegion
                        ) else { return }
                        onAddPoint(EdgeSAMGeometry.PromptPoint(
                            x: source.x, y: source.y, isPositive: placementMode == .positive
                        ))
                    }
            )
        }
    }

    private var maskImage: UIImage? { UIImage(data: mask.cutoutData) }

    private var localRegion: NormalizedCropRect? {
        MaskOverlayGeometry.localRegion(for: mask.boundingRegion, within: cropRegion)
    }

    /// Every refinement point converted from RIG source-space into a view
    /// position within `imageRect` — the same rect `overlay`'s
    /// `GeometryReader` computed from the container it is actually drawing
    /// into, passed in rather than recomputed so there is only ever one
    /// source of truth for where the image sits on screen.
    private func pointMarkers(in imageRect: CGRect) -> [(isPositive: Bool, location: CGPoint)] {
        refinementPoints.compactMap { point in
            guard let local = MaskOverlayGeometry.localPoint(
                forSourceX: point.x, sourceY: point.y, within: cropRegion
            ), (0...1).contains(local.x), (0...1).contains(local.y) else { return nil }
            return (
                point.isPositive,
                CGPoint(x: imageRect.minX + local.x * imageRect.width, y: imageRect.minY + local.y * imageRect.height)
            )
        }
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
