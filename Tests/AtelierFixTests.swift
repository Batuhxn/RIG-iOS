import UIKit
import XCTest
@testable import RIG

/// Regression tests for the fixes made after Codex's second Atelier review.
@MainActor
final class AtelierFixTests: XCTestCase {
    private func load() throws -> (AvatarBodyAsset, GarmentTemplateLibrary) {
        let asset = try AvatarBodyAsset.bundled(in: AvatarTestBundle.bundle)
        return (asset, try GarmentTemplateLibrary.bundled(in: AvatarTestBundle.bundle, for: asset))
    }

    /// Every vertex the plain back panel uses carries no photo, so the photo can never
    /// sit at full strength next to a plain face.
    func testSeamWeightIsZeroOnTheBackPanelAndRisesAwayFromIt() throws {
        let (asset, library) = try load()
        let builder = AvatarOutfitBuilder(asset: asset, templates: library)
        let built = try XCTUnwrap(builder.build(shape: .neutral, cuts: [.top(sleeve: .short), .dress(length: .knee)]))
        for mesh in built.garments where !mesh.backTriangles.isEmpty {
            let weights = AvatarStageCoordinator.seamWeights(mesh)
            XCTAssertEqual(weights.count, mesh.positions.count)
            for k in Set(mesh.backTriangles.map(Int.init)) { XCTAssertEqual(weights[k], 0) }
            XCTAssertTrue(weights.allSatisfy { (0...1).contains($0) })
            let front = Set(mesh.triangles.map(Int.init))
            XCTAssertGreaterThan(front.filter { weights[$0] == 1 }.count, front.count / 3, "the middle of the panel keeps the full photo")
        }
    }

    /// An empty photo row takes the nearest row with garment, below as well as above.
    func testPhotoSpansFillFromTheNearestRow() throws {
        let filled = try XCTUnwrap(GarmentPhotoMapping.fillPairs([(0, 0.2), nil, nil, (0.6, 1)]))
        XCTAssertEqual(filled.map { $0.lo }, [0, 0, 0.6, 0.6])
        XCTAssertEqual(try XCTUnwrap(GarmentPhotoMapping.fillPairs([nil, (0.3, 0.4)])).map { $0.lo }, [0.3, 0.3])
        XCTAssertNil(GarmentPhotoMapping.fillPairs([nil, nil]))
    }

    /// Codex: with the outer normal perpendicular to the inner surface, the old guard slid
    /// the vertex sideways and left it inside.
    func testLayerGuardPushesOutOfTheSurfaceWhenNormalsDisagree() {
        let inner = AvatarMesh(positions: [SIMD3(-1, -1, 0), SIMD3(1, -1, 0), SIMD3(0, 1, 0)],
                               normals: Array(repeating: SIMD3(0, 0, 1), count: 3),
                               uvs: Array(repeating: .zero, count: 3), triangles: [0, 1, 2])
        let outer = AvatarMesh(positions: [SIMD3(0, 0, -0.001), SIMD3(0.01, 0, -0.001), SIMD3(0, 0.01, -0.001)],
                               normals: Array(repeating: SIMD3(1, 0, 0), count: 3),
                               uvs: Array(repeating: .zero, count: 3), triangles: [0, 1, 2])
        var garments = [inner, outer]
        AvatarOutfitBuilder.layer(&garments, cuts: [.top(sleeve: .short), .outerwear])
        for p in garments[1].positions {
            XCTAssertGreaterThanOrEqual(p.z, 0.006 - 1e-5, "out of the inner surface")
            XCTAssertLessThan(abs(p.x), 0.05, "not slid sideways")
        }
    }

    /// One enormous triangle must not make the grid allocate millions of cells.
    func testTriangleGridCapsOversizedTriangles() {
        let huge = AvatarMesh(positions: [SIMD3(-10, -10, -10), SIMD3(10, -10, 10), SIMD3(0, 10, 0)],
                              normals: Array(repeating: SIMD3(0, 0, 1), count: 3),
                              uvs: Array(repeating: .zero, count: 3), triangles: [0, 1, 2])
        let started = Date()
        var grid = TriangleGrid(mesh: huge, cell: 0.03)
        XCTAssertNotNil(grid.closest(to: SIMD3(0, 0, 0), within: 0.06))
        XCTAssertLessThan(Date().timeIntervalSince(started), 1)
    }

    /// The snapshot used to ignore its background argument (a local shadowed it).
    func testSnapshotUsesTheRequestedBackground() throws {
        let coordinator = AvatarStageCoordinator()
        let image = coordinator.snapshot(size: CGSize(width: 8, height: 8), background: .red)
        let cg = try XCTUnwrap(image.cgImage)
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = try XCTUnwrap(CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        XCTAssertGreaterThan(pixel[0], 200)
        XCTAssertLessThan(pixel[1], 60)
    }
}
