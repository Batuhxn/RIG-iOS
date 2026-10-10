import Foundation

/// Projection of a garment photo onto a template's front panel.
///
/// A plain planar projection maps the panel's bounding box to the whole photo, but a
/// cutout's garment rarely fills its rectangle (a skirt is a trapezoid, a tee has
/// sleeves), so the panel's edges landed on transparent, padded pixels and showed as
/// blocks of colour. Here each photo row is read only *between that row's garment
/// pixels*, so every panel vertex samples real garment. (Matching the panel's own
/// per-row outline as well was tried and rejected: the outline jumps at the side seams
/// and made stripes wave.)
///
/// Across a row, the position is either planar (x across the panel: tops and trousers,
/// whose sleeves and legs sit off the body's axis) or angular around the garment's own
/// vertical axis (`wrapsAround`: skirts and dresses). On a flared skirt a line of
/// constant x is a curve (a hyperbola on the cone), so planar mapping bent vertical
/// stripes into arcs at three-quarter views; a line of constant angle runs straight
/// from waist to hem, as a stripe sewn into the fabric does.
enum GarmentPhotoMapping {
    /// - Parameters:
    ///   - mesh: a deformed template (front panel = `triangles`).
    ///   - photoSpans: for N rows of the photo, top to bottom, the garment's horizontal
    ///     extent in 0...1 (nil for an empty row).
    ///   - wrapsAround: angular rather than planar position across a row.
    /// - Returns: UVs for every vertex; back-panel vertices keep a plain planar mapping.
    static func uvs(for mesh: AvatarMesh, photoSpans: [ClosedRange<Float>?], wrapsAround: Bool = false) -> [SIMD2<Float>] {
        let front = Set(mesh.triangles.map(Int.init))
        guard !front.isEmpty, let filled = fill(photoSpans) else { return mesh.uvs }
        let ys = front.map { mesh.positions[$0].y }
        guard let top = ys.max(), let bottom = ys.min(), top > bottom else { return mesh.uvs }

        let across: (SIMD3<Float>) -> Float
        if wrapsAround, let wrap = angularAcross(mesh, front: front) {
            across = wrap
        } else {
            // Planar across the whole panel (straight prints stay straight from the front).
            let xs = front.map { mesh.positions[$0].x }
            guard let left = xs.min(), let right = xs.max(), right > left else { return mesh.uvs }
            across = { p in (p.x - left) / (right - left) }
        }
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
            let t = min(max(across(p), 0), 1)
            out[i] = SIMD2(qLo + t * (qHi - qLo), min(max(v, 0), 1))
        }
        return out
    }

    /// Angle around the garment's vertical axis, scaled so the front panel spans 0...1.
    /// The axis at each height is the centre of the whole garment's cross-section there
    /// (both panels), smoothed over height; nil when the garment is too thin to have one.
    static func angularAcross(_ mesh: AvatarMesh, front: Set<Int>) -> ((SIMD3<Float>) -> Float)? {
        guard let lowest = mesh.positions.map(\.y).min(), let highest = mesh.positions.map(\.y).max(), highest > lowest else { return nil }
        let bins = 24
        var lo = [SIMD2<Float>](repeating: SIMD2(.infinity, .infinity), count: bins)
        var hi = [SIMD2<Float>](repeating: SIMD2(-.infinity, -.infinity), count: bins)
        func bin(_ y: Float) -> Float { min(max((y - lowest) / (highest - lowest) * Float(bins) - 0.5, 0), Float(bins - 1)) }
        for p in mesh.positions {
            let b = Int(bin(p.y).rounded())
            lo[b] = pointwiseMin(lo[b], SIMD2(p.x, p.z))
            hi[b] = pointwiseMax(hi[b], SIMD2(p.x, p.z))
        }
        var centres: [SIMD2<Float>?] = (0..<bins).map { lo[$0].x.isFinite && hi[$0].x.isFinite ? (lo[$0] + hi[$0]) / 2 : nil }
        // Empty bins take the nearest filled one; then a light smoothing along the height.
        guard let firstFilled = centres.compactMap({ $0 }).first else { return nil }
        var last = firstFilled
        for b in 0..<bins { if let c = centres[b] { last = c } else { centres[b] = last } }
        let raw = centres.map { $0 ?? firstFilled }
        let axis = raw.indices.map { b -> SIMD2<Float> in
            let window = raw[max(0, b - 2)...min(bins - 1, b + 2)]
            return window.reduce(.zero, +) / Float(window.count)
        }
        func centre(_ y: Float) -> SIMD2<Float> {
            let f = bin(y)
            let b0 = Int(f), b1 = min(b0 + 1, bins - 1), w = f - Float(b0)
            return axis[b0] * (1 - w) + axis[b1] * w
        }
        func angle(_ p: SIMD3<Float>) -> Float {
            let c = centre(p.y)
            return atan2(p.x - c.x, p.z - c.y)
        }
        // The panel's angular half-width: a high percentile, so one stray vertex at the
        // side seam does not squeeze the whole print.
        let spread = front.map { abs(angle(mesh.positions[$0])) }.sorted()
        guard !spread.isEmpty else { return nil }
        let half = spread[min(spread.count - 1, Int(Float(spread.count - 1) * 0.98))]
        guard half > 0.1 else { return nil }
        return { p in (angle(p) + half) / (2 * half) }
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

extension AvatarGarmentCut {
    /// Skirts and dresses hang around one vertical axis, so their photo wraps by angle;
    /// tops (sleeves) and trousers (two legs) keep the planar mapping.
    var photoWrapsAround: Bool {
        switch self {
        case .skirt, .dress: return true
        default: return false
        }
    }
}
