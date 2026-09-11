import CoreGraphics
import Foundation
import UIKit

/// A rectangle expressed as fractions of a source image, origin at top-left.
///
/// Fractions rather than pixels on purpose: the same region means the same
/// thing on the scaled-down copy a finger dragged over, on the full-resolution
/// source the crop is actually taken from, and in a future where the rectangle
/// arrives from something other than a finger.
struct NormalizedCropRect: Equatable, Sendable {
    /// Below this, a rectangle is a mis-tap rather than a garment.
    static let minimumSide: Double = 0.05

    var x: Double
    var y: Double
    var width: Double
    var height: Double

    static let full = NormalizedCropRect(x: 0, y: 0, width: 1, height: 1)

    /// The opening rectangle: the middle of the photograph and deliberately not
    /// all of it, so it is immediately obvious the rectangle can be moved.
    static let centeredDefault = NormalizedCropRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)

    var isUsable: Bool {
        width >= Self.minimumSide && height >= Self.minimumSide
    }

    /// Pulls the rectangle inside the image and enforces the minimum side.
    func clamped() -> NormalizedCropRect {
        let boundedWidth = min(max(width, Self.minimumSide), 1)
        let boundedHeight = min(max(height, Self.minimumSide), 1)
        return NormalizedCropRect(
            x: min(max(x, 0), 1 - boundedWidth),
            y: min(max(y, 0), 1 - boundedHeight),
            width: boundedWidth,
            height: boundedHeight
        )
    }

    func translated(dx: Double, dy: Double) -> NormalizedCropRect {
        NormalizedCropRect(x: x + dx, y: y + dy, width: width, height: height).clamped()
    }

    /// Drags one corner while the opposite corner stays exactly where it is.
    ///
    /// The dragged edge stops at the minimum size rather than crossing over the
    /// one opposite it, so a fast drag cannot invert the rectangle.
    func resized(_ corner: CropCorner, dx: Double, dy: Double) -> NormalizedCropRect {
        var leading = x
        var top = y
        var trailing = x + width
        var bottom = y + height

        switch corner {
        case .topLeading:
            leading += dx
            top += dy
        case .topTrailing:
            trailing += dx
            top += dy
        case .bottomLeading:
            leading += dx
            bottom += dy
        case .bottomTrailing:
            trailing += dx
            bottom += dy
        }

        leading = min(max(leading, 0), 1)
        trailing = min(max(trailing, 0), 1)
        top = min(max(top, 0), 1)
        bottom = min(max(bottom, 0), 1)

        switch corner {
        case .topLeading:
            leading = min(leading, trailing - Self.minimumSide)
            top = min(top, bottom - Self.minimumSide)
        case .topTrailing:
            trailing = max(trailing, leading + Self.minimumSide)
            top = min(top, bottom - Self.minimumSide)
        case .bottomLeading:
            leading = min(leading, trailing - Self.minimumSide)
            bottom = max(bottom, top + Self.minimumSide)
        case .bottomTrailing:
            trailing = max(trailing, leading + Self.minimumSide)
            bottom = max(bottom, top + Self.minimumSide)
        }

        return NormalizedCropRect(
            x: leading,
            y: top,
            width: trailing - leading,
            height: bottom - top
        ).clamped()
    }

    func pixelRect(in size: CGSize) -> CGRect {
        let rect = clamped()
        return CGRect(
            x: (rect.x * Double(size.width)).rounded(.down),
            y: (rect.y * Double(size.height)).rounded(.down),
            width: max((rect.width * Double(size.width)).rounded(), 1),
            height: max((rect.height * Double(size.height)).rounded(), 1)
        )
    }
}

/// Which corner of the rectangle a drag is pulling.
enum CropCorner: CaseIterable, Hashable, Sendable {
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing
}

/// Cuts a region out of a photograph.
///
/// Non-destructive by construction: it reads bytes and returns new bytes. The
/// source is never opened for writing, which is what lets one outfit photo be
/// cropped a dozen times over and still be the photograph the user took.
///
/// The result is ordinary image data, so it goes into `GarmentImportService`
/// exactly like a photograph straight from the picker — background removal,
/// downscaling and thumbnailing all happen unchanged.
enum GarmentImageCropping {
    static func croppedData(from imageData: Data, region: NormalizedCropRect) -> Data? {
        guard region.isUsable, let image = UIImage(data: imageData) else { return nil }

        // Orientation is normalised first so a portrait mirror photo crops
        // where the user drew the rectangle rather than ninety degrees away.
        let upright = GarmentImageProcessing.normalizedOrientation(image)
        guard let source = upright.cgImage else { return nil }

        let pixelSize = CGSize(width: source.width, height: source.height)
        let bounds = CGRect(origin: .zero, size: pixelSize)
        let rect = region.pixelRect(in: pixelSize).intersection(bounds)
        guard !rect.isNull, rect.width >= 1, rect.height >= 1,
              let cropped = source.cropping(to: rect) else { return nil }

        return UIImage(cgImage: cropped, scale: 1, orientation: .up).pngData()
    }
}
