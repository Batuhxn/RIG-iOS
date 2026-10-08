import Foundation

/// Projection of a garment photo onto a template's front panel.
///
/// A plain planar projection maps the panel's bounding box to the whole photo, but a
/// cutout's garment rarely fills its rectangle (a skirt is a trapezoid, a tee has
/// sleeves), so the panel's edges landed on transparent, padded pixels and showed as
/// blocks of colour. Here the horizontal position stays planar over the panel, but each
/// photo row is read only *between that row's garment pixels*, so every panel vertex
/// samples real garment. (Matching the panel's own per-row outline as well was tried and
/// rejected: the outline jumps at the side seams and made stripes wave.)
enum GarmentPhotoMapping {
    /// - Parameters:
    ///   - mesh: a deformed template (front panel = `triangles`).
    ///   - photoSpans: for N rows of the photo, top to bottom, the garment's horizontal
    ///     extent in 0...1 (nil for an empty row).
    /// - Returns: UVs for every vertex; back-panel vertices keep a plain planar mapping.
    static func uvs(for mesh: AvatarMesh, photoSpans: [ClosedRange<Float>?]) -> [SIMD2<Float>] {
        let front = Set(mesh.triangles.map(Int.init))
        guard !front.isEmpty, let filled = fill(photoSpans) else { return mesh.uvs }
        let ys = front.map { mesh.positions[$0].y }
        guard let top = ys.max(), let bottom = ys.min(), top > bottom else { return mesh.uvs }

        // Horizontal position stays planar across the whole panel (straight prints stay
        // straight; a per-row panel outline jumps at the side seams and made stripes wave).
        let xs = front.map { mesh.positions[$0].x }
        guard let left = xs.min(), let right = xs.max(), right > left else { return mesh.uvs }
        let rows = filled.count
        let photoSmooth = AvatarFrontProjection.smooth(filled.map { (lo: $0.lowerBound, hi: $0.upperBound) }, radius: 3)

        var out = mesh.uvs
        for i in front {
            let p = mesh.positions[i]
            let v = (top - p.y) / (top - bottom)
            // Interpolate the photo's outline continuously between row centres.
            let f = min(max(v * Float(rows) - 0.5, 0), Float(rows - 1))
            let r0 = Int(f), r1 = min(r0 + 1, rows - 1), w = f - Float(r0)
            let qLo = photoSmooth[r0].lo * (1 - w) + photoSmooth[r1].lo * w
            let qHi = photoSmooth[r0].hi * (1 - w) + photoSmooth[r1].hi * w
            let t = min(max((p.x - left) / (right - left), 0), 1)
            out[i] = SIMD2(qLo + t * (qHi - qLo), min(max(v, 0), 1))
        }
        return out
    }

    /// Empty rows take the nearest non-empty row; nil when every row is empty.
    private static func fill(_ spans: [ClosedRange<Float>?]) -> [ClosedRange<Float>]? {
        fillPairs(spans.map { $0.map { (lo: $0.lowerBound, hi: $0.upperBound) } })?.map { $0.lo...max($0.lo, $0.hi) }
    }

    private static func fillPairs(_ rows: [(lo: Float, hi: Float)?]) -> [(lo: Float, hi: Float)]? {
        guard var last = rows.compactMap({ $0 }).first else { return nil }
        var out: [(lo: Float, hi: Float)] = []
        for r in rows {
            if let r { last = r }
            out.append(last)
        }
        return out
    }
}
