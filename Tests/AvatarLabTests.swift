import Foundation
import XCTest
@testable import RIG

final class AvatarLabTests: XCTestCase {
    private static var cached: AvatarBodyAsset?

    private func asset() throws -> AvatarBodyAsset {
        if let cached = Self.cached { return cached }
        let loaded = try AvatarBodyAsset.bundled(in: AvatarTestBundle.bundle)
        Self.cached = loaded
        return loaded
    }

    // MARK: Asset

    func testBundledAssetLoadsWithEveryTargetTheControlsNeed() throws {
        let asset = try asset()
        XCTAssertGreaterThan(asset.vertexCount, 10_000)
        for name in AvatarBodyAsset.requiredSubmeshes {
            XCTAssertFalse(asset.submeshes[name, default: []].isEmpty, name)
            XCTAssertEqual(asset.submeshes[name, default: []].count % 3, 0, name)
        }
        for control in AvatarControl.allCases {
            for (name, _) in control.targets.negative + control.targets.positive {
                XCTAssertNotNil(asset.targets[name], "\(control) needs \(name)")
            }
        }
        let heights = asset.restPositions.map(\.y)
        XCTAssertEqual(heights.min() ?? -1, 0, accuracy: 1e-4, "feet stand on the floor")
        XCTAssertEqual(heights.max() ?? 0, 1.66, accuracy: 0.03, "neutral figure is about 1.66 m")
    }

    func testCorruptAssetsAreRejectedNotCrashed() throws {
        let good = try Data(contentsOf: XCTUnwrap(AvatarTestBundle.bundle.url(
            forResource: AvatarBodyAsset.resourceName, withExtension: AvatarBodyAsset.resourceExtension)))
        XCTAssertThrowsError(try AvatarBodyAsset(data: Data("nope".utf8))) { XCTAssertEqual($0 as? AvatarBodyAsset.LoadError, .badMagic) }
        XCTAssertThrowsError(try AvatarBodyAsset(data: good.prefix(good.count / 2))) { XCTAssertEqual($0 as? AvatarBodyAsset.LoadError, .truncated) }
    }

    // MARK: Shape

    func testValuesAreClampedAndNonFiniteValuesAreNeutral() {
        var shape = AvatarBodyShape.neutral
        shape[.hips] = 7
        XCTAssertEqual(shape[.hips], 1)
        shape[.height] = 1
        XCTAssertEqual(shape[.height], AvatarControl.height.range.upperBound)
        shape[.waist] = .nan
        XCTAssertEqual(shape[.waist], 0)
        shape[.waist] = -.infinity
        XCTAssertEqual(shape[.waist], 0)
    }

    func testProfileRoundTripsAndToleratesUnknownOrBadValues() throws {
        var shape = AvatarBodyShape.neutral
        shape[.shoulders] = 0.4
        shape[.legLength] = -0.2
        let data = try JSONEncoder().encode(shape)
        XCTAssertEqual(try JSONDecoder().decode(AvatarBodyShape.self, from: data), shape)

        let future = Data(#"{"schemaVersion":9,"values":{"hips":3,"wingspan":1,"waist":-0.5}}"#.utf8)
        let decoded = try JSONDecoder().decode(AvatarBodyShape.self, from: future)
        XCTAssertEqual(decoded[.hips], 1)
        XCTAssertEqual(decoded[.waist], -0.5)
        XCTAssertEqual(decoded.schemaVersion, AvatarBodyShape.currentSchemaVersion)

        let garbage = Data(#"{"values":"x"}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(AvatarBodyShape.self, from: garbage), .neutral)
    }

    func testProfileStoreSavesReloadsAndDeletes() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = AvatarProfileStore(directory: dir)
        XCTAssertNil(store.load())
        var profile = AvatarProfile()
        profile.shape[.hips] = 0.5
        profile.outfit = AvatarOutfitSelection(top: UUID(), bottom: nil, shoes: UUID())
        try store.save(profile)
        XCTAssertEqual(store.load(), profile)
        try store.delete()
        XCTAssertNil(store.load())
        try Data("{".utf8).write(to: store.fileURL, options: .atomic)
        XCTAssertNil(store.load(), "a corrupt file reads as no profile")
    }

    // MARK: Morphs

    func testHipsChangeHipsOnlyAndShouldersChangeShouldersOnly() throws {
        let engine = AvatarMorphEngine(asset: try asset())
        let rest = engine.positions(for: .neutral)

        var hips = AvatarBodyShape.neutral
        hips[.hips] = 1
        let wide = engine.positions(for: hips)
        XCTAssertGreaterThan(halfWidth(wide, y: 0.85...0.95), halfWidth(rest, y: 0.85...0.95) + 0.01)
        XCTAssertEqual(maxMove(rest, wide, y: 1.30...2), 0, accuracy: 1e-3, "shoulders and head stay put")

        var shoulders = AvatarBodyShape.neutral
        shoulders[.shoulders] = 1
        let broad = engine.positions(for: shoulders)
        XCTAssertGreaterThan(maxMove(rest, broad, y: 1.30...1.50), 0.01)
        XCTAssertEqual(maxMove(rest, broad, y: 0...0.95, maxAbsX: 0.3), 0, accuracy: 1e-3, "hips and legs stay put")
    }

    func testEveryControlVisiblyChangesTheBodyAndStaysCoherentAtItsLimits() throws {
        let engine = AvatarMorphEngine(asset: try asset())
        let rest = engine.positions(for: .neutral)
        for control in AvatarControl.allCases {
            for end in [control.range.lowerBound, control.range.upperBound] {
                var shape = AvatarBodyShape.neutral
                shape[control] = end
                let moved = engine.positions(for: shape)
                XCTAssertGreaterThan(maxMove(rest, moved, y: -1...3), 0.003, "\(control) at \(end)")
                XCTAssertTrue(moved.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
                // No vertex flies off: everything stays within a plausible human box.
                let height = (moved.map(\.y).max() ?? 0) - (moved.map(\.y).min() ?? 0)
                XCTAssertTrue((1.40...1.95).contains(height), "\(control) at \(end): height \(height)")
            }
        }
    }

    // MARK: Garments

    func testEveryGarmentCutProducesAShellOutsideTheSkin() throws {
        let asset = try asset()
        let engine = AvatarMorphEngine(asset: asset)
        let builder = AvatarGarmentShellBuilder(asset: asset)
        let positions = engine.positions(for: .neutral)
        let cuts: [AvatarGarmentCut] = [
            .top(sleeve: .none), .top(sleeve: .short), .top(sleeve: .long), .top(sleeve: .short, hem: .cropped),
            .outerwear, .trousers, .shorts, .skirt(length: .mini), .skirt(length: .midi), .dress(length: .knee), .shoes,
        ]
        for cut in cuts {
            let shell = builder.shell(for: cut, positions: positions)
            XCTAssertGreaterThan(shell.triangles.count / 3, 40, "\(cut)")
            XCTAssertEqual(shell.uvs.count, shell.positions.count)
            XCTAssertTrue(shell.uvs.allSatisfy { (0...1).contains($0.x) && (0...1).contains($0.y) }, "\(cut)")
        }
        let long = builder.shell(for: .top(sleeve: .long), positions: positions).frontBounds
        let short = builder.shell(for: .top(sleeve: .short), positions: positions).frontBounds
        XCTAssertGreaterThan(try XCTUnwrap(long).max.x, try XCTUnwrap(short).max.x + 0.04, "long sleeves reach further")
        let trousers = try XCTUnwrap(builder.shell(for: .trousers, positions: positions).frontBounds)
        let shorts = try XCTUnwrap(builder.shell(for: .shorts, positions: positions).frontBounds)
        XCTAssertLessThan(trousers.min.y, shorts.min.y - 0.3)
    }

    func testGarmentsFollowTheBodyShape() throws {
        let asset = try asset()
        let engine = AvatarMorphEngine(asset: asset)
        let builder = AvatarGarmentShellBuilder(asset: asset)
        var curvy = AvatarBodyShape.neutral
        curvy[.hips] = 1
        for cut in [AvatarGarmentCut.trousers, .skirt(length: .knee)] {
            let before = builder.shell(for: cut, positions: engine.positions(for: .neutral)).positions
            let after = builder.shell(for: cut, positions: engine.positions(for: curvy)).positions
            XCTAssertGreaterThan(halfWidth(after, y: 0.80...0.92), halfWidth(before, y: 0.80...0.92) + 0.01, "\(cut) widens with the hips")
        }
    }

    func testCategoryMapsToACut() {
        XCTAssertEqual(AvatarGarmentCut.forGarment(category: .top, subtype: "T-shirt"), .top(sleeve: .short))
        XCTAssertEqual(AvatarGarmentCut.forGarment(category: .top, subtype: "Sweater"), .top(sleeve: .long))
        XCTAssertEqual(AvatarGarmentCut.forGarment(category: .top, subtype: "Tank top"), .top(sleeve: .none))
        XCTAssertEqual(AvatarGarmentCut.forGarment(category: .bottom, subtype: "Jeans"), .trousers)
        XCTAssertEqual(AvatarGarmentCut.forGarment(category: .bottom, subtype: "Mini skirt"), .skirt(length: .mini))
        XCTAssertEqual(AvatarGarmentCut.forGarment(category: .bottom, subtype: "Shorts"), .shorts)
        XCTAssertEqual(AvatarGarmentCut.forGarment(category: .shoes, subtype: ""), .shoes)
        XCTAssertNil(AvatarGarmentCut.forGarment(category: .bag, subtype: ""))
    }

    func testFlatOverlayPlacesAPhotoInsideItsShellsFrontBounds() throws {
        let asset = try asset()
        let builder = AvatarGarmentShellBuilder(asset: asset)
        let shell = builder.shell(for: .top(sleeve: .short), positions: asset.restPositions)
        let projection = AvatarFrontProjection(viewWidth: 300, viewHeight: 600, visibleHeight: 2.0, centreY: 0.9)
        let rect = try XCTUnwrap(projection.overlayRect(for: shell, imageAspect: 1.0))
        let bounds = try XCTUnwrap(shell.frontBounds)
        let a = projection.point(x: bounds.min.x, y: bounds.max.y)
        let b = projection.point(x: bounds.max.x, y: bounds.min.y)
        XCTAssertGreaterThanOrEqual(rect.minX, a.x - 0.5)
        XCTAssertLessThanOrEqual(rect.maxX, b.x + 0.5)
        XCTAssertGreaterThanOrEqual(rect.minY, a.y - 0.5)
        XCTAssertLessThanOrEqual(rect.maxY, b.y + 0.5)
    }

    func testWarpBandsFollowTheShellFromCollarToHem() throws {
        let asset = try asset()
        let builder = AvatarGarmentShellBuilder(asset: asset)
        let projection = AvatarFrontProjection(viewWidth: 300, viewHeight: 600, visibleHeight: 2.0, centreY: 0.9)
        let tee = try XCTUnwrap(projection.warpBands(for: builder.shell(for: .top(sleeve: .short), positions: asset.restPositions), bands: 16))
        XCTAssertEqual(tee.count, 16)
        for (upper, lower) in zip(tee, tee.dropFirst()) {
            XCTAssertEqual(upper.maxY, lower.minY, accuracy: 0.01, "bands tile from top to bottom")
        }
        let sleeves = tee[2].width, belly = tee[12].width
        XCTAssertGreaterThan(sleeves, belly * 1.4, "the sleeve rows are wider than the torso rows")
        var curvy = AvatarBodyShape.neutral
        curvy[.hips] = 1
        let engine = AvatarMorphEngine(asset: asset)
        let narrow = try XCTUnwrap(projection.warpBands(for: builder.shell(for: .skirt(length: .knee), positions: engine.positions(for: .neutral))))
        let wide = try XCTUnwrap(projection.warpBands(for: builder.shell(for: .skirt(length: .knee), positions: engine.positions(for: curvy))))
        // The hem flares the same either way; the hips are in the top bands.
        XCTAssertGreaterThan(wide.prefix(5).map(\.width).max() ?? 0, (narrow.prefix(5).map(\.width).max() ?? 0) + 2, "the 2D skirt widens at the hips")
    }

    func testTexturePaddingContinuesTheNearestGarmentColour() {
        // 4×3: row 0 empty; row 1 red at x=1, blue at x=3; row 2 empty.
        var p = [UInt8](repeating: 0, count: 4 * 3 * 4)
        func set(_ x: Int, _ y: Int, _ r: UInt8, _ g: UInt8, _ b: UInt8) {
            let i = (y * 4 + x) * 4
            p[i] = r; p[i + 1] = g; p[i + 2] = b; p[i + 3] = 255
        }
        set(1, 1, 255, 0, 0)
        set(3, 1, 0, 0, 255)
        XCTAssertTrue(AvatarTexturePadding.pad(&p, width: 4, height: 3))
        func pixel(_ x: Int, _ y: Int) -> [UInt8] { Array(p[((y * 4 + x) * 4)..<((y * 4 + x) * 4 + 4)]) }
        XCTAssertEqual(pixel(0, 1), [255, 0, 0, 255], "left margin takes the red")
        XCTAssertEqual(pixel(2, 1), [255, 0, 0, 255], "a gap takes its nearest neighbour (tie goes left)")
        XCTAssertEqual(pixel(0, 0), [255, 0, 0, 255], "empty rows copy the nearest garment row")
        XCTAssertEqual(pixel(3, 2), [0, 0, 255, 255])
        var empty = [UInt8](repeating: 0, count: 16)
        XCTAssertFalse(AvatarTexturePadding.pad(&empty, width: 2, height: 2))
    }

    func testMorphingIsFastEnoughForASlider() throws {
        let asset = try asset()
        let engine = AvatarMorphEngine(asset: asset)
        let builder = AvatarGarmentShellBuilder(asset: asset)
        var shape = AvatarBodyShape.neutral
        for control in AvatarControl.allCases { shape[control] = 0.3 }
        let start = Date()
        for _ in 0..<5 {
            let p = engine.positions(for: shape)
            _ = engine.mesh(named: "body", positions: p)
            _ = builder.shell(for: .top(sleeve: .short), positions: p)
            _ = builder.shell(for: .trousers, positions: p)
        }
        let perUpdate = Date().timeIntervalSince(start) / 5
        print("avatar update: \(Int(perUpdate * 1000)) ms per body + 2 garments (this host)")
        XCTAssertLessThan(perUpdate, 1.0)
    }

    // MARK: Helpers

    private func halfWidth(_ p: [SIMD3<Float>], y: ClosedRange<Float>) -> Float {
        p.filter { y.contains($0.y) && abs($0.x) < 0.3 }.map { abs($0.x) }.max() ?? 0
    }

    private func maxMove(_ a: [SIMD3<Float>], _ b: [SIMD3<Float>], y: ClosedRange<Float>, maxAbsX: Float = 10) -> Float {
        var worst: Float = 0
        for i in a.indices where y.contains(a[i].y) && abs(a[i].x) <= maxAbsX {
            let d = a[i] - b[i]
            worst = max(worst, (d * d).sum().squareRoot())
        }
        return worst
    }
}
