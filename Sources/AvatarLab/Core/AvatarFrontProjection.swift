#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

/// The 2D preview's camera: an orthographic front view, so a world point maps
/// to the screen with one scale and no perspective. The 2D overlay places each
/// garment photo in the front bounds of the same shell the 3D preview uses, so
/// both modes agree on where a garment sits.
struct AvatarFrontProjection: Equatable, Sendable {
    var viewWidth: CGFloat
    var viewHeight: CGFloat
    /// World metres visible from top to bottom.
    var visibleHeight: Float
    /// World y at the centre of the view.
    var centreY: Float

    var pointsPerMetre: CGFloat { viewHeight / CGFloat(visibleHeight) }

    func point(x: Float, y: Float) -> CGPoint {
        CGPoint(x: viewWidth / 2 + CGFloat(x) * pointsPerMetre,
                y: viewHeight / 2 - CGFloat(y - centreY) * pointsPerMetre)
    }

    /// Where to draw a garment photo of `imageAspect` (width / height): fitted
    /// inside the shell's front bounds, centred horizontally, pinned to the top
    /// (collar or waistband), so its proportions are kept.
    func overlayRect(for shell: AvatarMesh, imageAspect: CGFloat) -> CGRect? {
        guard let bounds = shell.frontBounds, imageAspect > 0, imageAspect.isFinite else { return nil }
        let topLeft = point(x: bounds.min.x, y: bounds.max.y)
        let bottomRight = point(x: bounds.max.x, y: bounds.min.y)
        let box = CGRect(x: topLeft.x, y: topLeft.y, width: bottomRight.x - topLeft.x, height: bottomRight.y - topLeft.y)
        guard box.width > 0, box.height > 0 else { return nil }
        var size = CGSize(width: box.width, height: box.width / imageAspect)
        if size.height > box.height {
            size = CGSize(width: box.height * imageAspect, height: box.height)
        }
        return CGRect(x: box.midX - size.width / 2, y: box.minY, width: size.width, height: size.height)
    }
}
