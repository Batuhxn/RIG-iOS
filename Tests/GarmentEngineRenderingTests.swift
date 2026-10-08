import Metal
import SceneKit
import UIKit
import XCTest
@testable import RIG

/// Garment Engine v1 renders, using the shared helpers of `AvatarRenderingTests`.
extension AvatarRenderingTests {
    /// Garment Engine v1 review: the same striped garments as before, old 2D and old 3D
    /// photo next to the new engine (front, three-quarter, side), on silhouettes 1-3 and one
    /// deliberately extreme but valid body. Failures are kept in the grid, not filtered out.
    func testGarmentEngineComparisonGrid() throws {
        let asset = try loadAsset()
        let library = try GarmentTemplateLibrary.bundled(in: AvatarTestBundle.bundle, for: asset)
        let engine = AvatarOutfitBuilder(asset: asset, templates: library)
        var extreme = AvatarBodyShape.neutral
        extreme[.hips] = 1
        extreme[.waist] = -1
        extreme[.bust] = 1
        extreme[.shoulders] = 1
        extreme[.overall] = 0.8
        var shapes: [AvatarBodyShape] = AvatarStartingSilhouette.all.map(\.shape)
        shapes.append(extreme)
        let tee = Self.stripedTeeCutout(), jeans = Self.trousersCutout(), dress = Self.stripedDressCutout()
        let outfits: [(String, [(AvatarGarmentCut, UIImage)])] = [
            ("engine-separates", [(AvatarGarmentCut.trousers, jeans), (AvatarGarmentCut.top(sleeve: .short), tee)]),
            ("engine-skirt-dress", []),
        ]
        let tile = CGSize(width: 180, height: 360)
        let projection = AvatarFrontProjection(viewWidth: tile.width, viewHeight: tile.height, visibleHeight: 1.9, centreY: 0.88)
        var lastMs = 0
        for (name, separates) in outfits {
            var rows: [[UIImage]] = []
            for (index, shape) in shapes.enumerated() {
                // The second grid alternates skirt and dress rows over the same shapes.
                let garments: [(AvatarGarmentCut, UIImage)] = separates.isEmpty
                    ? (index.isMultiple(of: 2) ? [(AvatarGarmentCut.skirt(length: .knee), dress), (AvatarGarmentCut.top(sleeve: .short), tee)]
                                               : [(AvatarGarmentCut.dress(length: .knee), dress)])
                    : separates
                let textured: [(AvatarGarmentCut, UIImage?)] = garments.map { ($0.0, AvatarGarmentTexture.prepare($0.1).image) }
                let old = try content(shape: shape, garments: textured)
                let started = Date()
                guard let built = engine.build(shape: shape, cuts: garments.map(\.0)) else { return XCTFail("cancelled") }
                lastMs = Int(Date().timeIntervalSince(started) * 1000)
                let layers = zip(garments, built.garments).map { garment, built -> AvatarGarmentLayer in
                    var mesh = built
                    if !mesh.backTriangles.isEmpty {
                        mesh.uvs = GarmentPhotoMapping.uvs(for: mesh, photoSpans: AvatarGarmentTexture.photoSpans(of: garment.1))
                    }
                    return AvatarGarmentLayer(id: UUID(), cut: garment.0, mesh: mesh,
                                       texture: AvatarGarmentTexture.prepare(garment.1).image,
                                       colour: AvatarGarmentTexture.prepare(garment.1).colour)
                }
                let new = AvatarStageContent(body: built.body, bareBody: built.bareBody, garments: layers, computeMilliseconds: lastMs)
                let base = render(try content(shape: shape, garments: []), mode: .flat2D, size: tile)
                let flat = UIGraphicsImageRenderer(size: tile).image { _ in
                    base.draw(at: .zero)
                    for (layer, garment) in zip(old.garments, garments).sorted(by: { $0.0.cut.layer < $1.0.cut.layer }) {
                        if let bands = projection.warpBands(for: layer.mesh) { AvatarGarmentTexture.drawWarped(garment.1, into: bands) }
                    }
                }
                var row: [UIImage] = [flat, render(old, mode: .photo3D, size: tile)]
                for yaw: Float in [0, 0.75, Float.pi / 2] {
                    row.append(render(new, mode: .photo3D, yaw: yaw, size: tile))
                }
                rows.append(row)
            }
            let cell = CGSize(width: 72, height: 144)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let size = CGSize(width: cell.width * 5, height: cell.height * CGFloat(rows.count))
            let grid = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                for (r, row) in rows.enumerated() {
                    for (c, image) in row.enumerated() {
                        image.draw(in: CGRect(x: CGFloat(c) * cell.width, y: CGFloat(r) * cell.height, width: cell.width, height: cell.height))
                    }
                }
            }
            emit(name, grid, width: Int(size.width), height: Int(size.height), quality: 0.6)
        }
        print("AVATAR_METRIC engine_build_ms_last=\(lastMs)")
    }

    /// Gemini review: the back panel should show the fabric's main colour, not the mean,
    /// which turns a red-and-white stripe into pink.
    func testDominantColourIsAFabricColourNotAMixture() throws {
        let stripes = Self.stripedTeeCutout()
        let dominant = try XCTUnwrap(AvatarGarmentTexture.dominantColour(of: stripes))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        XCTAssertTrue(dominant.getRed(&r, green: &g, blue: &b, alpha: &a))
        let isRed = r > 0.6 && g < 0.3 && b < 0.3
        let isWhite = r > 0.85 && g > 0.85 && b > 0.85
        XCTAssertTrue(isRed || isWhite, "dominant colour \(r) \(g) \(b) is one of the stripes")
        var mr: CGFloat = 0, mg: CGFloat = 0, mb: CGFloat = 0
        XCTAssertTrue(AvatarGarmentTexture.averageColour(of: stripes).getRed(&mr, green: &mg, blue: &mb, alpha: &a))
        XCTAssertTrue(mg > 0.3 && mg < 0.85, "while the mean is a pink mixture")
    }
}
