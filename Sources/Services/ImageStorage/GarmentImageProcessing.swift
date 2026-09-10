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
}
