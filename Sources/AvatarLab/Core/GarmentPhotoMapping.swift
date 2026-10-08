import Foundation

/// Silhouette-matched projection of a garment photo onto a template's front panel.
///
/// A plain planar projection maps the panel's bounding box to the whole photo, but a
/// cutout's garment rarely fills its rectangle (a skirt is a trapezoid, a tee has
/// sleeves), so the panel's edges landed on transparent, padded pixels and showed as
/// blocks of colour. Here each horizontal row of the panel maps to the same row of the
/// photo *between that row's garment pixels*: the photo's outline is stretched onto
/// the panel's outline, row by row, and every panel vertex samples real garment.
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

        // The panel's outline: min/max x per row, over the same number of rows.
        let rows = filled.count
        var panel = [(lo: Float, hi: Float)?](repeating: nil, count: rows)
        for i in front {
            let p = mesh.positions[i]
            let r = row(of: p.y, top: top, bottom: bottom, rows: rows)
            panel[r] = panel[r].map { (min($0.lo, p.x), max($0.hi, p.x)) } ?? (p.x, p.x)
        }
        guard let panelRows = fillPairs(panel) else { return mesh.uvs }
        let panelSmooth = AvatarFrontProjection.smooth(panelRows)
        let photoSmooth = AvatarFrontProjection.smooth(filled.map { (lo: $0.lowerBound, hi: $0.upperBound) })

        var out = mesh.uvs
        for i in front {
            let p = mesh.positions[i]
            let v = (top - p.y) / (top - bottom)
            // Interpolate both outlines continuously between row centres.
            let f = min(max(v * Float(rows) - 0.5, 0), Float(rows - 1))
            let r0 = Int(f), r1 = min(r0 + 1, rows - 1), w = f - Float(r0)
            let pLo = panelSmooth[r0].lo * (1 - w) + panelSmooth[r1].lo * w
            let pHi = panelSmooth[r0].hi * (1 - w) + panelSmooth[r1].hi * w
            let qLo = photoSmooth[r0].lo * (1 - w) + photoSmooth[r1].lo * w
            let qHi = photoSmooth[r0].hi * (1 - w) + photoSmooth[r1].hi * w
            let t = pHi > pLo ? min(max((p.x - pLo) / (pHi - pLo), 0), 1) : 0.5
            out[i] = SIMD2(qLo + t * (qHi - qLo), min(max(v, 0), 1))
        }
        return out
    }

    private static func row(of y: Float, top: Float, bottom: Float, rows: Int) -> Int {
        min(rows - 1, max(0, Int((top - y) / (top - bottom) * Float(rows))))
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
