import Foundation

enum GarmentImageStoreError: LocalizedError, Equatable {
    case baseDirectoryUnavailable
    case writeFailed(String)
    case readFailed(String)

    var errorDescription: String? {
        switch self {
        case .baseDirectoryUnavailable:
            return "RIG could not open its local storage folder."
        case .writeFailed:
            return "That image could not be saved to this device."
        case .readFailed:
            return "That image could not be read from this device."
        }
    }
}

/// Owns every garment image byte on disk.
///
/// Nothing here touches the network, and nothing here knows what an outfit is.
/// It deals in `Data` so it stays free of UIKit and remains testable with a
/// temporary directory.
struct GarmentImageStore: Sendable {
    let baseDirectory: URL

    init(baseDirectory: URL) {
        self.baseDirectory = baseDirectory
    }

    /// The production store. Application Support is the right home: it is backed
    /// up with the device, excluded from the user's Photos, and not purged the
    /// way Caches can be.
    static func applicationSupport() throws -> GarmentImageStore {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw GarmentImageStoreError.baseDirectoryUnavailable
        }
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return GarmentImageStore(baseDirectory: base)
    }

    func url(forRelativePath relativePath: String) -> URL {
        baseDirectory.appending(path: relativePath, directoryHint: .notDirectory)
    }

    func directoryURL(for id: UUID) -> URL {
        baseDirectory.appending(path: GarmentImagePaths.directoryRelativePath(for: id), directoryHint: .isDirectory)
    }

    func exists(atRelativePath relativePath: String) -> Bool {
        FileManager.default.fileExists(atPath: url(forRelativePath: relativePath).path(percentEncoded: false))
    }

    @discardableResult
    func write(_ data: Data, for id: UUID, kind: GarmentImageKind) throws -> String {
        let relativePath = GarmentImagePaths.relativePath(for: id, kind: kind)
        let destination = url(forRelativePath: relativePath)
        do {
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: destination, options: [.atomic])
        } catch {
            throw GarmentImageStoreError.writeFailed(relativePath)
        }
        return relativePath
    }

    func data(atRelativePath relativePath: String) -> Data? {
        try? Data(contentsOf: url(forRelativePath: relativePath))
    }

    /// Called when a garment is deleted. Removes the whole directory, so no
    /// rendition can survive its owner.
    func removeAll(for id: UUID) throws {
        let directory = directoryURL(for: id)
        guard FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) else { return }
        do {
            try FileManager.default.removeItem(at: directory)
        } catch {
            throw GarmentImageStoreError.writeFailed(GarmentImagePaths.directoryRelativePath(for: id))
        }
    }

    /// Garment directories on disk with no matching row in the store.
    ///
    /// These appear when a delete is interrupted, or when a store is restored
    /// without its files. Directories whose names are not garment UUIDs are
    /// never reported, so an unexpected file can never be swept up by accident.
    func orphanedGarmentIDs(knownGarmentIDs: Set<UUID>) -> [UUID] {
        let root = baseDirectory.appending(path: GarmentImagePaths.rootDirectoryName, directoryHint: .isDirectory)
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return contents
            .compactMap { UUID(uuidString: $0.lastPathComponent) }
            .filter { !knownGarmentIDs.contains($0) }
            .sorted { $0.uuidString < $1.uuidString }
    }

    @discardableResult
    func removeOrphans(knownGarmentIDs: Set<UUID>) -> Int {
        let orphans = orphanedGarmentIDs(knownGarmentIDs: knownGarmentIDs)
        var removed = 0
        for id in orphans {
            do {
                try removeAll(for: id)
                removed += 1
            } catch {
                continue
            }
        }
        return removed
    }
}
