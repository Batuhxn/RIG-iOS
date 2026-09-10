import XCTest
@testable import RIG

final class GarmentImageStorageTests: XCTestCase {
    private var directory: URL!
    private var store: GarmentImageStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appending(path: "RIGTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = GarmentImageStore(baseDirectory: directory)
    }

    override func tearDownWithError() throws {
        if let directory {
            try? FileManager.default.removeItem(at: directory)
        }
        store = nil
        directory = nil
        try super.tearDownWithError()
    }

    // MARK: - Path arithmetic

    func testRelativePathIsStableForTheSameGarmentAndKind() {
        let id = Fixture.id(1)
        XCTAssertEqual(
            GarmentImagePaths.relativePath(for: id, kind: .cutout),
            GarmentImagePaths.relativePath(for: id, kind: .cutout)
        )
    }

    func testDifferentGarmentsNeverCollide() {
        var seen = Set<String>()
        for index in 0..<50 {
            for kind in GarmentImageKind.allCases {
                let path = GarmentImagePaths.relativePath(for: Fixture.id(index), kind: kind)
                XCTAssertTrue(seen.insert(path).inserted, "Duplicate path: \(path)")
            }
        }
    }

    func testEachKindHasItsOwnFile() {
        let id = Fixture.id(1)
        let paths = GarmentImageKind.allCases.map { GarmentImagePaths.relativePath(for: id, kind: $0) }
        XCTAssertEqual(Set(paths).count, GarmentImageKind.allCases.count)
        XCTAssertTrue(paths.allSatisfy { $0.hasPrefix("\(GarmentImagePaths.rootDirectoryName)/") })
    }

    func testGarmentIDRecoveredFromPath() {
        let id = Fixture.id(7)
        let path = GarmentImagePaths.relativePath(for: id, kind: .original)
        XCTAssertEqual(GarmentImagePaths.garmentID(fromRelativePath: path), id)
    }

    func testUnrecognisedPathsYieldNoGarmentID() {
        XCTAssertNil(GarmentImagePaths.garmentID(fromRelativePath: "Garments"))
        XCTAssertNil(GarmentImagePaths.garmentID(fromRelativePath: "Elsewhere/\(Fixture.id(1).uuidString)/original.jpg"))
        XCTAssertNil(GarmentImagePaths.garmentID(fromRelativePath: "Garments/not-a-uuid/original.jpg"))
    }

    // MARK: - Reading and writing

    func testWriteThenReadRoundTrips() throws {
        let id = Fixture.id(1)
        let payload = Data("garment-bytes".utf8)
        let path = try store.write(payload, for: id, kind: .original)

        XCTAssertTrue(store.exists(atRelativePath: path))
        XCTAssertEqual(store.data(atRelativePath: path), payload)
    }

    func testWriteOverwritesInPlace() throws {
        let id = Fixture.id(1)
        _ = try store.write(Data("first".utf8), for: id, kind: .cutout)
        let path = try store.write(Data("second".utf8), for: id, kind: .cutout)
        XCTAssertEqual(store.data(atRelativePath: path), Data("second".utf8))
    }

    func testMissingFileReadsAsNil() {
        XCTAssertNil(store.data(atRelativePath: GarmentImagePaths.relativePath(for: Fixture.id(99), kind: .cutout)))
        XCTAssertFalse(store.exists(atRelativePath: "Garments/nothing/here.png"))
    }

    // MARK: - Cleanup bookkeeping

    func testRemovingAGarmentRemovesEveryRendition() throws {
        let id = Fixture.id(1)
        var paths: [String] = []
        for kind in GarmentImageKind.allCases {
            paths.append(try store.write(Data("x".utf8), for: id, kind: kind))
        }
        XCTAssertTrue(paths.allSatisfy { store.exists(atRelativePath: $0) })

        try store.removeAll(for: id)
        XCTAssertTrue(paths.allSatisfy { !store.exists(atRelativePath: $0) })
    }

    func testRemovingAGarmentLeavesOtherGarmentsAlone() throws {
        let kept = try store.write(Data("keep".utf8), for: Fixture.id(1), kind: .original)
        _ = try store.write(Data("drop".utf8), for: Fixture.id(2), kind: .original)

        try store.removeAll(for: Fixture.id(2))
        XCTAssertTrue(store.exists(atRelativePath: kept))
    }

    func testRemovingAnUnknownGarmentIsNotAnError() {
        XCTAssertNoThrow(try store.removeAll(for: Fixture.id(404)))
    }

    func testOrphanSweepFindsOnlyUnknownGarments() throws {
        _ = try store.write(Data("a".utf8), for: Fixture.id(1), kind: .original)
        _ = try store.write(Data("b".utf8), for: Fixture.id(2), kind: .original)
        _ = try store.write(Data("c".utf8), for: Fixture.id(3), kind: .original)

        let orphans = store.orphanedGarmentIDs(knownGarmentIDs: [Fixture.id(1)])
        XCTAssertEqual(Set(orphans), [Fixture.id(2), Fixture.id(3)])

        let removed = store.removeOrphans(knownGarmentIDs: [Fixture.id(1)])
        XCTAssertEqual(removed, 2)
        XCTAssertTrue(store.exists(atRelativePath: GarmentImagePaths.relativePath(for: Fixture.id(1), kind: .original)))
        XCTAssertTrue(store.orphanedGarmentIDs(knownGarmentIDs: [Fixture.id(1)]).isEmpty)
    }

    func testOrphanSweepIgnoresDirectoriesItDoesNotUnderstand() throws {
        _ = try store.write(Data("a".utf8), for: Fixture.id(1), kind: .original)
        let stranger = directory
            .appending(path: GarmentImagePaths.rootDirectoryName, directoryHint: .isDirectory)
            .appending(path: "not-a-uuid", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: stranger, withIntermediateDirectories: true)

        XCTAssertTrue(store.orphanedGarmentIDs(knownGarmentIDs: [Fixture.id(1)]).isEmpty)
        XCTAssertEqual(store.removeOrphans(knownGarmentIDs: [Fixture.id(1)]), 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: stranger.path(percentEncoded: false)))
    }

    func testOrphanSweepOnAnEmptyStoreIsHarmless() {
        XCTAssertTrue(store.orphanedGarmentIDs(knownGarmentIDs: []).isEmpty)
        XCTAssertEqual(store.removeOrphans(knownGarmentIDs: []), 0)
    }
}
