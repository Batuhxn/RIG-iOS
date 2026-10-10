import Metal
import SceneKit
import UIKit
import XCTest
@testable import RIG

/// RiG Atelier visual regression matrix: every Garment Engine template on silhouettes
/// 1-3 and one extreme but valid body, from the front, three-quarter, side and
/// three-quarter back, with striped and plain fabric, drawn once in the Garment Engine
/// v1 stage style and once in the current one. Nothing is filtered: the extreme body
/// and the back views stay in.
///
/// Full-size PNGs go to `RIG_RENDER_DIR` when CI sets it (`TEST_RUNNER_RIG_RENDER_DIR`);
/// the result bundle keeps them as attachments either way. Camera, lights per style,
/// morphs and garments are identical across the two styles.
extension AvatarRenderingTests {
    static let matrixYaws: [(String, Float)] = [("front", 0), ("three-quarter", .pi / 4), ("side", .pi / 2), ("back-three-quarter", 3 * .pi / 4)]
    static let matrixBackground = UIColor(red: 0.949, green: 0.949, blue: 0.969, alpha: 1)  // systemGroupedBackground, light

    static func matrixShapes() -> [(String, AvatarBodyShape)] {
        var extreme = AvatarBodyShape.neutral
        extreme[.hips] = 1
        extreme[.waist] = -1
        extreme[.bust] = 1
        extreme[.shoulders] = 1
        extreme[.overall] = 0.8
        return AvatarStartingSilhouette.all.map { ($0.id, $0.shape) } + [("extreme", extreme)]
    }

    func testAtelierRenderMatrix() throws {
        let asset = try loadAsset()
        let library = try GarmentTemplateLibrary.bundled(in: AvatarTestBundle.bundle, for: asset)
        let engine = AvatarOutfitBuilder(asset: asset, templates: library)
        let fabrics: [(String, tee: UIImage, dress: UIImage)] = [
            ("stripes", Self.stripedTeeCutout(), Self.stripedDressCutout()),
            ("plain", Self.plainTeeCutout(), Self.plainDressCutout()),
        ]
        let jeans = Self.trousersCutout()
        let styles: [(String, AvatarStageStyle)] = [("v1", .engineV1), ("atelier", .current)]
        let tile = CGSize(width: 180, height: 360)
        var timings: [Int] = []
        for (fabricName, tee, dress) in fabrics {
            let outfits: [(String, [(AvatarGarmentCut, UIImage)])] = [
                ("separates", [(.trousers, jeans), (.top(sleeve: .short), tee)]),
                ("skirt", [(.skirt(length: .knee), dress), (.top(sleeve: .short), tee)]),
                ("dress", [(.dress(length: .knee), dress)]),
            ]
            for (outfitName, garments) in outfits {
                var grids: [String: [[UIImage]]] = [:]
                for (_, shape) in Self.matrixShapes() {
                    let started = Date()
                    guard let built = engine.build(shape: shape, cuts: garments.map(\.0)) else { return XCTFail("cancelled") }
                    timings.append(Int(Date().timeIntervalSince(started) * 1000))
                    let content = Self.stageContent(built: built, garments: garments)
                    for (styleName, style) in styles {
                        let coordinator = AvatarStageCoordinator(style: style)
                        coordinator.show(content, mode: .photo3D)
                        let row = Self.matrixYaws.map { coordinator.snapshot(size: tile, yaw: $0.1, background: Self.matrixBackground) }
                        grids[styleName, default: []].append(row)
                    }
                }
                for (styleName, _) in styles {
                    let grid = Self.compose(grids[styleName] ?? [], tile: tile)
                    try saveRender("matrix_\(outfitName)_\(fabricName)_\(styleName)", grid)
                }
            }
        }
        print("AVATAR_METRIC atelier_matrix_build_ms_max=\(timings.max() ?? 0)")
    }

    /// The same garments as the app builds them: engine meshes, photo UVs on templates.
    static func stageContent(built: (body: AvatarMesh, bareBody: AvatarMesh, garments: [AvatarMesh]),
                             garments: [(AvatarGarmentCut, UIImage)]) -> AvatarStageContent {
        let layers = zip(garments, built.garments).map { garment, built -> AvatarGarmentLayer in
            var mesh = built
            if !mesh.backTriangles.isEmpty {
                mesh.uvs = GarmentPhotoMapping.uvs(for: mesh, photoSpans: AvatarGarmentTexture.photoSpans(of: garment.1))
            }
            let prepared = AvatarGarmentTexture.prepare(garment.1)
            return AvatarGarmentLayer(id: UUID(), cut: garment.0, mesh: mesh, texture: prepared.image, colour: prepared.colour)
        }
        return AvatarStageContent(body: built.body, bareBody: built.bareBody, garments: layers, computeMilliseconds: 0)
    }

    static func compose(_ rows: [[UIImage]], tile: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let columns = rows.map(\.count).max() ?? 0
        let size = CGSize(width: tile.width * CGFloat(columns), height: tile.height * CGFloat(rows.count))
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            for (r, row) in rows.enumerated() {
                for (c, image) in row.enumerated() {
                    image.draw(in: CGRect(x: CGFloat(c) * tile.width, y: CGFloat(r) * tile.height, width: tile.width, height: tile.height))
                }
            }
        }
    }

    /// Writes a PNG into `RIG_RENDER_DIR` (when set) and keeps it in the result bundle.
    func saveRender(_ name: String, _ image: UIImage) throws {
        attach(name, image)
        guard let dir = ProcessInfo.processInfo.environment["RIG_RENDER_DIR"], !dir.isEmpty else { return }
        let data = try XCTUnwrap(image.pngData())
        try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    /// The striped tee's outline in one navy.
    static func plainTeeCutout() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 300, height: 300)).image { _ in
            UIColor(red: 0.16, green: 0.22, blue: 0.38, alpha: 1).setFill()
            teePath().fill()
        }
    }

    /// The striped dress's outline in one terracotta.
    static func plainDressCutout() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 240, height: 420)).image { _ in
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 70, y: 5)); path.addLine(to: CGPoint(x: 170, y: 5))
            path.addLine(to: CGPoint(x: 185, y: 150)); path.addLine(to: CGPoint(x: 235, y: 415))
            path.addLine(to: CGPoint(x: 5, y: 415)); path.addLine(to: CGPoint(x: 55, y: 150)); path.close()
            UIColor(red: 0.72, green: 0.38, blue: 0.27, alpha: 1).setFill()
            path.fill()
        }
    }
}
