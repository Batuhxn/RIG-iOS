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

    /// A band-wise warp of a garment photo onto its shell: the photo is cut into
    /// `bands` horizontal strips from collar (or waistband) to hem, and each strip
    /// is stretched to the shell's front width at that height. The photo keeps
    /// its print and colour but follows the body's shoulders, waist and hips.
    /// Bands where the shell has no vertex take their neighbour's width.
    func warpBands(for shell: AvatarMesh, bands: Int = 48) -> [CGRect]? {
        guard bands > 0, let bounds = shell.frontBounds, bounds.max.y > bounds.min.y else { return nil }
        let height = (bounds.max.y - bounds.min.y) / Float(bands)
        var spans = [(lo: Float, hi: Float)?](repeating: nil, count: bands)
        for p in shell.positions {
            let band = min(bands - 1, max(0, Int((bounds.max.y - p.y) / height)))
            if let s = spans[band] {
                spans[band] = (min(s.lo, p.x), max(s.hi, p.x))
            } else {
                spans[band] = (p.x, p.x)
            }
        }
        for i in spans.indices where spans[i] == nil {
            if let previous = spans[..<i].compactMap({ $0 }).last {
                spans[i] = previous
            } else if let next = spans[(i + 1)...].compactMap({ $0 }).first {
                spans[i] = next
            }
        }
        let smoothed = Self.smooth(spans.compactMap { $0 }.map { ($0.lo, $0.hi) })
        guard smoothed.count == bands else { return nil }
        return smoothed.enumerated().map { i, span in
            let top = point(x: span.lo, y: bounds.max.y - Float(i) * height)
            let bottom = point(x: span.hi, y: bounds.max.y - Float(i + 1) * height)
            return CGRect(x: top.x, y: top.y, width: max(bottom.x - top.x, 1), height: bottom.y - top.y)
        }
    }

    /// Moving average over neighbouring bands, so outlines step gently instead
    /// of jumping (a stair-step edge reads as a torn garment).
    static func smooth<T: BinaryFloatingPoint>(_ spans: [(lo: T, hi: T)], radius: Int = 2) -> [(lo: T, hi: T)] {
        spans.indices.map { i in
            let window = spans[max(0, i - radius)...min(spans.count - 1, i + radius)]
            let n = T(window.count)
            return (window.reduce(T(0)) { $0 + $1.lo } / n, window.reduce(T(0)) { $0 + $1.hi } / n)
        }
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
