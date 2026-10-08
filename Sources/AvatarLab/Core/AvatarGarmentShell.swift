import Foundation

/// How a garment is cut out of MakeHuman's clothing helpers.
///
/// Approximate by design: a shell that follows the body, not a simulated cloth
/// and not a fit. See docs/AVATAR_LAB.md.
enum AvatarGarmentCut: Equatable, Sendable {
    case top(sleeve: Sleeve, hem: Hem = .hip)
    case outerwear
    case trousers
    case shorts
    case skirt(length: SkirtLength)
    case dress(length: SkirtLength)
    case shoes

    enum Sleeve: Sendable { case none, short, long }
    enum Hem: Sendable { case hip, cropped }
    enum SkirtLength: Sendable { case mini, knee, midi, maxi }

    /// The layer it is drawn on, innermost first; also how far it sits off the skin.
    var layer: Int {
        switch self {
        case .shoes: return 0
        case .trousers, .shorts: return 1
        case .skirt: return 2
        case .top: return 3
        case .dress: return 3
        case .outerwear: return 4
        }
    }

    /// Tops, dresses and coats fall from the chest and shoulder blades.
    var hangsFromChest: Bool {
        switch self {
        case .top, .dress, .outerwear: return true
        default: return false
        }
    }

    var offset: Float {
        switch self {
        case .shoes: return 0.012
        case .trousers, .shorts: return 0.004
        case .skirt: return 0.005
        case .top, .dress: return 0.008
        case .outerwear: return 0.018
        }
    }
}

/// Landmarks of MakeHuman's neutral figure in its rest pose, in metres (feet at
/// 0, A-pose). Faces are chosen on the *rest* mesh, so a garment always covers
/// the same part of the body however it is shaped; the shell then follows the
/// morphed vertices.
enum AvatarRestLandmarks {
    static let neckline: Float = 1.40
    static let torsoHalfWidth: Float = 0.19
    static let elbowX: Float = 0.31
    static let wristX: Float = 0.39
    static let hipHem: Float = 0.90
    static let croppedHem: Float = 1.02
    static let coatHem: Float = 0.74
    static let waistline: Float = 0.98
    static let handsX: Float = 0.33
    static let shortsHem: Float = 0.60
    static let ankle: Float = 0.075
    static let shoeTop: Float = 0.09

    static func skirtHem(_ length: AvatarGarmentCut.SkirtLength) -> Float {
        switch length {
        case .mini: return 0.66
        case .knee: return 0.46
        case .midi: return 0.30
        case .maxi: return 0.12
        }
    }
}

struct AvatarGarmentShellBuilder: Sendable {
    let asset: AvatarBodyAsset
    /// For every helper vertex, the nearest body vertex in the rest pose (-1 for
    /// body vertices). Used to keep shells outside the skin after a morph.
    private let skinAnchor: [Int32]

    init(asset: AvatarBodyAsset) {
        self.asset = asset
        self.skinAnchor = Self.nearestBodyVertices(asset)
    }

    /// Nearest body vertex for each helper vertex, on a 4 cm hash grid.
    private static func nearestBodyVertices(_ asset: AvatarBodyAsset) -> [Int32] {
        let rest = asset.restPositions
        let cell: Float = 0.04
        func key(_ p: SIMD3<Float>) -> SIMD3<Int32> {
            SIMD3(Int32((p.x / cell).rounded(.down)), Int32((p.y / cell).rounded(.down)), Int32((p.z / cell).rounded(.down)))
        }
        var grid: [SIMD3<Int32>: [Int32]] = [:]
        for index in Set(asset.submeshes["body"] ?? []) {
            grid[key(rest[Int(index)]), default: []].append(Int32(index))
        }
        var anchors = [Int32](repeating: -1, count: rest.count)
        for index in Set((asset.submeshes["tights"] ?? []) + (asset.submeshes["skirt"] ?? [])) {
            let p = rest[Int(index)]
            let k = key(p)
            var best: Int32 = -1
            var bestDistance = Float.greatestFiniteMagnitude
            for radius in Int32(1)...Int32(4) {
                for dx in -radius...radius {
                    for dy in -radius...radius {
                        for dz in -radius...radius {
                            for candidate in grid[k &+ SIMD3(dx, dy, dz)] ?? [] {
                                let d = rest[Int(candidate)] - p
                                let distance = (d * d).sum()
                                if distance < bestDistance {
                                    bestDistance = distance
                                    best = candidate
                                }
                            }
                        }
                    }
                }
                if best >= 0 { break }
            }
            anchors[Int(index)] = best
        }
        return anchors
    }

    /// Triangles (in asset vertex numbering) that make up `cut`.
    func triangles(for cut: AvatarGarmentCut) -> [UInt32] {
        let L = AvatarRestLandmarks.self
        switch cut {
        case let .top(sleeve, hem):
            return select("tights", top: L.neckline, bottom: hem == .hip ? L.hipHem : L.croppedHem, maxAbsX: sleeveLimit(sleeve))
        case .outerwear:
            return select("tights", top: L.neckline + 0.02, bottom: L.coatHem, maxAbsX: L.wristX)
        case .trousers:
            return select("tights", top: L.waistline, bottom: L.ankle, maxAbsX: L.handsX)
        case .shorts:
            return select("tights", top: L.waistline, bottom: L.shortsHem, maxAbsX: L.handsX)
        case let .skirt(length):
            return select("skirt", top: 10, bottom: L.skirtHem(length), maxAbsX: 10)
        case let .dress(length):
            return select("tights", top: L.neckline - 0.03, bottom: L.waistline, maxAbsX: L.torsoHalfWidth)
                + select("skirt", top: 10, bottom: L.skirtHem(length), maxAbsX: 10)
        case .shoes:
            return select("tights", top: L.shoeTop, bottom: -1, maxAbsX: L.handsX)
        }
    }

    /// The garment's shell on a morphed body, with front-projected UVs so a
    /// garment photo maps onto it: u across the front view, v from top to hem.
    func shell(for cut: AvatarGarmentCut, positions: [SIMD3<Float>]) -> AvatarMesh {
        shells(for: [cut], positions: positions)[0]
    }

    /// Several shells on one morphed body; the body's normals are computed once.
    func shells(for cuts: [AvatarGarmentCut], positions: [SIMD3<Float>]) -> [AvatarMesh] {
        let bodyNormals = AvatarMorphEngine.normals(positions: positions, triangles: asset.submeshes["body"] ?? [])
        return cuts.map { cut in
            let tris = triangles(for: cut)
            let sign = outwardSign(tris, positions)
            var (mesh, sources) = AvatarMorphEngine.compactWithSources(triangles: tris, positions: positions, offset: cut.offset * sign)
            if sign < 0 {
                mesh.normals = mesh.normals.map { -$0 }
            }
            // Skin guard: a morph can push the body through a helper (MakeHuman's
            // helpers do not follow every target). Push such vertices back out.
            for k in mesh.positions.indices {
                let anchor = Int(skinAnchor[Int(sources[k])])
                guard anchor >= 0 else { continue }
                let n = bodyNormals[anchor]
                let depth = ((mesh.positions[k] - positions[anchor]) * n).sum()
                if depth < cut.offset {
                    mesh.positions[k] += (cut.offset - depth) * n
                }
            }
            if cut.hangsFromChest {
                Self.drape(&mesh, maxAbsX: AvatarRestLandmarks.torsoHalfWidth)
            }
            guard let bounds = mesh.frontBounds else { return mesh }
            let size = SIMD2(max(bounds.max.x - bounds.min.x, 1e-4), max(bounds.max.y - bounds.min.y, 1e-4))
            mesh.uvs = mesh.positions.map { p in
                SIMD2((p.x - bounds.min.x) / size.x, (bounds.max.y - p.y) / size.y)
            }
            return mesh
        }
    }

    /// Cloth over the torso hangs from what is above it instead of following
    /// every hollow: in each vertical strip, a front vertex is never further
    /// back than the most forward point above it, less a gentle slope (and the
    /// same for the back). This removes the "painted on" look under the chest,
    /// at the stomach and in the small of the back. Sleeves are left alone.
    static func drape(_ mesh: inout AvatarMesh, maxAbsX: Float, strip: Float = 0.012, slope: Float = 0.25) {
        var columns: [Int: [Int]] = [:]
        for k in mesh.positions.indices where abs(mesh.positions[k].x) <= maxAbsX {
            columns[Int((mesh.positions[k].x / strip).rounded(.down)), default: []].append(k)
        }
        for (_, members) in columns {
            let sorted = members.sorted { mesh.positions[$0].y > mesh.positions[$1].y }
            var front: (z: Float, y: Float)?
            var back: (z: Float, y: Float)?
            for k in sorted {
                var p = mesh.positions[k]
                let facesFront = mesh.normals[k].z >= 0
                if facesFront {
                    let limit = front.map { $0.z - slope * ($0.y - p.y) } ?? -.greatestFiniteMagnitude
                    if p.z > limit { front = (p.z, p.y) } else { p.z = limit }
                } else {
                    let limit = back.map { $0.z + slope * ($0.y - p.y) } ?? .greatestFiniteMagnitude
                    if p.z < limit { back = (p.z, p.y) } else { p.z = limit }
                }
                mesh.positions[k] = p
            }
        }
    }

    private func sleeveLimit(_ sleeve: AvatarGarmentCut.Sleeve) -> Float {
        switch sleeve {
        case .none: return AvatarRestLandmarks.torsoHalfWidth
        case .short: return AvatarRestLandmarks.elbowX
        case .long: return AvatarRestLandmarks.wristX
        }
    }

    /// Faces of a helper whose rest-pose centroid lies in the band. The helpers
    /// are quads split into triangle pairs; a pair is kept or dropped together,
    /// so hems follow the quad grid instead of zig-zagging.
    private func select(_ submesh: String, top: Float, bottom: Float, maxAbsX: Float) -> [UInt32] {
        let source = asset.submeshes[submesh] ?? []
        let rest = asset.restPositions
        var out: [UInt32] = []
        var t = 0
        while t + 2 < source.count {
            let isQuad = t + 5 < source.count && source[t + 3] == source[t] && source[t + 4] == source[t + 2]
            let count = isQuad ? 6 : 3
            var c = rest[Int(source[t])] + rest[Int(source[t + 1])] + rest[Int(source[t + 2])]
            if isQuad { c += rest[Int(source[t + 5])] }
            c /= isQuad ? 4 : 3
            if c.y <= top, c.y >= bottom, abs(c.x) <= maxAbsX {
                out += source[t..<(t + count)]
            }
            t += count
        }
        return out
    }

    /// +1 when the helper's winding makes normals point away from the body's
    /// vertical axis, −1 otherwise; decides which way "off the skin" is.
    private func outwardSign(_ triangles: [UInt32], _ positions: [SIMD3<Float>]) -> Float {
        let normals = AvatarMorphEngine.normals(positions: positions, triangles: triangles)
        var score: Float = 0
        for index in Set(triangles) {
            let p = positions[Int(index)]
            score += (normals[Int(index)] * SIMD3(p.x, 0, p.z)).sum()
        }
        return score >= 0 ? 1 : -1
    }
}
