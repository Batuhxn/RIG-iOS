import Foundation

/// One sparse morph: the vertices it moves and how far, in metres.
struct AvatarMorphTarget: Sendable, Equatable {
    let vertices: [Int32]
    let deltas: [SIMD3<Float>]
}

/// The avatar's body: MakeHuman's CC0 base mesh with its clothing helpers and a
/// small set of baked morph targets. Built offline by
/// `Tools/AvatarAssets/build_avatar_asset.py`; see docs/AVATAR_LAB.md for the format.
///
/// Foundation only, so the body model is testable without a renderer.
struct AvatarBodyAsset: Sendable {
    enum LoadError: Error, Equatable {
        case badMagic
        case truncated
        case indexOutOfRange
        case missingSubmesh(String)
        case missingResource
        case invalidValue
    }

    /// Nothing in a human-sized asset lies further than this from the origin (metres).
    static let maxCoordinate: Float = 10

    static let resourceName = "RIGAvatarBody"
    static let resourceExtension = "rigavatar"
    static let requiredSubmeshes = ["body", "tights", "skirt"]

    let restPositions: [SIMD3<Float>]
    /// Triangle lists by name: "body", "tights" and "skirt".
    let submeshes: [String: [UInt32]]
    let targets: [String: AvatarMorphTarget]

    var vertexCount: Int { restPositions.count }

    init(data: Data) throws {
        var reader = Reader(bytes: [UInt8](data))
        guard reader.bytes.count >= 8, Array(reader.bytes[0..<8]) == Array("RIGAVTR1".utf8) else {
            throw LoadError.badMagic
        }
        reader.offset = 8
        // Every count is checked against the bytes left before anything is allocated,
        // so a corrupt count is a thrown error, never a huge allocation.
        let count = Int(try reader.u32())
        try reader.require(count, bytesEach: 12)
        var positions: [SIMD3<Float>] = []
        positions.reserveCapacity(count)
        for _ in 0..<count {
            let p = SIMD3(try reader.f32(), try reader.f32(), try reader.f32())
            guard p.x.isFinite, p.y.isFinite, p.z.isFinite,
                  max(abs(p.x), abs(p.y), abs(p.z)) <= Self.maxCoordinate else { throw LoadError.invalidValue }
            positions.append(p)
        }
        var submeshes: [String: [UInt32]] = [:]
        for _ in 0..<(try reader.u32()) {
            let name = try reader.name()
            let indexCount = Int(try reader.u32())
            try reader.require(indexCount, bytesEach: 4)
            var indices: [UInt32] = []
            indices.reserveCapacity(indexCount)
            for _ in 0..<indexCount {
                let index = try reader.u32()
                guard Int(index) < count else { throw LoadError.indexOutOfRange }
                indices.append(index)
            }
            submeshes[name] = indices
        }
        var targets: [String: AvatarMorphTarget] = [:]
        for _ in 0..<(try reader.u32()) {
            let name = try reader.name()
            let scale = try reader.f32()
            // i16 × scale must stay inside the coordinate bound: |delta| ≤ 32767 × scale.
            guard scale.isFinite, scale > 0, scale * 32767 <= Self.maxCoordinate else { throw LoadError.invalidValue }
            let entryCount = Int(try reader.u32())
            try reader.require(entryCount, bytesEach: 10)
            var vertices: [Int32] = []
            vertices.reserveCapacity(entryCount)
            for _ in 0..<entryCount {
                let index = try reader.u32()
                guard Int(index) < count else { throw LoadError.indexOutOfRange }
                vertices.append(Int32(index))
            }
            var deltas: [SIMD3<Float>] = []
            deltas.reserveCapacity(entryCount)
            for _ in 0..<entryCount {
                deltas.append(SIMD3(Float(try reader.i16()), Float(try reader.i16()), Float(try reader.i16())) * scale)
            }
            targets[name] = AvatarMorphTarget(vertices: vertices, deltas: deltas)
        }
        for name in Self.requiredSubmeshes where submeshes[name] == nil {
            throw LoadError.missingSubmesh(name)
        }
        self.restPositions = positions
        self.submeshes = submeshes
        self.targets = targets
    }

    /// The asset shipped in the app bundle.
    static func bundled(in bundle: Bundle = .main) throws -> AvatarBodyAsset {
        guard let url = bundle.url(forResource: resourceName, withExtension: resourceExtension) else {
            throw LoadError.missingResource
        }
        return try AvatarBodyAsset(data: Data(contentsOf: url, options: .mappedIfSafe))
    }
}

private struct Reader {
    let bytes: [UInt8]
    var offset = 0

    init(bytes: [UInt8]) { self.bytes = bytes }

    /// Throws `.truncated` unless `count` records of `bytesEach` bytes remain.
    func require(_ count: Int, bytesEach: Int) throws {
        guard count >= 0, count <= (bytes.count - offset) / bytesEach else { throw AvatarBodyAsset.LoadError.truncated }
    }

    private mutating func take(_ n: Int) throws -> ArraySlice<UInt8> {
        guard offset + n <= bytes.count else { throw AvatarBodyAsset.LoadError.truncated }
        defer { offset += n }
        return bytes[offset..<(offset + n)]
    }

    mutating func u32() throws -> UInt32 {
        try take(4).reversed().reduce(0) { $0 << 8 | UInt32($1) }
    }

    mutating func f32() throws -> Float { Float(bitPattern: try u32()) }

    mutating func i16() throws -> Int16 {
        let raw = try take(2)
        return Int16(bitPattern: UInt16(raw[raw.startIndex]) | UInt16(raw[raw.startIndex + 1]) << 8)
    }

    mutating func name() throws -> String {
        let raw = try take(32)
        return String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
    }
}
