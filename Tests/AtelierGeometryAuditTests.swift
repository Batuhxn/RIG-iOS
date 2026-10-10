import Foundation
import UIKit
import XCTest
@testable import RIG

/// Independent regression specifications. The defect tests are expected to fail
/// at ccdb984; run them in Apple's XCTest CI before and after the corresponding fix.
/// No production files are changed by this review.
final class AtelierGeometryAuditTests: XCTestCase {
    private func load() throws -> (AvatarBodyAsset, GarmentTemplateLibrary) {
        let asset = try AvatarBodyAsset.bundled(in: AvatarTestBundle.bundle)
        return (asset, try GarmentTemplateLibrary.bundled(in: AvatarTestBundle.bundle, for: asset))
    }

    func testNeutralTeeDoesNotPenetrateUnhiddenUnderarmSkin() throws {
        let (asset, library) = try load()
        let tee = try XCTUnwrap(library.templates["tee"])
        let body = try XCTUnwrap(asset.submeshes["body"])
        let normals = AvatarMorphEngine.normals(positions: asset.restPositions, triangles: body)
        let garment = GarmentDeformer.mesh(for: tee, positions: asset.restPositions, bodyNormals: normals)
        let hidden = Set(tee.hiddenBodyTriangles)
        var worst: Float = 0
        var checked = 0
        // Both underarms, selected spatially instead of relying on a packed vertex ID.
        for p in garment.positions where (1.20...1.27).contains(p.y)
            && (0.18...0.25).contains(abs(p.x)) && abs(p.z) < 0.03 {
            var best = Float.greatestFiniteMagnitude
            var depth: Float = 0
            var closestFace = -1
            for t in stride(from: 0, to: body.count, by: 3) {
                let a = asset.restPositions[Int(body[t])]
                let b = asset.restPositions[Int(body[t + 1])]
                let c = asset.restPositions[Int(body[t + 2])]
                let q = closestPoint(p, a, b, c)
                let d = p - q
                let distance = (d * d).sum()
                if distance < best {
                    best = distance
                    depth = (d * unit(avatarCross(b - a, c - a))).sum()
                    closestFace = t / 3
                }
            }
            if !hidden.contains(Int32(closestFace)) {
                checked += 1
                worst = min(worst, depth)
            }
        }
        XCTAssertGreaterThan(checked, 0)
        XCTAssertGreaterThanOrEqual(worst, -0.002,
            "Neutral tee intersects unhidden underarm skin; offline witness is about -17.35 mm")
    }

    func testPhotoFrontFacesRemainCameraFacingAfterMorphAndSmoothing() throws {
        let (asset, library) = try load()
        let tee = try XCTUnwrap(library.templates["tee"])
        let shape = AvatarBodyShape(values: [.hips: 1, .waist: -1, .bust: 1,
                                            .shoulders: 1, .overall: 1, .legLength: -0.6])
        let p = AvatarMorphEngine(asset: asset).positions(for: shape)
        let n = AvatarMorphEngine.normals(positions: p, triangles: asset.submeshes["body"] ?? [])
        let mesh = GarmentDeformer.mesh(for: tee, positions: p, bodyNormals: n)
        var minFacing: Float = 1
        for t in stride(from: 0, to: mesh.triangles.count, by: 3) {
            let a = Int(mesh.triangles[t]), b = Int(mesh.triangles[t + 1]), c = Int(mesh.triangles[t + 2])
            var fn = unit(avatarCross(mesh.positions[b] - mesh.positions[a], mesh.positions[c] - mesh.positions[a]))
            if (fn * (mesh.normals[a] + mesh.normals[b] + mesh.normals[c])).sum() < 0 { fn = -fn }
            minFacing = min(minFacing, fn.z)
        }
        XCTAssertGreaterThanOrEqual(minFacing, 0.34,
            "Photo faces must satisfy the authored 0.35 facing threshold, allowing 0.01 numeric margin")
    }

    func testLayerGuardChecksInnerTriangleInteriors() {
        // A valid inner surface with sparse vertices: the outer triangle is directly
        // behind its interior, but every inner vertex is beyond the 6 cm search radius.
        let inner = triangle([SIMD3(-1, -1, 0.01), SIMD3(1, -1, 0.01), SIMD3(0, 1, 0.01)])
        let outer = triangle([SIMD3(-0.01, 0, 0), SIMD3(0.01, 0, 0), SIMD3(0, 0.01, 0)])
        var garments = [inner, outer]
        AvatarOutfitBuilder.layer(&garments, cuts: [.top(sleeve: .short), .outerwear])
        for p in garments[1].positions {
            XCTAssertGreaterThanOrEqual(p.z, 0.016 - 1e-6,
                "A nearest-vertex guard misses a triangle's interior")
        }
    }

    func testLayerGuardRecomputesNormalsAfterMovingVertices() {
        // Only the two bottom outer vertices are close to the inner garment. The
        // third stays at z=0; the resulting face tilts, so its normal must change.
        let inner = triangle([SIMD3(0, 0, 0.03), SIMD3(0.1, 0, 0.03), SIMD3(0, 0.001, 0.03)])
        let outer = triangle([SIMD3(0, 0, 0), SIMD3(0.1, 0, 0), SIMD3(0, 0.2, 0)])
        var garments = [inner, outer]
        AvatarOutfitBuilder.layer(&garments, cuts: [.top(sleeve: .short), .outerwear])
        let mesh = garments[1]
        XCTAssertGreaterThan(mesh.positions[0].z, 0.03, "Fixture must exercise a real layer push")
        let expected = unit(avatarCross(mesh.positions[1] - mesh.positions[0], mesh.positions[2] - mesh.positions[0]))
        for k in mesh.normals.indices {
            XCTAssertLessThan(length(mesh.normals[k] - expected), 0.001,
                "Normals must describe the final rendered positions, not the pre-guard mesh")
        }
    }

    func testPaddingUsesTheNearestNonemptyRow() {
        var rgba: [UInt8] = [255, 0, 0, 255, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 255, 255]
        XCTAssertTrue(AvatarTexturePadding.pad(&rgba, width: 1, height: 4))
        XCTAssertEqual(Array(rgba[4..<8]), [255, 0, 0, 255])
        XCTAssertEqual(Array(rgba[8..<12]), [0, 0, 255, 255],
            "Row 2 is one row from blue and two from red; previous-row filling smears the wrong colour")
    }

    @MainActor
    func testRewearingSameGarmentUsesItsNewlySelectedPhoto() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = GarmentImageStore(baseDirectory: directory)
        let id = UUID()
        func photo(_ colour: UIColor) throws -> Data {
            let image = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16)).image { context in
                colour.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
            }
            return try XCTUnwrap(image.pngData())
        }
        let original = try store.write(photo(.red), for: id, kind: .original)
        let cutout = try store.write(photo(.blue), for: id, kind: .cutout)
        let item = ClothingItem(id: id, displayName: "Photo cache witness", subtype: "T-shirt",
                                category: .top, primaryColor: .red, originalImageRelativePath: original,
                                cutoutImageRelativePath: cutout, isBackgroundRemoved: false)
        let model = AvatarLabModel(store: nil, imageStore: store)
        await model.load()
        let oldID = model.content?.id
        model.wear(item, in: .top)
        let first = try await nextContent(model, after: oldID, garmentID: id)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        XCTAssertTrue(first.garments[0].colour.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        XCTAssertGreaterThan(red, 0.9, "Fixture must first cache the red original")
        item.isBackgroundRemoved = true
        model.wear(item, in: .top)
        let second = try await nextContent(model, after: first.id, garmentID: id)
        XCTAssertTrue(second.garments[0].colour.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        XCTAssertGreaterThan(blue, 0.9, "Changing the selected photo must invalidate a UUID-only texture cache")
    }

    func testLoaderRejectsWeightsOutsideTheBarycentricSimplex() throws {
        let (asset, _) = try load()
        var data = try garmentData()
        // Header 12 + name 32 + version/count 8 + three body indices 12 = wb at 64.
        replaceU32(&data, at: 64, with: Float(2).bitPattern)
        XCTAssertThrowsError(try GarmentTemplateLibrary(data: data, bodyVertexCount: asset.vertexCount,
            bodyTriangleCount: (asset.submeshes["body"]?.count ?? 0) / 3))
    }

    func testLoaderRejectsUnsupportedTemplateVersion() throws {
        let (asset, _) = try load()
        var data = try garmentData()
        replaceU32(&data, at: 44, with: 999)
        XCTAssertThrowsError(try GarmentTemplateLibrary(data: data, bodyVertexCount: asset.vertexCount,
            bodyTriangleCount: (asset.submeshes["body"]?.count ?? 0) / 3))
    }

    /// Positive control: duplicate UV seam vertices share final positions and normals.
    func testSeamDuplicatesShareSmoothedPositionsAndNormals() throws {
        let (asset, library) = try load()
        let normals = AvatarMorphEngine.normals(positions: asset.restPositions,
                                               triangles: asset.submeshes["body"] ?? [])
        for template in library.templates.values {
            let mesh = GarmentDeformer.mesh(for: template, positions: asset.restPositions, bodyNormals: normals)
            for k in template.canonical.indices {
                let twin = Int(template.canonical[k])
                XCTAssertEqual(mesh.positions[k], mesh.positions[twin], template.name)
                XCTAssertEqual(mesh.normals[k], mesh.normals[twin], template.name)
            }
        }
    }

    private func garmentData() throws -> Data {
        let url = try XCTUnwrap(AvatarTestBundle.bundle.url(forResource: GarmentTemplateLibrary.resourceName,
            withExtension: GarmentTemplateLibrary.resourceExtension))
        return try Data(contentsOf: url)
    }

    @MainActor
    private func nextContent(_ model: AvatarLabModel, after oldID: UUID?, garmentID: UUID) async throws -> AvatarStageContent {
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            if let content = model.content, content.id != oldID,
               content.garments.first?.id == garmentID { return content }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for the requested geometry and texture refresh")
        throw NSError(domain: "AtelierGeometryAuditTests", code: 1)
    }

    private func replaceU32(_ data: inout Data, at offset: Int, with value: UInt32) {
        withUnsafeBytes(of: value.littleEndian) { data.replaceSubrange(offset..<(offset + 4), with: $0) }
    }

    private func triangle(_ positions: [SIMD3<Float>]) -> AvatarMesh {
        AvatarMesh(positions: positions, normals: Array(repeating: SIMD3(0, 0, 1), count: 3),
                   uvs: Array(repeating: .zero, count: 3), triangles: [0, 1, 2])
    }

    private func length(_ v: SIMD3<Float>) -> Float { (v * v).sum().squareRoot() }
    private func unit(_ v: SIMD3<Float>) -> SIMD3<Float> {
        let l = length(v)
        return l > 1e-12 ? v / l : .zero
    }

    private func closestPoint(_ p: SIMD3<Float>, _ a: SIMD3<Float>, _ b: SIMD3<Float>,
                              _ c: SIMD3<Float>) -> SIMD3<Float> {
        var best = a
        var distance = Float.greatestFiniteMagnitude
        func consider(_ q: SIMD3<Float>) {
            let d = p - q
            let ds = (d * d).sum()
            if ds < distance { distance = ds; best = q }
        }
        let ab = b - a, ac = c - a
        let fn = avatarCross(ab, ac)
        let nn = (fn * fn).sum()
        let d00 = (ab * ab).sum(), d01 = (ab * ac).sum(), d11 = (ac * ac).sum()
        let denominator = d00 * d11 - d01 * d01
        if nn > 1e-20 && denominator > 0 {
            let projected = p - ((p - a) * fn).sum() / nn * fn
            let ap = projected - a
            let d20 = (ap * ab).sum(), d21 = (ap * ac).sum()
            let wb = (d11 * d20 - d01 * d21) / denominator
            let wc = (d00 * d21 - d01 * d20) / denominator
            if wb >= 0 && wc >= 0 && wb + wc <= 1 { consider(projected) }
        }
        for (start, end) in [(a, b), (b, c), (c, a)] {
            let edge = end - start
            let squared = (edge * edge).sum()
            let t: Float = squared > 0 ? min(max(((p - start) * edge).sum() / squared, 0), 1) : 0
            consider(start + t * edge)
        }
        return best
    }
}
