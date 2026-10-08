import Foundation

/// Applies a body shape to the asset on the CPU. Plain linear blend shapes:
/// position = rest + Σ weight × delta. Targets are sparse and local, which is
/// what keeps the controls independent.
struct AvatarMorphEngine: Sendable {
    let asset: AvatarBodyAsset

    func positions(for shape: AvatarBodyShape) -> [SIMD3<Float>] {
        var positions = asset.restPositions
        for (name, weight) in shape.targetWeights where weight != 0 {
            guard let target = asset.targets[name] else { continue }
            for k in 0..<target.vertices.count {
                positions[Int(target.vertices[k])] += weight * target.deltas[k]
            }
        }
        return positions
    }

    /// Area-weighted vertex normals over the given triangles. Vertices not used
    /// by them keep a zero normal.
    static func normals(positions: [SIMD3<Float>], triangles: [UInt32]) -> [SIMD3<Float>] {
        var normals = [SIMD3<Float>](repeating: .zero, count: positions.count)
        var t = 0
        while t + 2 < triangles.count {
            let a = Int(triangles[t]), b = Int(triangles[t + 1]), c = Int(triangles[t + 2])
            let n = avatarCross(positions[b] - positions[a], positions[c] - positions[a])
            normals[a] += n
            normals[b] += n
            normals[c] += n
            t += 3
        }
        return normals.map { n in
            let length = (n * n).sum().squareRoot()
            return length > 0 ? n / length : .zero
        }
    }
}

/// A self-contained triangle mesh ready for any renderer.
struct AvatarMesh: Sendable, Equatable {
    var positions: [SIMD3<Float>]
    var normals: [SIMD3<Float>]
    var uvs: [SIMD2<Float>]
    var triangles: [UInt32]

    var isEmpty: Bool { triangles.isEmpty }

    /// Front-view bounds (x, y) in metres.
    var frontBounds: (min: SIMD2<Float>, max: SIMD2<Float>)? {
        guard let first = positions.first else { return nil }
        var lo = SIMD2(first.x, first.y), hi = lo
        for p in positions {
            lo = SIMD2(Swift.min(lo.x, p.x), Swift.min(lo.y, p.y))
            hi = SIMD2(Swift.max(hi.x, p.x), Swift.max(hi.y, p.y))
        }
        return (lo, hi)
    }

    /// Wavefront OBJ, for offline previews and debugging.
    func objText() -> String {
        var out = ""
        for p in positions { out += "v \(p.x) \(p.y) \(p.z)\n" }
        var t = 0
        while t + 2 < triangles.count {
            out += "f \(triangles[t] + 1) \(triangles[t + 1] + 1) \(triangles[t + 2] + 1)\n"
            t += 3
        }
        return out
    }
}

func avatarCross(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> {
    SIMD3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
}

extension AvatarMorphEngine {
    /// Extracts one submesh as a compact mesh with its own vertex numbering.
    func mesh(named name: String, positions: [SIMD3<Float>]) -> AvatarMesh {
        Self.compact(triangles: asset.submeshes[name] ?? [], positions: positions, offset: 0)
    }

    /// Re-indexes `triangles` into a standalone mesh, pushing each vertex
    /// `offset` metres out along its normal (garments sit just above the skin).
    static func compact(triangles: [UInt32], positions: [SIMD3<Float>], offset: Float) -> AvatarMesh {
        compactWithSources(triangles: triangles, positions: positions, offset: offset).mesh
    }

    /// `compact`, plus the asset vertex each new vertex came from.
    static func compactWithSources(triangles: [UInt32], positions: [SIMD3<Float>], offset: Float) -> (mesh: AvatarMesh, sources: [UInt32]) {
        let normals = Self.normals(positions: positions, triangles: triangles)
        var remap: [UInt32: UInt32] = [:]
        var sources: [UInt32] = []
        var mesh = AvatarMesh(positions: [], normals: [], uvs: [], triangles: [])
        mesh.triangles.reserveCapacity(triangles.count)
        for index in triangles {
            if let new = remap[index] {
                mesh.triangles.append(new)
            } else {
                let new = UInt32(mesh.positions.count)
                remap[index] = new
                sources.append(index)
                let n = normals[Int(index)]
                mesh.positions.append(positions[Int(index)] + offset * n)
                mesh.normals.append(n)
                mesh.triangles.append(new)
            }
        }
        mesh.uvs = [SIMD2<Float>](repeating: .zero, count: mesh.positions.count)
        return (mesh, sources)
    }
}
