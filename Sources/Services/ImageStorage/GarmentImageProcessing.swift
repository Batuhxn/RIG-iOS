import Foundation
import UIKit

/// Image size policy for RIG.
///
/// Photographs from a modern iPhone are 12 MP and several megabytes each. A
/// wardrobe of two hundred garments at full resolution would be gigabytes of
/// user storage for no benefit, since nothing here is ever printed or zoomed
/// beyond screen size. The three ceilings below are the whole policy:
///
/// - **1600 px** for the retained original. Enough to reprocess a garment later
///   with a better background remover without re-photographing it.
/// - **1200 px** for the cutout. This is what look composition draws.
/// - **400 px** for the thumbnail. Comfortably above a grid cell on a 3x screen.
///
/// Longest side is what is bounded; aspect ratio is preserved and images are
/// never upscaled.
enum GarmentImageProcessing {
    static let originalMaxDimension: CGFloat = 1600
    static let cutoutMaxDimension: CGFloat = 1200
    static let thumbnailMaxDimension: CGFloat = 400
    static let jpegCompressionQuality: CGFloat = 0.85

    /// Redraws into the `.up` orientation so downstream code never has to carry
    /// an EXIF orientation around.
    static func normalizedOrientation(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    static func resized(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let longestSide = max(image.size.width, image.size.height)
        guard longestSide > maxDimension, longestSide > 0 else {
            return normalizedOrientation(image)
        }
        let scale = maxDimension / longestSide
        let target = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())

        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    /// JPEG for opaque photographs. Alpha is not preserved, so this is only ever
    /// used for the imported original.
    static func jpegData(from imageData: Data, maxDimension: CGFloat) -> Data? {
        guard let image = UIImage(data: imageData) else { return nil }
        return resized(image, maxDimension: maxDimension).jpegData(compressionQuality: jpegCompressionQuality)
    }

    /// PNG for anything that may carry transparency.
    static func pngData(from imageData: Data, maxDimension: CGFloat) -> Data? {
        guard let image = UIImage(data: imageData) else { return nil }
        return resized(image, maxDimension: maxDimension).pngData()
    }

    /// Crops to a rectangle expressed in unit coordinates of the source image,
    /// returning freshly encoded JPEG bytes.
    ///
    /// This is deliberately non-destructive and deliberately upstream: it takes
    /// source bytes and returns new bytes, touching nothing on disk. The import
    /// pipeline below it is unchanged and unaware — it receives whichever bytes
    /// the user chose, and background removal therefore operates on the crop
    /// for free, because the crop *is* the original as far as the pipeline is
    /// concerned.
    ///
    /// Returns nil when the image cannot be read or the rectangle does not
    /// describe at least one pixel; callers fall back to the uncropped data,
    /// because a crop that cannot be computed must never lose the photograph.
    static func croppedJPEGData(from imageData: Data, unitRect: CGRect) -> Data? {
        guard let source = UIImage(data: imageData) else { return nil }
        let image = normalizedOrientation(source)

        let clamped = CGRect(
            x: max(0, min(1, unitRect.minX)),
            y: max(0, min(1, unitRect.minY)),
            width: max(0, min(1, unitRect.width)),
            height: max(0, min(1, unitRect.height))
        )
        guard clamped.width > 0, clamped.height > 0 else { return nil }

        let pixels = CGRect(
            x: (clamped.minX * image.size.width).rounded(.down),
            y: (clamped.minY * image.size.height).rounded(.down),
            width: (clamped.width * image.size.width).rounded(),
            height: (clamped.height * image.size.height).rounded()
        )
        guard pixels.width >= 1, pixels.height >= 1 else { return nil }

        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: pixels.size, format: format)
        let cropped = renderer.image { _ in
            image.draw(at: CGPoint(x: -pixels.minX, y: -pixels.minY))
        }
        return cropped.jpegData(compressionQuality: jpegCompressionQuality)
    }
}
