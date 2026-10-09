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
    /// Vertices are pushed out along their own normal, measured against the nearest
    /// vertex of the inner garment found on a 3 cm hash grid.
    static func layer(_ garments: inout [AvatarMesh], cuts: [AvatarGarmentCut], gap: Float = 0.006) {
        let order = cuts.indices.sorted { cuts[$0].layer < cuts[$1].layer }
        func yRange(_ m: AvatarMesh) -> ClosedRange<Float> {
            let ys = m.positions.map(\.y)
            return (ys.min() ?? 0)...(ys.max() ?? 0)
        }
        for (rank, outer) in order.enumerated() {
            for inner in order[..<rank] where cuts[inner].layer < cuts[outer].layer {
                // Garments that cannot touch (shoes and a tee) are skipped.
                guard yRange(garments[inner]).overlaps(yRange(garments[outer])) else { continue }
                let innerPoints = garments[inner].positions
                let grid = HashGrid(points: innerPoints, cell: 0.06)
                var mesh = garments[outer]
                // A push can bring a different inner vertex into play; a few passes settle it.
                for _ in 0..<6 {
                    var moved = false
                    for k in mesh.positions.indices {
                        let p = mesh.positions[k]
                        guard let j = grid.nearest(to: p, within: 0.06, in: innerPoints) else { continue }
                        let n = mesh.normals[k]
                        let depth = ((p - innerPoints[j]) * n).sum()
                        if depth < gap {
                            mesh.positions[k] = p + (gap - depth) * n
                            moved = true
                        }
                    }
                    if !moved { break }
                }
                garments[outer] = mesh
            }
        }
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
