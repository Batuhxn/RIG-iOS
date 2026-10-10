import Foundation

/// Builds everything the stage draws for one body shape and outfit: the morphed body,
/// minus the triangles garments cover, and one mesh per garment. Cuts with a Garment
/// Engine template use it; the others fall back to the body-hugging shells.
struct AvatarOutfitBuilder: Sendable {
    let asset: AvatarBodyAsset
    let shells: AvatarGarmentShellBuilder
    let templates: GarmentTemplateLibrary?

    init(asset: AvatarBodyAsset, templates: GarmentTemplateLibrary?) {
        self.asset = asset
        self.shells = AvatarGarmentShellBuilder(asset: asset)
        self.templates = templates
    }

    func template(for cut: AvatarGarmentCut) -> GarmentTemplate? {
        cut.templateName.flatMap { templates?.templates[$0] }
    }

    /// - Returns: `body` without the skin garments cover (for 3D), `bareBody` complete
    ///   (for the 2D overlay, which draws no 3D garments), and the garments; nil once the
    ///   calling task is cancelled.
    func build(shape: AvatarBodyShape, cuts: [AvatarGarmentCut]) -> (body: AvatarMesh, bareBody: AvatarMesh, garments: [AvatarMesh])? {
        let engine = AvatarMorphEngine(asset: asset)
        let positions = engine.positions(for: shape)
        let bodyTriangles = asset.submeshes["body"] ?? []
        let bodyNormals = AvatarMorphEngine.normals(positions: positions, triangles: bodyTriangles)
        guard !Task.isCancelled else { return nil }

        var hidden = Set<Int32>()
        var garments: [AvatarMesh] = []
        let fallback = shells.shells(for: cuts, positions: positions)
        for (cut, shell) in zip(cuts, fallback) {
            if let template = template(for: cut) {
                garments.append(GarmentDeformer.mesh(for: template, positions: positions, bodyNormals: bodyNormals))
                hidden.formUnion(template.hiddenBodyTriangles)
            } else {
                garments.append(shell)
            }
        }
        Self.layer(&garments, cuts: cuts)
        guard !Task.isCancelled else { return nil }
        var visible: [UInt32] = []
        visible.reserveCapacity(bodyTriangles.count)
        var t = 0
        while t + 2 < bodyTriangles.count {
            if !hidden.contains(Int32(t / 3)) { visible += bodyTriangles[t..<(t + 3)] }
            t += 3
        }
        let body = AvatarMorphEngine.compact(triangles: visible, positions: positions, offset: 0)
        let bare = hidden.isEmpty ? body : AvatarMorphEngine.compact(triangles: bodyTriangles, positions: positions, offset: 0)
        return (body, bare, garments)
    }

    /// Layer guard: every garment sits at least `gap` outside each garment on a lower layer
    /// (a body-hugging coat shell used to pass through a relaxed tee; Codex review).
    /// Vertices are pushed out along their own normal, measured against the closest point
    /// on the inner garment's triangles within `reach` (not only its vertices, which
    /// missed the inside of large triangles; Atelier review). Normals of a moved garment
    /// are recomputed from its final positions.
    static func layer(_ garments: inout [AvatarMesh], cuts: [AvatarGarmentCut], gap: Float = 0.006, reach: Float = 0.06) {
        let order = cuts.indices.sorted { cuts[$0].layer < cuts[$1].layer }
        func yRange(_ m: AvatarMesh) -> ClosedRange<Float> {
            let ys = m.positions.map(\.y)
            return (ys.min() ?? 0)...(ys.max() ?? 0)
        }
        for (rank, outer) in order.enumerated() {
            var mesh = garments[outer]
            var movedAny = false
            for inner in order[..<rank] where cuts[inner].layer < cuts[outer].layer {
                // Garments that cannot touch (shoes and a tee) are skipped.
                guard yRange(garments[inner]).overlaps(yRange(garments[outer])) else { continue }
                let surface = TriangleGrid(mesh: garments[inner], cell: 0.03)
                // A push can bring a different inner triangle into play; a few passes settle it.
                for _ in 0..<6 {
                    var moved = false
                    for k in mesh.positions.indices {
                        let p = mesh.positions[k]
                        guard let hit = surface.closest(to: p, within: reach) else { continue }
                        let n = mesh.normals[k]
                        // Height above the inner surface, along the inner surface's normal.
                        let depth = ((p - hit.point) * hit.normal).sum()
                        if depth < gap {
                            // Moving along our own normal, which may be tilted against theirs.
                            let along = max((n * hit.normal).sum(), 0.25)
                            mesh.positions[k] = p + ((gap - depth) / along) * n
                            moved = true
                        }
                    }
                    if !moved { break }
                    movedAny = true
                }
            }
            if movedAny { mesh.normals = Self.recomputedNormals(mesh) }
            garments[outer] = mesh
        }
    }

    /// Area-weighted normals of the final positions over both triangle groups. Vertices at
    /// the same position (a template's seam duplicates) share one normal, and the result
    /// keeps the mesh's previous outward orientation.
    static func recomputedNormals(_ mesh: AvatarMesh) -> [SIMD3<Float>] {
        var slot: [SIMD3<UInt32>: Int] = [:]
        var key = [Int](repeating: 0, count: mesh.positions.count)
        for (k, p) in mesh.positions.enumerated() {
            let bits = SIMD3(p.x.bitPattern, p.y.bitPattern, p.z.bitPattern)
            if let s = slot[bits] {
                key[k] = s
            } else {
                key[k] = slot.count
                slot[bits] = slot.count
            }
        }
        var acc = [SIMD3<Float>](repeating: .zero, count: slot.count)
        for list in [mesh.triangles, mesh.backTriangles] {
            var t = 0
            while t + 2 < list.count {
                let a = Int(list[t]), b = Int(list[t + 1]), c = Int(list[t + 2])
                let fn = avatarCross(mesh.positions[b] - mesh.positions[a], mesh.positions[c] - mesh.positions[a])
                acc[key[a]] += fn
                acc[key[b]] += fn
                acc[key[c]] += fn
                t += 3
            }
        }
        var normals = mesh.positions.indices.map { k -> SIMD3<Float> in
            let n = acc[key[k]]
            let length = (n * n).sum().squareRoot()
            return length > 1e-12 ? n / length : mesh.normals[k]
        }
        var agreement: Float = 0
        for k in normals.indices { agreement += (normals[k] * mesh.normals[k]).sum() }
        if agreement < 0 { normals = normals.map { -$0 } }
        return normals
    }
}

/// Triangles of a mesh bucketed by the grid cells their bounds touch, for closest-point
/// queries against a surface (the layer guard).
struct TriangleGrid {
    private var cells: [SIMD3<Int32>: [Int32]] = [:]
    private let positions: [SIMD3<Float>]
    private let normals: [SIMD3<Float>]
    private let corners: [SIMD3<Int32>]
    let cell: Float

    init(mesh: AvatarMesh, cell: Float) {
        self.cell = cell
        positions = mesh.positions
        normals = mesh.normals
        let all = mesh.triangles + mesh.backTriangles
        var corners: [SIMD3<Int32>] = []
        corners.reserveCapacity(all.count / 3)
        var t = 0
        while t + 2 < all.count {
            corners.append(SIMD3(Int32(all[t]), Int32(all[t + 1]), Int32(all[t + 2])))
            t += 3
        }
        self.corners = corners
        for (index, tri) in corners.enumerated() {
            let a = positions[Int(tri.x)], b = positions[Int(tri.y)], c = positions[Int(tri.z)]
            let lo = Self.key(pointwiseMin(a, pointwiseMin(b, c)), cell), hi = Self.key(pointwiseMax(a, pointwiseMax(b, c)), cell)
            for x in lo.x...hi.x {
                for y in lo.y...hi.y {
                    for z in lo.z...hi.z { cells[SIMD3(x, y, z), default: []].append(Int32(index)) }
                }
            }
        }
    }

    private static func key(_ p: SIMD3<Float>, _ cell: Float) -> SIMD3<Int32> {
        SIMD3(Int32((p.x / cell).rounded(.down)), Int32((p.y / cell).rounded(.down)), Int32((p.z / cell).rounded(.down)))
    }

    /// The closest point on any triangle within `radius`, with that triangle's normal
    /// oriented like the mesh's vertex normals there.
    func closest(to p: SIMD3<Float>, within radius: Float) -> (point: SIMD3<Float>, normal: SIMD3<Float>)? {
        let lo = Self.key(p - radius, cell), hi = Self.key(p + radius, cell)
        var best: (point: SIMD3<Float>, normal: SIMD3<Float>)?
        var bestDistance = radius * radius
        var seen = Set<Int32>()
        for x in lo.x...hi.x {
            for y in lo.y...hi.y {
                for z in lo.z...hi.z {
                    for index in cells[SIMD3(x, y, z)] ?? [] where seen.insert(index).inserted {
                        let tri = corners[Int(index)]
                        let a = positions[Int(tri.x)], b = positions[Int(tri.y)], c = positions[Int(tri.z)]
                        let q = Self.closestPoint(p, a, b, c)
                        let d = p - q
                        let distance = (d * d).sum()
                        guard distance < bestDistance else { continue }
                        var n = avatarCross(b - a, c - a)
                        let length = (n * n).sum().squareRoot()
                        guard length > 1e-12 else { continue }
                        n /= length
                        if (n * (normals[Int(tri.x)] + normals[Int(tri.y)] + normals[Int(tri.z)])).sum() < 0 { n = -n }
                        bestDistance = distance
                        best = (q, n)
                    }
                }
            }
        }
        return best
    }

    /// Closest point on triangle abc (Ericson, Real-Time Collision Detection, 5.1.5).
    static func closestPoint(_ p: SIMD3<Float>, _ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) -> SIMD3<Float> {
        let ab = b - a, ac = c - a, ap = p - a
        let d1 = (ab * ap).sum(), d2 = (ac * ap).sum()
        if d1 <= 0, d2 <= 0 { return a }
        let bp = p - b
        let d3 = (ab * bp).sum(), d4 = (ac * bp).sum()
        if d3 >= 0, d4 <= d3 { return b }
        let vc = d1 * d4 - d3 * d2
        if vc <= 0, d1 >= 0, d3 <= 0 { return a + (d1 / (d1 - d3)) * ab }
        let cp = p - c
        let d5 = (ab * cp).sum(), d6 = (ac * cp).sum()
        if d6 >= 0, d5 <= d6 { return c }
        let vb = d5 * d2 - d1 * d6
        if vb <= 0, d2 >= 0, d6 <= 0 { return a + (d2 / (d2 - d6)) * ac }
        let va = d3 * d6 - d5 * d4
        if va <= 0, d4 - d3 >= 0, d5 - d6 >= 0 { return b + ((d4 - d3) / ((d4 - d3) + (d5 - d6))) * (c - b) }
        let denominator = 1 / (va + vb + vc)
        return a + ab * (vb * denominator) + ac * (vc * denominator)
    }
}

/// Uniform hash grid for nearest-vertex queries.
struct HashGrid {
    private var cells: [SIMD3<Int32>: [Int32]] = [:]
    let cell: Float

    init(points: [SIMD3<Float>], cell: Float) {
        self.cell = cell
        for (i, p) in points.enumerated() { cells[key(p), default: []].append(Int32(i)) }
    }

    private func key(_ p: SIMD3<Float>) -> SIMD3<Int32> {
        SIMD3(Int32((p.x / cell).rounded(.down)), Int32((p.y / cell).rounded(.down)), Int32((p.z / cell).rounded(.down)))
    }

    func nearest(to p: SIMD3<Float>, within radius: Float, in points: [SIMD3<Float>]) -> Int? {
        let k = key(p), r = Int32((radius / cell).rounded(.up))
        var best: Int?, bestDistance = radius * radius
        for dx in -r...r {
            for dy in -r...r {
                for dz in -r...r {
                    for i in cells[k &+ SIMD3(dx, dy, dz)] ?? [] {
                        let d = points[Int(i)] - p
                        let distance = (d * d).sum()
                        if distance < bestDistance { bestDistance = distance; best = Int(i) }
                    }
                }
            }
        }
        return best
    }
}
