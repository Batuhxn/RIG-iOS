import CoreGraphics
import CoreML
import Foundation
import UIKit

/// Converts the decoder's raw `scores`/`masks` tensors into a
/// `SegmentationMaskResult` expressed entirely in RIG source-space.
///
/// This file owns the whole trip back out of model-space: picking the best
/// of the four mask candidates, undoing the encoder's resize-and-pad
/// (resampling and thresholding delegated to `EdgeSAMGeometry`, which
/// carries the actual `Sam.postprocess_masks`-equivalent math and is what
/// `Tests/EdgeSAMGeometryTests.swift` exercises), and compositing a hard
/// alpha cutout — see `docs/EDGESAM_PROVENANCE.md`, "Reading the outputs".
/// The bilinear resample's `align_corners=False` sample-position formula
/// reproduces PyTorch's own, but is **not** claimed to be bit-exact with
/// `torch.nn.functional.interpolate` — see the "known limitations" note
/// this integration's final report carries.
enum EdgeSAMMaskConversion {
    static let decoderMaskSize = 256
    static let candidateCount = 4

    struct Converted {
        let cutoutData: Data
        let boundingRegion: NormalizedCropRect
        let qualityScore: Double
    }

    /// `sourceImage` must be the exact upright image `resizeMetadata` was
    /// computed from — `EdgeSAMSegmenter` caches the two together at
    /// `encodeSource` time for this reason.
    static func convert(
        masks: MLMultiArray,
        scores: MLMultiArray,
        resizeMetadata: EdgeSAMResizeMetadata,
        sourceImage: CGImage
    ) -> Converted? {
        guard masks.count == candidateCount * decoderMaskSize * decoderMaskSize,
              scores.count == candidateCount,
              // v0.4 Slice 2.1 repair: read through `strides`, not a flat
              // linear index — `masks`/`scores` are Core ML *output*
              // arrays, and Core ML does not guarantee their memory is
              // contiguous for their declared shape. See
              // `EdgeSAMMultiArraySupport`'s doc comment and
              // `docs/EDGESAM_PROVENANCE.md`, "Regression: the deep-copy
              // strides bug".
              let scoreValues = EdgeSAMMultiArraySupport.floatElements(of: scores),
              let maskValues = EdgeSAMMultiArraySupport.floatElements(of: masks)
        else { return nil }

        var bestIndex = 0
        var bestScore = scoreValues[0]
        for i in 1..<candidateCount where scoreValues[i] > bestScore {
            bestScore = scoreValues[i]
            bestIndex = i
        }

        let plane = decoderMaskSize * decoderMaskSize
        let base = bestIndex * plane
        let logits = Array(maskValues[base..<(base + plane)])

        // 1) 256x256 -> the encoder's own 1024x1024 frame.
        let upscaled = EdgeSAMGeometry.bilinearResize(
            logits, width: decoderMaskSize, height: decoderMaskSize,
            toWidth: EdgeSAMGeometry.modelInputSize, toHeight: EdgeSAMGeometry.modelInputSize
        )

        // 2) Crop away the bottom/right padding, back down to the
        //    resized-but-unpadded size the source actually occupied.
        let resizedW = resizeMetadata.resizedWidth
        let resizedH = resizeMetadata.resizedHeight
        guard resizedW > 0, resizedH > 0 else { return nil }
        var cropped = [Float](repeating: 0, count: resizedW * resizedH)
        for y in 0..<resizedH {
            let srcRow = y * EdgeSAMGeometry.modelInputSize
            let dstRow = y * resizedW
            for x in 0..<resizedW {
                cropped[dstRow + x] = upscaled[srcRow + x]
            }
        }

        // 3) Back up to the bounded source's own pixel size.
        let sourceW = resizeMetadata.sourceWidth
        let sourceH = resizeMetadata.sourceHeight
        guard sourceW > 0, sourceH > 0, sourceImage.width == sourceW, sourceImage.height == sourceH else { return nil }
        let full = EdgeSAMGeometry.bilinearResize(cropped, width: resizedW, height: resizedH, toWidth: sourceW, toHeight: sourceH)

        // 4) Threshold (`Sam.mask_threshold == 0.0`) and find the mask's
        //    bounding box. An empty mask is an honest "nothing proposed",
        //    not a crash.
        guard let thresholded = EdgeSAMGeometry.thresholdAndBoundingBox(full, width: sourceW, height: sourceH) else {
            return nil
        }

        guard let cutout = compositeCutout(
            sourceImage: sourceImage, values: full,
            sourceWidth: sourceW, sourceHeight: sourceH,
            minX: thresholded.minX, minY: thresholded.minY, maxX: thresholded.maxX, maxY: thresholded.maxY
        ) else { return nil }

        return Converted(cutoutData: cutout, boundingRegion: thresholded.boundingRegion, qualityScore: Double(bestScore))
    }

    /// Zeroes alpha (and colour, to keep premultiplied data valid) outside
    /// the mask, then crops to its bounding box — a hard cutout, the same
    /// contract `GarmentBackgroundRemoving` results already carry.
    private static func compositeCutout(
        sourceImage: CGImage, values: [Float],
        sourceWidth: Int, sourceHeight: Int,
        minX: Int, minY: Int, maxX: Int, maxY: Int
    ) -> Data? {
        guard let context = CGContext(
            data: nil, width: sourceWidth, height: sourceHeight,
            bitsPerComponent: 8, bytesPerRow: sourceWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(sourceImage, in: CGRect(x: 0, y: 0, width: sourceWidth, height: sourceHeight))
        guard let data = context.data else { return nil }
        let pointer = data.bindMemory(to: UInt8.self, capacity: sourceWidth * sourceHeight * 4)
        for y in 0..<sourceHeight {
            let row = y * sourceWidth
            for x in 0..<sourceWidth where values[row + x] <= 0 {
                let i = (row + x) * 4
                pointer[i] = 0
                pointer[i + 1] = 0
                pointer[i + 2] = 0
                pointer[i + 3] = 0
            }
        }
        guard let masked = context.makeImage() else { return nil }
        let cropRect = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        guard let croppedImage = masked.cropping(to: cropRect) else { return nil }
        return UIImage(cgImage: croppedImage, scale: 1, orientation: .up).pngData()
    }
}
