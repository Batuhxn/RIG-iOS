import Foundation

/// Edge padding for garment textures. A cutout is transparent around the
/// garment and in its gaps (between a sleeve and the body); projected onto a
/// 3D shell, those pixels used to be filled with one average colour, which
/// showed as flat skin-like patches at the sides. Instead every transparent
/// pixel takes the colour of the nearest garment pixel in its row (or, in rows
/// with no garment at all, the nearest row that has one), so stripes and
/// colours simply continue to the shell's edge.
enum AvatarTexturePadding {
    /// Pads premultiplied RGBA8 pixels in place and makes them opaque.
    /// Returns false when the image has no garment pixel at all.
    @discardableResult
    static func pad(_ rgba: inout [UInt8], width: Int, height: Int, opaqueAlpha: UInt8 = 128) -> Bool {
        guard width > 0, height > 0, rgba.count >= width * height * 4 else { return false }
        var rowHasGarment = [Bool](repeating: false, count: height)
        for y in 0..<height {
            var opaque: [Int] = []
            for x in 0..<width where rgba[(y * width + x) * 4 + 3] >= opaqueAlpha {
                opaque.append(x)
                unpremultiply(&rgba, at: (y * width + x) * 4)
            }
            guard !opaque.isEmpty else { continue }
            rowHasGarment[y] = true
            // Each transparent pixel copies the nearest opaque pixel in the row.
            var next = 0
            for x in 0..<width where rgba[(y * width + x) * 4 + 3] < opaqueAlpha {
                while next + 1 < opaque.count, opaque[next + 1] <= x { next += 1 }
                var source = opaque[next]
                if next + 1 < opaque.count, abs(opaque[next + 1] - x) < abs(source - x) { source = opaque[next + 1] }
                copy(&rgba, from: (y * width + source) * 4, to: (y * width + x) * 4)
            }
        }
        guard let firstRow = rowHasGarment.firstIndex(of: true) else { return false }
        var lastGood = firstRow
        for y in 0..<height {
            if rowHasGarment[y] {
                lastGood = y
            } else {
                let source = y < firstRow ? firstRow : lastGood
                for x in 0..<width { copy(&rgba, from: (source * width + x) * 4, to: (y * width + x) * 4) }
            }
        }
        for i in stride(from: 3, to: width * height * 4, by: 4) { rgba[i] = 255 }
        return true
    }

    private static func unpremultiply(_ p: inout [UInt8], at i: Int) {
        let a = Int(p[i + 3])
        guard a > 0, a < 255 else { return }
        for k in 0..<3 { p[i + k] = UInt8(min(255, Int(p[i + k]) * 255 / a)) }
        p[i + 3] = 255
    }

    private static func copy(_ p: inout [UInt8], from source: Int, to target: Int) {
        p[target] = p[source]
        p[target + 1] = p[source + 1]
        p[target + 2] = p[source + 2]
        p[target + 3] = 255
    }
}
