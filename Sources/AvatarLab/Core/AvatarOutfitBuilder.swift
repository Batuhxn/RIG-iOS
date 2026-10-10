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
    /// How far skin bordering hidden skin is pulled in under the fabric.
    static let skinTuck: Float = 0.008

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
        // Skin on the edge of what garments hide is tucked in a little, so the visible
        // triangles there slope under the fabric instead of poking through its edge
        // (the jagged white teeth along necklines in the Atelier close-ups).
        var shown = positions
        if !hidden.isEmpty {
            var covered = [Bool](repeating: false, count: positions.count)
            for triangle in hidden {
                for k in 0..<3 { covered[Int(bodyTriangles[Int(triangle) * 3 + k])] = true }
            }
            for v in visible where covered[Int(v)] {
                shown[Int(v)] = positions[Int(v)] - Self.skinTuck * bodyNormals[Int(v)]
            }
        }
        let body = AvatarMorphEngine.compact(triangles: visible, positions: shown, offset: 0)
        let bare = hidden.isEmpty ? body : AvatarMorphEngine.compact(triangles: bodyTriangles, positions: positions, offset: 0)
        return (body, bare, garments)
    }

    /// Layer guard: every garment sits at least `gap` outside each garment on a lower layer
    /// (a body-hugging coat shell used to pass through a relaxed tee; Codex review).
    /// Two clearances are enforced: above the closest point of the inner garment's
    /// surface, so the inside of a large triangle counts (Atelier review), and along the
    /// vertex's own normal from the nearest inner vertex, as before. Only vertices that
    /// moved are checked again. Normals of a moved garment are recomputed at the end.
    static func layer(_ garments: inout [AvatarMesh], cuts: [AvatarGarmentCut], gap: Float = 0.008, reach: Float = 0.06) {
        let order = cuts.indices.sorted { cuts[$0].layer < cuts[$1].layer }
        func yRange(_ m: AvatarMesh) -> ClosedRange<Float> {
            let ys = m.positions.map(\.y)
            return (ys.min() ?? 0)...(ys.max() ?? 0)
        }
        for (rank, outer) in order.enumerated() {
            let inners = order[..<rank].filter {
                // Garments that cannot touch (shoes and a tee) are skipped.
                cuts[$0].layer < cuts[outer].layer && yRange(garments[$0]).overlaps(yRange(garments[outer]))
            }
            guard !inners.isEmpty else { continue }
            var surfaces = inners.map { TriangleGrid(mesh: garments[$0], cell: reach) }
            let pointGrids = inners.map { HashGrid(points: garments[$0].positions, cell: reach / 2) }
            var mesh = garments[outer]
            // Pushes follow the vertex normals; once normals are recomputed from the moved
            // positions, clearance is checked again along them. The 8 mm gap leaves room
            // for the small tilt recomputed normals get, so two rounds settle it.
            for _ in 0..<2 {
                var movedThisRound = false
                for (i, inner) in inners.enumerated() {
                    let innerPoints = garments[inner].positions
                    // A push can bring a different inner triangle into play; a few passes settle it.
                    var pending = Array(mesh.positions.indices)
                    for _ in 0..<6 where !pending.isEmpty {
                        var moved: [Int] = []
                        for k in pending {
                            var p = mesh.positions[k]
                            let n = mesh.normals[k]
                            if let hit = surfaces[i].closest(to: p, within: reach) {
                                let depth = ((p - hit.point) * hit.normal).sum()
                                if depth < gap {
                                    // Along our own normal while it roughly agrees with theirs; otherwise
                                    // straight out of their surface (a perpendicular or opposed normal
                                    // slid vertices sideways or deeper; Codex review).
                                    let along = (n * hit.normal).sum()
                                    p += (gap - depth) * (along >= 0.5 ? n / along : hit.normal)
                                }
                            }
                            if let j = pointGrids[i].nearest(to: p, within: reach, in: innerPoints) {
                                let depth = ((p - innerPoints[j]) * n).sum()
                                if depth < gap { p += (gap - depth) * n }
                            }
                            if p != mesh.positions[k] {
                                mesh.positions[k] = p
                                moved.append(k)
                            }
                        }
                        if !moved.isEmpty { movedThisRound = true }
                        pending = moved
                    }
                }
                guard movedThisRound else { break }
                mesh.normals = Self.recomputedNormals(mesh)
            }
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
    /// Triangles spanning more than `maxCells` cells are checked on every query instead
    /// of being bucketed, so one huge triangle cannot make construction explode.
    private var oversized: [Int32] = []
    private static let maxCells = 512
    private let positions: [SIMD3<Float>]
    private let normals: [SIMD3<Float>]
    private let corners: [SIMD3<Int32>]
    /// Per-triangle mark of the last query that tested it (no per-query set).
    private var stamps: [UInt32]
    private var query: UInt32 = 0
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
        stamps = [UInt32](repeating: 0, count: corners.count)
        for (index, tri) in corners.enumerated() {
            let a = positions[Int(tri.x)], b = positions[Int(tri.y)], c = positions[Int(tri.z)]
            let lo = Self.key(pointwiseMin(a, pointwiseMin(b, c)), cell), hi = Self.key(pointwiseMax(a, pointwiseMax(b, c)), cell)
            let span = (Int(hi.x) - Int(lo.x) + 1) * (Int(hi.y) - Int(lo.y) + 1) * (Int(hi.z) - Int(lo.z) + 1)
            if span > Self.maxCells {
                oversized.append(Int32(index))
                continue
            }
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
    mutating func closest(to p: SIMD3<Float>, within radius: Float) -> (point: SIMD3<Float>, normal: SIMD3<Float>)? {
        let lo = Self.key(p - radius, cell), hi = Self.key(p + radius, cell)
        query &+= 1
        var best: (point: SIMD3<Float>, normal: SIMD3<Float>)?
        var bestDistance = radius * radius
        func test(_ index: Int32) {
            let t = Int(index)
            guard stamps[t] != query else { return }
            stamps[t] = query
            let tri = corners[t]
            let a = positions[Int(tri.x)], b = positions[Int(tri.y)], c = positions[Int(tri.z)]
            let q = Self.closestPoint(p, a, b, c)
            let d = p - q
            let distance = (d * d).sum()
            guard distance < bestDistance else { return }
            var n = avatarCross(b - a, c - a)
            let length = (n * n).sum().squareRoot()
            guard length > 1e-12 else { return }
            n /= length
            if (n * (normals[Int(tri.x)] + normals[Int(tri.y)] + normals[Int(tri.z)])).sum() < 0 { n = -n }
            bestDistance = distance
            best = (q, n)
        }
        for index in oversized { test(index) }
        for x in lo.x...hi.x {
            for y in lo.y...hi.y {
                for z in lo.z...hi.z {
                    for index in cells[SIMD3(x, y, z)] ?? [] { test(index) }
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
