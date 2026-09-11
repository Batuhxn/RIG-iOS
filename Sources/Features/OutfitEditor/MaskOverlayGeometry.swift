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
}
