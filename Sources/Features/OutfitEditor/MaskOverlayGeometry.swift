import Foundation

/// Converts a mask's bounding region — expressed in the outfit source
/// photograph's own normalized space — into the local normalized space of
/// one manually drawn crop rectangle.
///
/// `GarmentSegmenting` always reports a mask's bounds in RIG source-space
/// (the whole outfit photo), because that is the space its embedding was
/// computed against. The mask review screen, though, draws its overlay on
/// top of the small rectangular crop the user actually drew — not the whole
/// photograph — so the bounds have to be re-expressed relative to that
/// crop's own frame before `CropGeometry.viewRect(for:in:)` can place them.
/// Kept separate from `CropGeometry` because this step has nothing to do
/// with touch handling and needs none of it to be tested.
enum MaskOverlayGeometry {
    /// Returns nil when `cropRegion` cannot be divided into (a zero-size
    /// crop has no local frame to convert into) or the result is not a
    /// usable rectangle — the mask review screen's answer to either is to
    /// draw no overlay rather than a distorted one.
    static func localRegion(
        for maskBoundingRegion: NormalizedCropRect,
        within cropRegion: NormalizedCropRect
    ) -> NormalizedCropRect? {
        guard cropRegion.isUsable, cropRegion.width > 0, cropRegion.height > 0 else { return nil }
        let local = NormalizedCropRect(
            x: (maskBoundingRegion.x - cropRegion.x) / cropRegion.width,
            y: (maskBoundingRegion.y - cropRegion.y) / cropRegion.height,
            width: maskBoundingRegion.width / cropRegion.width,
            height: maskBoundingRegion.height / cropRegion.height
        )
        return local.isUsable ? local : nil
    }

    /// The exact inverse of `localRegion`, for one point rather than a
    /// rectangle: converts a tap the user made on `MaskReviewSheet`'s
    /// overlay — normalized to the *crop's own* frame, `(0,0)` its
    /// top-left — back into RIG source-space, the frame every
    /// `EdgeSAMGeometry.PromptPoint` is expressed in. v0.4 Slice 2.1's
    /// interactive refinement is what needs this direction; mask overlay
    /// placement only ever needed the region-to-local direction above.
    /// `nil` for a degenerate crop region, mirroring `localRegion`.
    static func sourcePoint(
        forLocalX localX: Double, localY: Double, within cropRegion: NormalizedCropRect
    ) -> (x: Double, y: Double)? {
        guard cropRegion.isUsable, cropRegion.width > 0, cropRegion.height > 0,
              localX.isFinite, localY.isFinite else { return nil }
        return (
            x: cropRegion.x + localX * cropRegion.width,
            y: cropRegion.y + localY * cropRegion.height
        )
    }

    /// The forward direction of `sourcePoint`: where an already-placed
    /// RIG-source-space point (an accepted `EdgeSAMGeometry.PromptPoint`)
    /// falls within the crop's own frame, so `MaskReviewSheet` can draw a
    /// marker for it. `nil` for a degenerate crop region, or a source point
    /// that landed outside this particular crop.
    static func localPoint(
        forSourceX sourceX: Double, sourceY: Double, within cropRegion: NormalizedCropRect
    ) -> (x: Double, y: Double)? {
        guard cropRegion.isUsable, cropRegion.width > 0, cropRegion.height > 0,
              sourceX.isFinite, sourceY.isFinite else { return nil }
        return (
            x: (sourceX - cropRegion.x) / cropRegion.width,
            y: (sourceY - cropRegion.y) / cropRegion.height
        )
    }
}
