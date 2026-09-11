import Foundation

/// How a bounded RIG source image maps into EdgeSAM's fixed 1024x1024
/// encoder input, so later steps (prompt coordinates, mask upscaling) can
/// invert the same transform without recomputing it.
///
/// `resizedWidth`/`resizedHeight` are the dimensions the source occupies
/// *inside* the 1024x1024 frame before padding — i.e. everything past them,
/// up to 1024 on each axis, is the padding region. `scale` is the single
/// uniform factor (`1024 / max(sourceWidth, sourceHeight)`) that maps a
/// source-pixel coordinate into that frame; because the padding is
/// bottom/right-only, the mapping is a pure scale with no offset. See
/// `docs/EDGESAM_PROVENANCE.md` for where each of these numbers comes from.
/// Kept in this file, which has no Core ML import, purely so it stays a
/// plain Sendable value type usable by pure tests.
struct EdgeSAMResizeMetadata: Sendable, Equatable {
    let sourceWidth: Int
    let sourceHeight: Int
    let resizedWidth: Int
    let resizedHeight: Int
    let scale: Double
}

/// The model-space↔RIG-space and mask-space↔source-space math behind
/// `EdgeSAMSegmenter`, deliberately factored out of every file that imports
/// Core ML.
///
/// Everything in `EdgeSAMSegmenter`/`EdgeSAMImageTensor`/
/// `EdgeSAMPromptTensor`/`EdgeSAMMaskConversion` that actually touches
/// `MLModel` or `MLMultiArray` cannot be unit tested without a real Apple
/// toolchain and the bundled model assets — there is no way around that in
/// this environment. But almost none of what makes that code *correct* is
/// actually about Core ML: it is arithmetic — the resize-and-pad scale
/// factor, the box-corner coordinate mapping, the bilinear resample used to
/// bring a 256x256 mask back to source resolution, and the
/// threshold-and-bounding-box step. Moving that arithmetic here, with no
/// Core ML import anywhere in this file, is what lets
/// `Tests/EdgeSAMGeometryTests.swift` exercise the actual logic
/// deterministically rather than leaving the whole adapter untested.
enum EdgeSAMGeometry {
    static let modelInputSize = 1024

    /// The scale-to-longest-side-1024 transform `ResizeLongestSide` +
    /// `Sam.preprocess()`'s pad step describe: aspect ratio preserved,
    /// padding (elsewhere) added bottom/right only. `nil` for a
    /// non-positive source size.
    static func resizeMetadata(sourceWidth: Int, sourceHeight: Int) -> EdgeSAMResizeMetadata? {
        guard sourceWidth > 0, sourceHeight > 0 else { return nil }
        let longestSide = max(sourceWidth, sourceHeight)
        let scale = Double(modelInputSize) / Double(longestSide)
        let resizedWidth = max(1, min(modelInputSize, Int((Double(sourceWidth) * scale).rounded())))
        let resizedHeight = max(1, min(modelInputSize, Int((Double(sourceHeight) * scale).rounded())))
        return EdgeSAMResizeMetadata(
            sourceWidth: sourceWidth, sourceHeight: sourceHeight,
            resizedWidth: resizedWidth, resizedHeight: resizedHeight, scale: scale
        )
    }

    /// A box prompt's two corners, in the padded 1024x1024 pixel space the
    /// encoder consumed. See `docs/EDGESAM_PROVENANCE.md` for why this is a
    /// pure scale with no offset.
    struct BoxPromptCoordinates: Equatable {
        let x0: Double
        let y0: Double
        let x1: Double
        let y1: Double
    }

    /// `nil` when `region` is not a usable rectangle — mirrors
    /// `NormalizedCropRect.isUsable`, since a caller with nothing sensible
    /// to prompt with should get nothing back rather than a NaN-laced box.
    static func boxPromptCoordinates(
        for region: NormalizedCropRect, resizeMetadata: EdgeSAMResizeMetadata
    ) -> BoxPromptCoordinates? {
        guard region.isUsable else { return nil }
        let clamped = region.clamped()
        guard clamped.isUsable else { return nil }
        let sourceWidth = Double(resizeMetadata.sourceWidth)
        let sourceHeight = Double(resizeMetadata.sourceHeight)
        return BoxPromptCoordinates(
            x0: clamped.x * sourceWidth * resizeMetadata.scale,
            y0: clamped.y * sourceHeight * resizeMetadata.scale,
            x1: (clamped.x + clamped.width) * sourceWidth * resizeMetadata.scale,
            y1: (clamped.y + clamped.height) * sourceHeight * resizeMetadata.scale
        )
    }

    /// A minimal `align_corners=False`-style bilinear resample — see
    /// `EdgeSAMMaskConversion`'s doc comment for why this exists instead of
    /// a tensor library call.
    static func bilinearResize(
        _ source: [Float], width: Int, height: Int, toWidth: Int, toHeight: Int
    ) -> [Float] {
        guard width > 0, height > 0, toWidth > 0, toHeight > 0 else { return [] }
        if width == toWidth, height == toHeight { return source }
        var destination = [Float](repeating: 0, count: toWidth * toHeight)
        let scaleX = Float(width) / Float(toWidth)
        let scaleY = Float(height) / Float(toHeight)
        for dy in 0..<toHeight {
            let sy = max(0, (Float(dy) + 0.5) * scaleY - 0.5)
            let y0 = min(height - 1, Int(sy))
            let y1 = min(height - 1, y0 + 1)
            let wy = sy - Float(y0)
            let destRow = dy * toWidth
            for dx in 0..<toWidth {
                let sx = max(0, (Float(dx) + 0.5) * scaleX - 0.5)
                let x0 = min(width - 1, Int(sx))
                let x1 = min(width - 1, x0 + 1)
                let wx = sx - Float(x0)

                let v00 = source[y0 * width + x0]
                let v01 = source[y0 * width + x1]
                let v10 = source[y1 * width + x0]
                let v11 = source[y1 * width + x1]
                let top = v00 * (1 - wx) + v01 * wx
                let bottom = v10 * (1 - wx) + v11 * wx
                destination[destRow + dx] = top * (1 - wy) + bottom * wy
            }
        }
        return destination
    }

    struct ThresholdResult: Equatable {
        let boundingRegion: NormalizedCropRect
        let minX: Int
        let minY: Int
        let maxX: Int
        let maxY: Int
    }

    /// Thresholds a `width`x`height` logit buffer at `threshold` (EdgeSAM's
    /// own `Sam.mask_threshold == 0.0`) and reports the bounding box of
    /// foreground pixels, both as pixel indices and as a RIG-normalized
    /// region. `nil` for an empty mask (nothing cleared the threshold) —
    /// an honest "nothing proposed", not an error.
    static func thresholdAndBoundingBox(
        _ values: [Float], width: Int, height: Int, threshold: Float = 0
    ) -> ThresholdResult? {
        guard width > 0, height > 0, values.count == width * height else { return nil }
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            let row = y * width
            for x in 0..<width where values[row + x] > threshold {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        let region = NormalizedCropRect(
            x: Double(minX) / Double(width),
            y: Double(minY) / Double(height),
            width: Double(maxX - minX + 1) / Double(width),
            height: Double(maxY - minY + 1) / Double(height)
        )
        return ThresholdResult(boundingRegion: region, minX: minX, minY: minY, maxX: maxX, maxY: maxY)
    }
}
