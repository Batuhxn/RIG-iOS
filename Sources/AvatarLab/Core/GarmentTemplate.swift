import Foundation

/// RiG Garment Engine v1: authored garments with their own volume, bound to the body.
///
/// A template is built offline by `Tools/AvatarAssets/build_garment_templates.py` from
/// MakeHuman's CC0 helper topology, shaped at the rest pose (ease, hang, flare) and bound
/// .mhclo-style: every garment vertex is a barycentric point on a body triangle plus an
/// offset in that triangle's local frame. Evaluating the binding on a morphed body moves
/// the garment with it while keeping its own shape. See docs/AVATAR_LAB.md.
struct GarmentTemplate: Sendable {
    struct Binding: Sendable, Equatable {
        let a: Int32, b: Int32, c: Int32
        let wb: Float, wc: Float
        /// Offset along the interpolated normal, then along the triangle's two tangents.
        let normal: Float, tangent1: Float, tangent2: Float
    }

    let name: String
    let version: Int
    let bindings: [Binding]
    let uvs: [SIMD2<Float>]
    /// For seam duplicates, the vertex whose normal they share (smooth shading across seams).
    let canonical: [Int32]
    /// The front panel: where the garment photo is shown.
    let frontTriangles: [UInt32]
    /// The back panel: what a single front photo cannot show.
    let backTriangles: [UInt32]
    /// Body triangles (indices into the body's triangle list / 3) the garment covers.
    let hiddenBodyTriangles: [Int32]
    /// Neighbours of each canonical vertex, and whether it lies on an open edge (hem,
    /// neckline, sleeve opening). Derived from the triangles at load.
    let neighbours: [[Int32]]
    let isBoundary: [Bool]

    var vertexCount: Int { bindings.count }

    init(name: String, version: Int, bindings: [Binding], uvs: [SIMD2<Float>], canonical: [Int32],
         frontTriangles: [UInt32], backTriangles: [UInt32], hiddenBodyTriangles: [Int32]) {
        self.name = name
        self.version = version
        self.bindings = bindings
        self.uvs = uvs
        self.canonical = canonical
        self.frontTriangles = frontTriangles
        self.backTriangles = backTriangles
        self.hiddenBodyTriangles = hiddenBodyTriangles
        var sets = [Set<Int32>](repeating: [], count: bindings.count)
        var edgeUse: [UInt64: Int] = [:]
        for list in [frontTriangles, backTriangles] {
            var t = 0
            while t + 2 < list.count {
                let tri = (0..<3).map { canonical[Int(list[t + $0])] }
                for k in 0..<3 {
                    let a = tri[k], b = tri[(k + 1) % 3]
                    sets[Int(a)].insert(b)
                    sets[Int(b)].insert(a)
                    let key = UInt64(UInt32(min(a, b))) << 32 | UInt64(UInt32(max(a, b)))
                    edgeUse[key, default: 0] += 1
                }
                t += 3
            }
        }
        var boundary = [Bool](repeating: false, count: bindings.count)
        for (key, uses) in edgeUse where uses == 1 {
            boundary[Int(key >> 32)] = true
            boundary[Int(key & 0xFFFF_FFFF)] = true
        }
        neighbours = sets.map { Array($0) }
        isBoundary = boundary
    }
}

/// Loads `RIGGarments.rigarm`.
struct GarmentTemplateLibrary: Sendable {
    enum LibraryError: Error, Equatable {
        case badMagic, truncated, indexOutOfRange, invalidValue, missingResource
    }

    static let resourceName = "RIGGarments"
    static let resourceExtension = "rigarm"

    let templates: [String: GarmentTemplate]

    /// - Parameters:
    ///   - bodyVertexCount: vertices in the avatar asset; every binding must refer to one.
    ///   - bodyTriangleCount: triangles in the avatar's body submesh.
    init(data: Data, bodyVertexCount: Int, bodyTriangleCount: Int) throws {
        var r = ByteReader(bytes: [UInt8](data))
        guard (try? r.take(8)).map(Array.init) == Array("RIGGARM1".utf8) else { throw LibraryError.badMagic }
        let count = Int(try r.u32())
        guard count <= 64 else { throw LibraryError.invalidValue }
        var templates: [String: GarmentTemplate] = [:]
        for _ in 0..<count {
            let name = try r.name()
            let version = Int(try r.u32())
            let n = Int(try r.u32())
            try r.require(n, bytesEach: 44)  // 3 × u32, 7 × f32, 1 × u32
            var bindings: [GarmentTemplate.Binding] = []
            var uvs: [SIMD2<Float>] = []
            var canonical: [Int32] = []
            bindings.reserveCapacity(n)
            for _ in 0..<n {
                let a = try r.u32(), b = try r.u32(), c = try r.u32()
                let floats = try (0..<7).map { _ in try r.f32() }
                let twin = try r.u32()
                guard Int(a) < bodyVertexCount, Int(b) < bodyVertexCount, Int(c) < bodyVertexCount,
                      Int(twin) < n else { throw LibraryError.indexOutOfRange }
                guard floats.allSatisfy({ $0.isFinite && abs($0) <= 10 }) else { throw LibraryError.invalidValue }
                bindings.append(.init(a: Int32(a), b: Int32(b), c: Int32(c), wb: floats[0], wc: floats[1],
                                      normal: floats[2], tangent1: floats[3], tangent2: floats[4]))
                uvs.append(SIMD2(floats[5], floats[6]))
                canonical.append(Int32(twin))
            }
            let front = try r.indices(limit: n)
            let back = try r.indices(limit: n)
            let hidden = try r.indices(limit: bodyTriangleCount).map(Int32.init)
            guard front.count % 3 == 0, back.count % 3 == 0 else { throw LibraryError.invalidValue }
            templates[name] = GarmentTemplate(name: name, version: version, bindings: bindings, uvs: uvs,
                                              canonical: canonical, frontTriangles: front, backTriangles: back,
                                              hiddenBodyTriangles: hidden)
        }
        self.templates = templates
    }

    static func bundled(in bundle: Bundle = .main, for asset: AvatarBodyAsset) throws -> GarmentTemplateLibrary {
        guard let url = bundle.url(forResource: resourceName, withExtension: resourceExtension) else {
            throw LibraryError.missingResource
        }
        return try GarmentTemplateLibrary(data: Data(contentsOf: url, options: .mappedIfSafe),
                                          bodyVertexCount: asset.vertexCount,
                                          bodyTriangleCount: (asset.submeshes["body"]?.count ?? 0) / 3)
    }
}

/// Places a template on a (morphed) body.
enum GarmentDeformer {
    /// - Parameters:
    ///   - positions: the morphed avatar vertices.
    ///   - bodyNormals: unit vertex normals of the morphed body.
    static func mesh(for template: GarmentTemplate, positions: [SIMD3<Float>], bodyNormals: [SIMD3<Float>],
                     smoothing: Int = 2) -> AvatarMesh {
        var out = [SIMD3<Float>](repeating: .zero, count: template.vertexCount)
        for (k, bind) in template.bindings.enumerated() {
            let ia = Int(bind.a), ib = Int(bind.b), ic = Int(bind.c)
            let wa = 1 - bind.wb - bind.wc
            let pa = positions[ia], pb = positions[ib], pc = positions[ic]
            let q = wa * pa + bind.wb * pb + bind.wc * pc
            var n = wa * bodyNormals[ia] + bind.wb * bodyNormals[ib] + bind.wc * bodyNormals[ic]
            n = normalized(n)
            var e1 = (pb - pa) - ((pb - pa) * n).sum() * n
            e1 = normalized(e1)
            let e2 = avatarCross(n, e1)
            out[k] = q + bind.normal * n + bind.tangent1 * e1 + bind.tangent2 * e2
        }
        smooth(&out, template, iterations: smoothing)
        // Normals over both panels, accumulated on the canonical vertex so the side
        // seams shade smoothly.
        var acc = [SIMD3<Float>](repeating: .zero, count: out.count)
        for list in [template.frontTriangles, template.backTriangles] {
            var t = 0
            while t + 2 < list.count {
                let a = Int(list[t]), b = Int(list[t + 1]), c = Int(list[t + 2])
                let fn = avatarCross(out[b] - out[a], out[c] - out[a])
                acc[Int(template.canonical[a])] += fn
                acc[Int(template.canonical[b])] += fn
                acc[Int(template.canonical[c])] += fn
                t += 3
            }
        }
        // Point away from the body: the binding's offset direction tells which side is out.
        var outward: Float = 0
        for (k, bind) in template.bindings.enumerated() { outward += (acc[Int(template.canonical[k])] * bodyNormals[Int(bind.a)]).sum() }
        let flip: Float = outward < 0 ? -1 : 1
        let normals = (0..<out.count).map { flip * normalized(acc[Int(template.canonical[$0])]) }
        return AvatarMesh(positions: out, normals: normals, uvs: template.uvs,
                          triangles: template.frontTriangles, backTriangles: template.backTriangles)
    }

    /// Two Taubin steps (shrink-free smoothing) over the garment, on canonical vertices,
    /// leaving open edges where they are. Evens out the ripples that strong, combined
    /// body morphs put into the fabric, which showed as wavy stripes.
    static func smooth(_ p: inout [SIMD3<Float>], _ template: GarmentTemplate, iterations: Int = 2) {
        let canonical = template.canonical
        for _ in 0..<iterations {
            for factor: Float in [0.5, -0.53] {
                var moved = p
                for k in p.indices where Int(canonical[k]) == k && !template.isBoundary[k] {
                    let ring = template.neighbours[k]
                    guard !ring.isEmpty else { continue }
                    var centre = SIMD3<Float>.zero
                    for j in ring { centre += p[Int(j)] }
                    centre /= Float(ring.count)
                    moved[k] = p[k] + factor * (centre - p[k])
                }
                // Seam duplicates follow their canonical vertex.
                for k in p.indices where Int(canonical[k]) != k { moved[k] = moved[Int(canonical[k])] }
                p = moved
            }
        }
    }

    private static func normalized(_ v: SIMD3<Float>) -> SIMD3<Float> {
        let l = (v * v).sum().squareRoot()
        return l > 1e-12 ? v / l : SIMD3(0, 0, 1)
    }
}

extension AvatarGarmentCut {
    /// The Garment Engine v1 template for this cut, when there is one. Other cuts use the
    /// earlier body-hugging shells.
    var templateName: String? {
        switch self {
        case .top(sleeve: .short, hem: .hip): return "tee"
        case .trousers: return "trousers"
        // Knee length only: a midi cut keeps the longer shell until a midi template exists.
        case .skirt(length: .knee): return "skirt"
        case .dress(length: .knee): return "dress"
        default: return nil
        }
    }
}

/// Little-endian reader with bounds checks before every allocation.
struct ByteReader {
    let bytes: [UInt8]
    var offset = 0

    init(bytes: [UInt8]) { self.bytes = bytes }

    mutating func take(_ n: Int) throws -> ArraySlice<UInt8> {
        guard n >= 0, offset + n <= bytes.count else { throw GarmentTemplateLibrary.LibraryError.truncated }
        defer { offset += n }
        return bytes[offset..<(offset + n)]
    }

    func require(_ count: Int, bytesEach: Int) throws {
        guard count >= 0, count <= (bytes.count - offset) / bytesEach else { throw GarmentTemplateLibrary.LibraryError.truncated }
    }

    mutating func u32() throws -> UInt32 { try take(4).reversed().reduce(0) { $0 << 8 | UInt32($1) } }
    mutating func f32() throws -> Float { Float(bitPattern: try u32()) }

    mutating func name() throws -> String {
        String(decoding: try take(32).prefix { $0 != 0 }, as: UTF8.self)
    }

    /// A u32 count followed by that many u32 values, each below `limit`.
    mutating func indices(limit: Int) throws -> [UInt32] {
        let n = Int(try u32())
        try require(n, bytesEach: 4)
        var out: [UInt32] = []
        out.reserveCapacity(n)
        for _ in 0..<n {
            let v = try u32()
            guard Int(v) < limit else { throw GarmentTemplateLibrary.LibraryError.indexOutOfRange }
            out.append(v)
        }
        return out
    }
}
