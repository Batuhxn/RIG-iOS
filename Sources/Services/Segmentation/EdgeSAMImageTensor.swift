import CoreGraphics
import CoreML
import Foundation
import UIKit

/// Builds the exact preprocessed input tensor EdgeSAM's encoder expects.
///
/// This is the only place in RIG that performs the resize/pad/normalize
/// EdgeSAM's own `Sam.preprocess()` does — see
/// `docs/EDGESAM_PROVENANCE.md`, "Encoder interface", for the source this
/// was verified against. Nothing here is Vision or UIKit-idiomatic image
/// processing; it exists solely to match one specific model's contract.
enum EdgeSAMImageTensor {
    static let modelInputSize = EdgeSAMGeometry.modelInputSize
    /// RGB order, matching `Sam`'s `pixel_mean`/`pixel_std` and
    /// `SamPredictor`'s default `image_format = "RGB"`.
    static let pixelMean: [Float] = [123.675, 116.28, 103.53]
    static let pixelStd: [Float] = [58.395, 57.12, 57.375]

    struct Prepared {
        let tensor: MLMultiArray
        let resizeMetadata: EdgeSAMResizeMetadata
    }

    /// `image` must already be in the `.up` orientation — callers are
    /// expected to have normalized it once, the same way
    /// `GarmentImageCropping` does, rather than have every consumer of a
    /// photo repeat that step.
    static func preprocessed(_ image: UIImage) -> Prepared? {
        guard let cgImage = image.cgImage, cgImage.width > 0, cgImage.height > 0,
              let metadata = EdgeSAMGeometry.resizeMetadata(sourceWidth: cgImage.width, sourceHeight: cgImage.height)
        else { return nil }
        let resizedWidth = metadata.resizedWidth
        let resizedHeight = metadata.resizedHeight

        guard let pixels = rgba8888(cgImage: cgImage, width: resizedWidth, height: resizedHeight) else { return nil }
        guard let tensor = try? MLMultiArray(
            shape: [1, 3, NSNumber(value: modelInputSize), NSNumber(value: modelInputSize)],
            dataType: .float32
        ) else { return nil }

        let pointer = tensor.dataPointer.bindMemory(to: Float32.self, capacity: tensor.count)
        // The padding region must be exactly 0.0 in *normalized* space:
        // `Sam.preprocess()` normalizes first, then pads the already-
        // normalized tensor with zeros — not the other way round. Zeroing
        // the whole buffer up front and only writing the resized region
        // below reproduces that without a second pass.
        pointer.update(repeating: 0, count: tensor.count)

        let planeStride = modelInputSize * modelInputSize
        pixels.withUnsafeBufferPointer { rgba in
            for y in 0..<resizedHeight {
                let srcRow = y * resizedWidth * 4
                let destRow = y * modelInputSize
                for x in 0..<resizedWidth {
                    let i = srcRow + x * 4
                    let r = (Float(rgba[i]) - pixelMean[0]) / pixelStd[0]
                    let g = (Float(rgba[i + 1]) - pixelMean[1]) / pixelStd[1]
                    let b = (Float(rgba[i + 2]) - pixelMean[2]) / pixelStd[2]
                    let dest = destRow + x
                    pointer[dest] = r
                    pointer[planeStride + dest] = g
                    pointer[2 * planeStride + dest] = b
                }
            }
        }

        return Prepared(tensor: tensor, resizeMetadata: metadata)
    }

    /// Draws `cgImage` into a `width`x`height` RGBA8888 buffer, letting Core
    /// Graphics do the resampling for this (comparatively cheap) downscale
    /// to at most 1024px — nothing here reimplements image interpolation.
    private static func rgba8888(cgImage: CGImage, width: Int, height: Int) -> [UInt8]? {
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let drew: Bool = buffer.withUnsafeMutableBytes { rawBuffer in
            guard let context = CGContext(
                data: rawBuffer.baseAddress,
                width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: colorSpace, bitmapInfo: bitmapInfo
            ) else { return false }
            context.interpolationQuality = .high
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drew ? buffer : nil
    }
}
