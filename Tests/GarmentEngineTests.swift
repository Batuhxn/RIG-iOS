import Foundation
import XCTest
@testable import RIG

final class GarmentEngineTests: XCTestCase {
    private static var cache: (AvatarBodyAsset, GarmentTemplateLibrary)?

    private func load() throws -> (AvatarBodyAsset, GarmentTemplateLibrary) {
        if let cache = Self.cache { return cache }
        let asset = try AvatarBodyAsset.bundled(in: AvatarTestBundle.bundle)
        let library = try GarmentTemplateLibrary.bundled(in: AvatarTestBundle.bundle, for: asset)
        Self.cache = (asset, library)
        return (asset, library)
    }

    private func garment(_ name: String, shape: AvatarBodyShape = .neutral) throws -> (AvatarMesh, [SIMD3<Float>], [SIMD3<Float>]) {
        let (asset, library) = try load()
        let template = try XCTUnwrap(library.templates[name])
        let positions = AvatarMorphEngine(asset: asset).positions(for: shape)
        let normals = AvatarMorphEngine.normals(positions: positions, triangles: asset.submeshes["body"] ?? [])
        return (GarmentDeformer.mesh(for: template, positions: positions, bodyNormals: normals), positions, normals)
    }

    private func halfWidth(_ points: [SIMD3<Float>], y: ClosedRange<Float>) -> Float {
        points.filter { y.contains($0.y) }.map { abs($0.x) }.max() ?? 0
    }

    // MARK: Loading

    func testLibraryHasTheFourV1Templates() throws {
        let (_, library) = try load()
        XCTAssertEqual(Set(library.templates.keys), ["tee", "trousers", "skirt", "dress"])
        for template in library.templates.values {
            XCTAssertEqual(template.version, 1)
            XCTAssertGreaterThan(template.frontTriangles.count / 3, 100, template.name)
            XCTAssertGreaterThan(template.backTriangles.count / 3, 100, template.name)
            XCTAssertFalse(template.hiddenBodyTriangles.isEmpty, template.name)
            XCTAssertTrue(template.uvs.allSatisfy { (0...1).contains($0.x) && (0...1).contains($0.y) })
        }
    }

    func testCorruptLibrariesAreRejected() throws {
        let (asset, _) = try load()
        let url = try XCTUnwrap(AvatarTestBundle.bundle.url(forResource: GarmentTemplateLibrary.resourceName,
                                                           withExtension: GarmentTemplateLibrary.resourceExtension))
        let good = try Data(contentsOf: url)
        let tris = (asset.submeshes["body"]?.count ?? 0) / 3
        XCTAssertThrowsError(try GarmentTemplateLibrary(data: Data("nope".utf8), bodyVertexCount: asset.vertexCount, bodyTriangleCount: tris))
        XCTAssertThrowsError(try GarmentTemplateLibrary(data: good.prefix(good.count / 2), bodyVertexCount: asset.vertexCount, bodyTriangleCount: tris))
        // Bindings must refer to vertices of the body they are loaded against.
        XCTAssertThrowsError(try GarmentTemplateLibrary(data: good, bodyVertexCount: 10, bodyTriangleCount: tris))
        var huge = Data("RIGGARM1".utf8)
        huge.append(contentsOf: [1, 0, 0, 0])
        huge.append(Data(count: 32))
        huge.append(contentsOf: [1, 0, 0, 0, 0xFF, 0xFF, 0xFF, 0x7F])
        XCTAssertThrowsError(try GarmentTemplateLibrary(data: huge, bodyVertexCount: asset.vertexCount, bodyTriangleCount: tris)) {
            XCTAssertEqual($0 as? GarmentTemplateLibrary.LibraryError, .truncated)
        }
    }

    // MARK: Volume

    func testGarmentsHaveRoomInsteadOfHuggingTheBody() throws {
        let (asset, _) = try load()
        let shells = AvatarGarmentShellBuilder(asset: asset)
        let (tee, rest, _) = try garment("tee")
        let oldTee = shells.shell(for: .top(sleeve: .short), positions: rest)
        // At the stomach, the relaxed tee stands clearly further from the body than the old shell.
        let band: ClosedRange<Float> = 1.00...1.08
        let newFront = tee.positions.filter { band.contains($0.y) && abs($0.x) < 0.05 }.map(\.z).max() ?? 0
        let oldFront = oldTee.positions.filter { band.contains($0.y) && abs($0.x) < 0.05 }.map(\.z).max() ?? 0
        XCTAssertGreaterThan(newFront, oldFront + 0.01, "the tee hangs from the chest instead of following the stomach")
    }

    func testSkirtFlaresAwayFromTheBody() throws {
        let (skirt, _, _) = try garment("skirt")
        let top = halfWidth(skirt.positions, y: 0.90...0.96)
        let hem = halfWidth(skirt.positions, y: 0.44...0.52)
        XCTAssertGreaterThan(hem, top + 0.05, "A-line: the hem is clearly wider than the hips")
    }

    func testTrousersKeepTwoStraightLegOpenings() throws {
        let (trousers, _, _) = try garment("trousers")
        let hem = trousers.positions.filter { $0.y < 0.14 }
        XCTAssertFalse(hem.isEmpty)
        XCTAssertTrue(hem.contains { $0.x < -0.03 } && hem.contains { $0.x > 0.03 }, "two legs")
        XCTAssertFalse(hem.contains { abs($0.x) < 0.02 }, "a gap between the leg openings")
        func legWidth(_ points: [SIMD3<Float>], _ y: ClosedRange<Float>) -> Float {
            let pts = points.filter { y.contains($0.y) && $0.x > 0 }
            return (pts.map(\.x).max() ?? 0) - (pts.map(\.x).min() ?? 0)
        }
        // Straight leg: the hem keeps the knee's width instead of closing round the ankle.
        let (asset, _) = try load()
        let ankle = legWidth(Set(asset.submeshes["body"] ?? []).map { asset.restPositions[Int($0)] }, 0.12...0.15)
        XCTAssertGreaterThan(legWidth(trousers.positions, 0.12...0.15), ankle * 1.4, "the hem stands well clear of the ankle")
    }

    // MARK: Body adaptation

    func testGarmentsFollowEachBodyChange() throws {
        var hips = AvatarBodyShape.neutral
        hips[.hips] = 1
        let (narrow, _, _) = try garment("skirt")
        let (wide, _, _) = try garment("skirt", shape: hips)
        XCTAssertGreaterThan(halfWidth(wide.positions, y: 0.84...0.92), halfWidth(narrow.positions, y: 0.84...0.92) + 0.01)

        var shoulders = AvatarBodyShape.neutral
        shoulders[.shoulders] = 1
        let (tee, _, _) = try garment("tee")
        let (broad, _, _) = try garment("tee", shape: shoulders)
        XCTAssertGreaterThan(halfWidth(broad.positions, y: 1.30...1.40), halfWidth(tee.positions, y: 1.30...1.40) + 0.01)
    }

    func testExtremeButValidShapesKeepGarmentsOutsideTheSkin() throws {
        var extreme = AvatarBodyShape.neutral
        extreme[.hips] = 1
        extreme[.waist] = -1
        extreme[.bust] = 1
        extreme[.shoulders] = 1
        extreme[.overall] = 1
        extreme[.legLength] = -0.6
        for name in ["tee", "trousers", "skirt", "dress"] {
            let (mesh, positions, normals) = try garment(name, shape: extreme)
            XCTAssertTrue(mesh.positions.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }, name)
            // Fraction of garment vertices more than 5 mm inside the skin, by their nearest body vertex.
            let body = Array(Set(try load().0.submeshes["body"] ?? []))
            var inside = 0
            let sample = stride(from: 0, to: mesh.positions.count, by: 4).map { mesh.positions[$0] }
            for p in sample {
                var best = Float.greatestFiniteMagnitude, bi = 0
                for i in body {
                    let d = positions[Int(i)] - p
                    let dist = (d * d).sum()
                    if dist < best { best = dist; bi = Int(i) }
                }
                if ((p - positions[bi]) * normals[bi]).sum() < -0.005 { inside += 1 }
            }
            // Measured 2.0% for the dress at this extreme (v1); most such skin is hidden under the garment.
            XCTAssertLessThan(Double(inside) / Double(sample.count), 0.03, "\(name): \(inside) vertices inside the body")
        }
    }

    // MARK: Photo mapping

    func testPhotoOutlineIsMappedOntoTheFrontPanelOutline() throws {
        let (skirt, _, _) = try garment("skirt")
        // A trapezoid photo: narrow at the waist (0.3...0.7), full width at the hem.
        let spans: [ClosedRange<Float>?] = (0..<64).map { r in
            let t = Float(r) / 63
            return (0.3 - 0.3 * t)...(0.7 + 0.3 * t)
        }
        let uvs = GarmentPhotoMapping.uvs(for: skirt, photoSpans: spans)
        let front = Set(skirt.triangles.map(Int.init))
        for i in front {
            let row = min(63, Int(uvs[i].y * 64))
            let span = try XCTUnwrap(spans[row])
            XCTAssertGreaterThanOrEqual(uvs[i].x, span.lowerBound - 0.06, "front vertices sample the garment, not its transparent margin")
            XCTAssertLessThanOrEqual(uvs[i].x, span.upperBound + 0.06)
        }
        let top = front.filter { uvs[$0].y < 0.1 }.map { uvs[$0].x }
        XCTAssertGreaterThan(top.min() ?? 0, 0.2, "at the waist only the photo's narrow waistband is used")
        XCTAssertEqual(GarmentPhotoMapping.uvs(for: skirt, photoSpans: [nil, nil]), skirt.uvs, "an empty photo changes nothing")
    }

    // MARK: Outfit building

    func testCoveredSkinIsHiddenAndRepeatedBuildsAreStable() throws {
        let (asset, library) = try load()
        let builder = AvatarOutfitBuilder(asset: asset, templates: library)
        let bare = try XCTUnwrap(builder.build(shape: .neutral, cuts: []))
        let dressed = try XCTUnwrap(builder.build(shape: .neutral, cuts: [.trousers, .top(sleeve: .short)]))
        XCTAssertLessThan(dressed.body.triangles.count, bare.body.triangles.count, "skin under the garments is not drawn")
        XCTAssertEqual(dressed.bareBody.triangles.count, bare.body.triangles.count, "the 2D overlay still gets the whole body")
        XCTAssertEqual(dressed.garments.count, 2)
        XCTAssertFalse(dressed.garments[1].backTriangles.isEmpty, "templates come with a back panel")
        // Swapping outfits back and forth gives identical results (no state carried over).
        for _ in 0..<5 {
            _ = builder.build(shape: .neutral, cuts: [.skirt(length: .knee)])
            _ = builder.build(shape: .neutral, cuts: [.dress(length: .knee), .shoes])
        }
        XCTAssertEqual(builder.build(shape: .neutral, cuts: [.trousers, .top(sleeve: .short)])?.garments, dressed.garments)
        // Cuts without a template still get the earlier shell.
        let coat = try XCTUnwrap(builder.build(shape: .neutral, cuts: [.outerwear]))
        XCTAssertTrue(coat.garments[0].backTriangles.isEmpty)
        XCTAssertFalse(coat.garments[0].triangles.isEmpty)
    }

    func testOutfitBuildIsFastEnoughForASlider() throws {
        let (asset, library) = try load()
        let builder = AvatarOutfitBuilder(asset: asset, templates: library)
        var shape = AvatarBodyShape.neutral
        shape[.hips] = 0.4
        let start = Date()
        for _ in 0..<5 { _ = builder.build(shape: shape, cuts: [.trousers, .top(sleeve: .short), .shoes]) }
        let each = Date().timeIntervalSince(start) / 5
        print("AVATAR_METRIC engine_outfit_ms=\(Int(each * 1000))")
        XCTAssertLessThan(each, 1.5)
    }
}
