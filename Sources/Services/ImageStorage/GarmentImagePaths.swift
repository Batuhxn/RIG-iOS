import Foundation

/// The three renditions RIG keeps for each garment.
enum GarmentImageKind: String, CaseIterable, Hashable, Sendable {
    /// The imported photograph, downscaled. Kept so a garment can be reprocessed
    /// later without asking the user to photograph it again.
    case original
    /// Transparent PNG produced by background removal. Absent when removal failed.
    case cutout
    /// Small PNG for grids. PNG rather than JPEG so a cutout keeps its
    /// transparency at thumbnail size.
    case thumbnail

    var fileName: String {
        switch self {
        case .original: return "original.jpg"
        case .cutout: return "cutout.png"
        case .thumbnail: return "thumbnail.png"
        }
    }
}

/// Relative path arithmetic, deliberately free of the file system so it can be
/// reasoned about and tested on its own.
///
/// Layout, rooted at the app's Application Support directory:
///
///     Garments/<GARMENT-UUID>/original.jpg
///     Garments/<GARMENT-UUID>/cutout.png
///     Garments/<GARMENT-UUID>/thumbnail.png
///
/// Every file a garment owns lives under one directory named by its UUID, so
/// two garments can never collide and deleting a garment is one directory
/// removal rather than a hunt for stray files.
enum GarmentImagePaths {
    static let rootDirectoryName = "Garments"
    static let separator = "/"

    static func directoryRelativePath(for id: UUID) -> String {
        "\(rootDirectoryName)\(separator)\(id.uuidString.uppercased())"
    }

    static func relativePath(for id: UUID, kind: GarmentImageKind) -> String {
        "\(directoryRelativePath(for: id))\(separator)\(kind.fileName)"
    }

    /// Recovers the owning garment from a stored path. Returns nil for anything
    /// that is not a well-formed garment path, which is how orphan sweeps avoid
    /// deleting directories they do not understand.
    static func garmentID(fromRelativePath path: String) -> UUID? {
        let components = path.split(separator: Character(separator))
        guard components.count >= 2, components[0] == rootDirectoryName else { return nil }
        return UUID(uuidString: String(components[1]))
    }
}
