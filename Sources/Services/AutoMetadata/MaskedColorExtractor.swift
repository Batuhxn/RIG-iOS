import CoreGraphics
import Foundation
import UIKit

enum MaskedColorExtractor {
    struct Result: Hashable, Sendable {
        let primary: MetadataSuggestion<ColorFamily>
        let secondary: MetadataSuggestion<ColorFamily>?
    }

    static func extract(png: Data) -> Result? {
        guard let image = UIImage(data: png), let cg = GarmentImageProcessing.resized(image, maxDimension: 192).cgImage,
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let width = cg.width, height = cg.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return rendered ? extract(rgba: pixels) : nil
    }

    /// Premultiplied RGBA8 in sRGB. Transparent pixels and soft mask edges never vote.
    static func extract(rgba: [UInt8]) -> Result? {
        guard !rgba.isEmpty, rgba.count % 4 == 0 else { return nil }
        var counts: [ColorFamily: Int] = [:]
        var accepted = 0
        for offset in stride(from: 0, to: rgba.count, by: 4) {
            let alpha = Double(rgba[offset + 3])
            guard alpha >= 230 else { continue }
            let r = min(1, Double(rgba[offset]) / alpha)
            let g = min(1, Double(rgba[offset + 1]) / alpha)
            let b = min(1, Double(rgba[offset + 2]) / alpha)
            counts[family(r: r, g: g, b: b), default: 0] += 1
            accepted += 1
        }
        guard accepted >= 32 else { return nil }
        let ranked = counts.sorted { $0.value == $1.value ? $0.key.rawValue < $1.key.rawValue : $0.value > $1.value }
        guard let first = ranked.first else { return nil }
        let primary = MetadataSuggestion(value: first.key, score: Double(first.value) / Double(accepted))
        let secondary: MetadataSuggestion<ColorFamily>?
        if ranked.count > 1, Double(ranked[1].value) / Double(accepted) >= 0.15 {
            secondary = MetadataSuggestion(value: ranked[1].key, score: Double(ranked[1].value) / Double(accepted))
        } else { secondary = nil }
        return Result(primary: primary, secondary: secondary)
    }

    /// Fixed HSV boundaries: deterministic, but affected by lighting and mask quality.
    /// Metallic cannot be inferred from a pixel histogram and is manual only.
    private static func family(r: Double, g: Double, b: Double) -> ColorFamily {
        let maximum = max(r, max(g, b)), minimum = min(r, min(g, b)), delta = maximum - minimum
        let saturation = maximum == 0 ? 0 : delta / maximum
        if maximum < 0.16 { return .black }
        if saturation < 0.12 { return maximum > 0.85 ? .white : .gray }
        var hue: Double
        if maximum == r { hue = 60 * ((g - b) / delta).truncatingRemainder(dividingBy: 6) }
        else if maximum == g { hue = 60 * ((b - r) / delta + 2) }
        else { hue = 60 * ((r - g) / delta + 4) }
        if hue < 0 { hue += 360 }
        if hue >= 20 && hue < 65 && saturation < 0.4 && maximum > 0.6 { return .beige }
        if hue < 15 || hue >= 345 { return maximum < 0.5 ? .burgundy : (saturation < 0.5 ? .pink : .red) }
        if hue < 45 { return maximum < 0.65 ? .brown : .orange }
        if hue < 70 { return .yellow }
        if hue < 100 { return .olive }
        if hue < 175 { return .green }
        if hue < 260 { return maximum < 0.45 ? .navy : .blue }
        if hue < 310 { return .purple }
        return .pink
    }
}
