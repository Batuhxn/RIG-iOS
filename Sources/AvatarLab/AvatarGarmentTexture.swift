import CoreGraphics
import UIKit

/// Turns a garment cutout into something a shell can wear: transparent areas
/// (between sleeves and body in a flat photo) are filled with the garment's own
/// average colour, so the shell never shows holes.
enum AvatarGarmentTexture {
    /// A copy no larger than `maxSide` on its long edge, at scale 1.
    static func downscaled(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let scale = min(1, maxSide / max(image.size.width, image.size.height, 1))
        guard scale < 1 else { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }

    /// Draws `photo` warped into `bands` (see `AvatarFrontProjection.warpBands`).
    /// Each horizontal strip of the photo is first cropped to the garment's own
    /// opaque pixels in that strip, so transparent margins are never stretched
    /// onto the body.
    static func drawWarped(_ photo: UIImage, into bands: [CGRect]) {
        guard let cg = photo.cgImage, !bands.isEmpty else { return }
        let raw = opaqueSpans(of: cg, bands: bands.count)
        // Smooth the photo's outline the same way as the body's, skipping empty rows.
        let present = raw.compactMap { $0 }.map { (lo: $0.lowerBound, hi: $0.upperBound) }
        var smoothed = AvatarFrontProjection.smooth(present).makeIterator()
        let spans: [ClosedRange<CGFloat>?] = raw.map { span in
            guard span != nil, let s = smoothed.next() else { return nil }
            return s.lo...max(s.lo + 1, s.hi)
        }
        let rowHeight = CGFloat(cg.height) / CGFloat(bands.count)
        for (k, rect) in bands.enumerated() {
            guard let span = spans[k] else { continue }
            let source = CGRect(x: span.lowerBound, y: (CGFloat(k) * rowHeight).rounded(.down),
                                width: max(1, span.upperBound - span.lowerBound), height: rowHeight.rounded(.up) + 1)
            if let strip = cg.cropping(to: source) {
                UIImage(cgImage: strip).draw(in: rect.insetBy(dx: 0, dy: -0.5))
            }
        }
    }

    /// The garment's horizontal extent per row, normalised to 0...1, for
    /// `GarmentPhotoMapping`.
    static func photoSpans(of image: UIImage, rows: Int = 64) -> [ClosedRange<Float>?] {
        guard let cg = image.cgImage, cg.width > 0 else { return [] }
        let width = CGFloat(cg.width)
        return opaqueSpans(of: cg, bands: rows).map { span in
            span.map { Float($0.lowerBound / width)...Float(min($0.upperBound / width, 1)) }
        }
    }

    /// For each horizontal band of the image, the x range holding opaque pixels.
    static func opaqueSpans(of cg: CGImage, bands: Int) -> [ClosedRange<CGFloat>?] {
        let width = min(cg.width, 256)
        let height = max(bands * 4, min(cg.height, 512))
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return [ClosedRange<CGFloat>?](repeating: 0...CGFloat(cg.width), count: bands) }
        let toSource = CGFloat(cg.width) / CGFloat(width)
        return (0..<bands).map { band in
            var lo = Int.max, hi = Int.min
            // A bitmap context's memory starts at the image's top row, like band 0.
            for row in (band * height / bands)..<((band + 1) * height / bands) {
                for x in 0..<width where pixels[(row * width + x) * 4 + 3] > 40 {
                    lo = min(lo, x)
                    hi = max(hi, x)
                }
            }
            guard lo <= hi else { return nil }
            return CGFloat(lo) * toSource...CGFloat(hi + 1) * toSource
        }
    }

    static func prepare(_ image: UIImage) -> (image: UIImage, colour: UIColor) {
        let colour = dominantColour(of: image) ?? averageColour(of: image)
        let maxSide: CGFloat = 1024
        let scale = min(1, maxSide / max(image.size.width, image.size.height, 1))
        let size = CGSize(width: max(1, image.size.width * scale), height: max(1, image.size.height * scale))
        if let padded = padded(image, size: size) {
            return (padded, colour)
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let filled = UIGraphicsImageRenderer(size: size, format: format).image { context in
            colour.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return (filled, colour)
    }

    /// The cutout with its transparent pixels edge-padded (`AvatarTexturePadding`).
    private static func padded(_ image: UIImage, size: CGSize) -> UIImage? {
        guard let cg = image.cgImage else { return nil }
        let width = Int(size.width), height = Int(size.height)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: space, bitmapInfo: info) else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn, AvatarTexturePadding.pad(&pixels, width: width, height: height) else { return nil }
        let result: CGImage? = pixels.withUnsafeMutableBytes { buffer in
            CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                      bytesPerRow: width * 4, space: space, bitmapInfo: info)?.makeImage()
        }
        return result.map { UIImage(cgImage: $0) }
    }

    /// Alpha-weighted mean colour, from an 8×8 downsample.
    /// The fabric's main colour: the most frequent quantised colour among garment pixels
    /// near the outline (the outer 8% of each row), where prints, logos and plackets
    /// rarely are. A mean would mix a red-and-white stripe into pink. nil without pixels.
    static func dominantColour(of image: UIImage) -> UIColor? {
        guard let cg = image.cgImage else { return nil }
        let width = min(cg.width, 128), height = min(cg.height, 128)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        var bins: [Int: (count: Int, r: Int, g: Int, b: Int)] = [:]
        for y in 0..<height {
            let row = (0..<width).filter { pixels[(y * width + $0) * 4 + 3] > 200 }
            guard let lo = row.first, let hi = row.last else { continue }
            let margin = max(1, (hi - lo) * 8 / 100)
            for x in row where x <= lo + margin || x >= hi - margin {
                let i = (y * width + x) * 4
                let r = Int(pixels[i]), g = Int(pixels[i + 1]), b = Int(pixels[i + 2])
                let key = (r >> 4) << 8 | (g >> 4) << 4 | (b >> 4)
                let old = bins[key] ?? (0, 0, 0, 0)
                bins[key] = (old.count + 1, old.r + r, old.g + g, old.b + b)
            }
        }
        guard let best = bins.values.max(by: { $0.count < $1.count }), best.count > 0 else { return nil }
        let n = CGFloat(best.count) * 255
        return UIColor(red: CGFloat(best.r) / n, green: CGFloat(best.g) / n, blue: CGFloat(best.b) / n, alpha: 1)
    }

    static func averageColour(of image: UIImage) -> UIColor {
        guard let cg = image.cgImage else { return .gray }
        let side = 8
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return .gray }
        var r = 0.0, g = 0.0, b = 0.0, a = 0.0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            r += Double(pixels[i]); g += Double(pixels[i + 1]); b += Double(pixels[i + 2]); a += Double(pixels[i + 3])
        }
        guard a > 0 else { return .gray }
        // Premultiplied: the sums of colour over the sum of alpha give the mean.
        return UIColor(red: r / a, green: g / a, blue: b / a, alpha: 1)
    }
}
