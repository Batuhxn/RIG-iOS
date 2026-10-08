import Metal
import SceneKit
import UIKit
import XCTest
@testable import RIG

/// Renders the avatar offscreen with the app's own SceneKit stage and checks the
/// pixels: the body appears, morphs are visible, garments are drawn with their
/// photo, front and side views differ. Simulator rendering, not iPhone
/// performance. Small thumbnails are printed (AVATAR_SNAPSHOT lines) so a CI
/// run can be inspected without downloading artifacts.
@MainActor
final class AvatarRenderingTests: XCTestCase {
    private static var asset: AvatarBodyAsset?

    private func loadAsset() throws -> AvatarBodyAsset {
        if let asset = Self.asset { return asset }
        let started = Date()
        let asset = try AvatarBodyAsset.bundled(in: AvatarTestBundle.bundle)
        print("AVATAR_METRIC asset_load_ms=\(Int(Date().timeIntervalSince(started) * 1000))")
        Self.asset = asset
        return asset
    }

    private func content(shape: AvatarBodyShape, cuts: [AvatarGarmentCut], texture: UIImage?) throws -> AvatarStageContent {
        try content(shape: shape, garments: cuts.map { ($0, texture) })
    }

    private func content(shape: AvatarBodyShape, garments: [(AvatarGarmentCut, UIImage?)]) throws -> AvatarStageContent {
        let asset = try loadAsset()
        let started = Date()
        let engine = AvatarMorphEngine(asset: asset)
        let builder = AvatarGarmentShellBuilder(asset: asset)
        let positions = engine.positions(for: shape)
        let shells = builder.shells(for: garments.map(\.0), positions: positions)
        let layers = zip(garments, shells).map { garment, mesh in
            AvatarGarmentLayer(id: UUID(), cut: garment.0, mesh: mesh, texture: garment.1,
                               colour: garment.1.map { AvatarGarmentTexture.averageColour(of: $0) } ?? .systemTeal)
        }
        return AvatarStageContent(body: engine.mesh(named: "body", positions: positions), garments: layers,
                                  computeMilliseconds: Int(Date().timeIntervalSince(started) * 1000))
    }

    private func render(_ content: AvatarStageContent, mode: AvatarPreviewMode, yaw: Float = 0, size: CGSize = CGSize(width: 240, height: 480)) -> UIImage {
        let coordinator = AvatarStageCoordinator()
        coordinator.show(content, mode: mode)
        return coordinator.snapshot(size: size, yaw: yaw)
    }

    func testAvatarRendersAndMorphsAreVisible() throws {
        let neutral = render(try content(shape: .neutral, cuts: [], texture: nil), mode: .colour3D)
        var wide = AvatarBodyShape.neutral
        wide[.hips] = 1
        wide[.seat] = 1
        let curvy = render(try content(shape: wide, cuts: [], texture: nil), mode: .colour3D)
        let side = render(try content(shape: .neutral, cuts: [], texture: nil), mode: .colour3D, yaw: .pi / 2)

        let n = try XCTUnwrap(PixelStats(neutral))
        XCTAssertGreaterThan(n.nonBackgroundFraction, 0.05, "the body is drawn")
        let hipRow = Int(Double(neutral.size.height) * 0.50)
        let c = try XCTUnwrap(PixelStats(curvy))
        XCTAssertGreaterThan(c.width(atRow: hipRow), n.width(atRow: hipRow) + 2, "wider hips are visible in pixels")
        let s = try XCTUnwrap(PixelStats(side))
        XCTAssertNotEqual(s.nonBackgroundFraction, n.nonBackgroundFraction, accuracy: 0.002, "the side view differs from the front")
        attach("neutral-front", neutral)
        attach("neutral-side", side)
        attach("hips-front", curvy)
    }

    func testGarmentPhotoIsDrawnOnTheBody() throws {
        let stripes = Self.stripedGarment()
        let outfit = try content(shape: .neutral, cuts: [.top(sleeve: .short), .trousers, .shoes], texture: stripes)
        print("AVATAR_METRIC body_plus_3_garments_ms=\(outfit.computeMilliseconds)")
        let photo = render(outfit, mode: .photo3D)
        let colour = render(outfit, mode: .colour3D)
        let stats = try XCTUnwrap(PixelStats(photo))
        XCTAssertGreaterThan(stats.fraction { r, g, b in r > 150 && g < 90 && b < 90 }, 0.005, "red stripes from the photo appear")
        let flat = try XCTUnwrap(PixelStats(colour))
        XCTAssertLessThan(flat.fraction { r, g, b in r > 150 && g < 90 && b < 90 }, 0.001, "colour mode draws no photo")
        var curvy = AvatarBodyShape.neutral
        curvy[.hips] = 1
        curvy[.waist] = -0.6
        curvy[.bust] = 0.8
        let dressed = render(try content(shape: curvy, cuts: [.dress(length: .knee), .shoes], texture: stripes), mode: .photo3D)
        attach("outfit-photo", photo)
        attach("outfit-colour", colour)
        attach("dress-curvy", dressed)
        attach("outfit-side", render(outfit, mode: .photo3D, yaw: .pi / 2))
    }

    /// The same outfit in all three preview modes, for the product comparison.
    func testThreePreviewModesOnOneOutfit() throws {
        let tee = Self.teeCutout()
        let jeans = Self.trousersCutout()
        var shape = AvatarBodyShape.neutral
        shape[.hips] = 0.3
        let outfit = try content(shape: shape, garments: [(.top(sleeve: .short), AvatarGarmentTexture.prepare(tee).image),
                                                          (.trousers, AvatarGarmentTexture.prepare(jeans).image), (.shoes, nil)])
        let size = CGSize(width: 240, height: 480)
        let flatBody = try content(shape: shape, garments: [])
        let base = render(flatBody, mode: .flat2D, size: size)
        let projection = AvatarFrontProjection(viewWidth: size.width, viewHeight: size.height, visibleHeight: 1.9, centreY: 0.88)
        let flat = UIGraphicsImageRenderer(size: size).image { _ in
            base.draw(at: .zero)
            // Innermost first, as the app draws them: trousers under the tee.
            for (layer, photo) in zip(outfit.garments, [tee, jeans]).sorted(by: { $0.0.cut.layer < $1.0.cut.layer }) {
                if let bands = projection.warpBands(for: layer.mesh) {
                    AvatarGarmentTexture.drawWarped(photo, into: bands)
                }
            }
        }
        emit("mode-2d", flat)
        emit("mode-3d-photo", render(outfit, mode: .photo3D, size: size))
        emit("mode-3d-colour", render(outfit, mode: .colour3D, size: size))
        emit("mode-3d-photo-turned", render(outfit, mode: .photo3D, yaw: 0.6, size: size))
    }

    /// The product review grid: rows are body shapes, columns are the 2D
    /// preview and the 3D view from the front, three-quarter and side. Striped
    /// garments show whether the warp breaks lines or tears edges.
    func testComparisonGridAcrossSilhouettesAndAngles() throws {
        let tee = Self.stripedTeeCutout()
        let jeans = Self.trousersCutout()
        let dress = Self.stripedDressCutout()
        var curvy = AvatarBodyShape.neutral
        curvy[.hips] = 1
        curvy[.waist] = -0.7
        curvy[.bust] = 0.8
        let separates: [(AvatarGarmentCut, UIImage)] = [(AvatarGarmentCut.trousers, jeans), (AvatarGarmentCut.top(sleeve: .short), tee)]
        var rows: [(AvatarBodyShape, [(AvatarGarmentCut, UIImage)])] = []
        for silhouette in AvatarStartingSilhouette.all {
            rows.append((silhouette.shape, separates))
        }
        rows.append((curvy, [(AvatarGarmentCut.dress(length: .knee), dress)]))
        let tile = CGSize(width: 200, height: 400)
        var tiles: [[UIImage]] = []
        for (shape, garments) in rows {
            var dressed: [(AvatarGarmentCut, UIImage?)] = garments.map { garment -> (AvatarGarmentCut, UIImage?) in
                (garment.0, AvatarGarmentTexture.prepare(garment.1).image)
            }
            dressed.append((AvatarGarmentCut.shoes, nil))
            let outfit = try content(shape: shape, garments: dressed)
            let base = render(try content(shape: shape, garments: []), mode: .flat2D, size: tile)
            let projection = AvatarFrontProjection(viewWidth: tile.width, viewHeight: tile.height, visibleHeight: 1.9, centreY: 0.88)
            let flat = UIGraphicsImageRenderer(size: tile).image { _ in
                base.draw(at: .zero)
                for (layer, garment) in zip(outfit.garments, garments) {
                    let photo: UIImage = garment.1
                    if let bands = projection.warpBands(for: layer.mesh) { AvatarGarmentTexture.drawWarped(photo, into: bands) }
                }
            }
            var row: [UIImage] = [flat]
            for yaw: Float in [0, 0.75, Float.pi / 2] {
                row.append(render(outfit, mode: .photo3D, yaw: yaw, size: tile))
            }
            tiles.append(row)
        }
        let cell = CGSize(width: 90, height: 180)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let grid = UIGraphicsImageRenderer(size: CGSize(width: cell.width * 4, height: cell.height * CGFloat(tiles.count)), format: format).image { _ in
            for (r, row) in tiles.enumerated() {
                for (c, image) in row.enumerated() {
                    image.draw(in: CGRect(x: CGFloat(c) * cell.width, y: CGFloat(r) * cell.height, width: cell.width, height: cell.height))
                }
            }
        }
        emit("grid", grid, width: Int(cell.width * 4), height: Int(cell.height * CGFloat(tiles.count)), quality: 0.6)
    }

    // MARK: Helpers

    /// A flat-lay tee in red and white horizontal stripes.
    private static func stripedTeeCutout() -> UIImage {
        let size = CGSize(width: 300, height: 300)
        return UIGraphicsImageRenderer(size: size).image { context in
            teePath().addClip()
            for i in 0..<15 {
                (i.isMultiple(of: 2) ? UIColor(red: 0.8, green: 0.1, blue: 0.15, alpha: 1) : .white).setFill()
                context.fill(CGRect(x: 0, y: CGFloat(i) * 20, width: 300, height: 20))
            }
        }
    }

    /// A flat-lay sleeveless dress with vertical navy and yellow stripes.
    private static func stripedDressCutout() -> UIImage {
        let size = CGSize(width: 240, height: 420)
        return UIGraphicsImageRenderer(size: size).image { context in
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 70, y: 5)); path.addLine(to: CGPoint(x: 170, y: 5))
            path.addLine(to: CGPoint(x: 185, y: 150)); path.addLine(to: CGPoint(x: 235, y: 415))
            path.addLine(to: CGPoint(x: 5, y: 415)); path.addLine(to: CGPoint(x: 55, y: 150)); path.close()
            path.addClip()
            for i in 0..<12 {
                (i.isMultiple(of: 2) ? UIColor(red: 0.1, green: 0.15, blue: 0.4, alpha: 1) : UIColor(red: 0.95, green: 0.8, blue: 0.2, alpha: 1)).setFill()
                context.fill(CGRect(x: CGFloat(i) * 20, y: 0, width: 20, height: 420))
            }
        }
    }

    private static func teePath() -> UIBezierPath {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 110, y: 10)); path.addLine(to: CGPoint(x: 190, y: 10))
        path.addLine(to: CGPoint(x: 290, y: 60)); path.addLine(to: CGPoint(x: 260, y: 120))
        path.addLine(to: CGPoint(x: 230, y: 100)); path.addLine(to: CGPoint(x: 230, y: 295))
        path.addLine(to: CGPoint(x: 70, y: 295)); path.addLine(to: CGPoint(x: 70, y: 100))
        path.addLine(to: CGPoint(x: 40, y: 120)); path.addLine(to: CGPoint(x: 10, y: 60)); path.close()
        return path
    }

    /// A flat-lay T-shirt cutout: navy, white chest stripe, transparent background.
    private static func teeCutout() -> UIImage {
        let size = CGSize(width: 300, height: 300)
        return UIGraphicsImageRenderer(size: size).image { context in
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 110, y: 10)); path.addLine(to: CGPoint(x: 190, y: 10))
            path.addLine(to: CGPoint(x: 290, y: 60)); path.addLine(to: CGPoint(x: 260, y: 120))
            path.addLine(to: CGPoint(x: 230, y: 100)); path.addLine(to: CGPoint(x: 230, y: 295))
            path.addLine(to: CGPoint(x: 70, y: 295)); path.addLine(to: CGPoint(x: 70, y: 100))
            path.addLine(to: CGPoint(x: 40, y: 120)); path.addLine(to: CGPoint(x: 10, y: 60)); path.close()
            UIColor(red: 0.1, green: 0.15, blue: 0.4, alpha: 1).setFill()
            path.fill()
            path.addClip()
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 120, width: 300, height: 26))
        }
    }

    /// A flat-lay trousers cutout in denim blue.
    private static func trousersCutout() -> UIImage {
        let size = CGSize(width: 200, height: 400)
        return UIGraphicsImageRenderer(size: size).image { _ in
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 20, y: 5)); path.addLine(to: CGPoint(x: 180, y: 5))
            path.addLine(to: CGPoint(x: 195, y: 395)); path.addLine(to: CGPoint(x: 115, y: 395))
            path.addLine(to: CGPoint(x: 100, y: 120)); path.addLine(to: CGPoint(x: 85, y: 395))
            path.addLine(to: CGPoint(x: 5, y: 395)); path.close()
            UIColor(red: 0.25, green: 0.4, blue: 0.62, alpha: 1).setFill()
            path.fill()
        }
    }

    /// A synthetic "garment photo": red and blue stripes, transparent corners.
    private static func stripedGarment() -> UIImage {
        let size = CGSize(width: 200, height: 240)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            for i in 0..<12 {
                (i.isMultiple(of: 2) ? UIColor.red : UIColor.blue).setFill()
                context.fill(CGRect(x: 0, y: CGFloat(i) * 20, width: size.width, height: 20))
            }
        }
        return AvatarGarmentTexture.prepare(image).image
    }

    /// Keeps an image in the result bundle only (the log carries the mode and grid images).
    private func attach(_ name: String, _ image: UIImage) {
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Prints a small PNG as base64 so CI logs and annotations carry it.
    private func emit(_ name: String, _ image: UIImage, width: Int = 120, height: Int = 240, quality: CGFloat = 0.5) {
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let small = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        // Annotations hold about 4 KB of text, so the JPEG goes out in numbered chunks.
        if let data = small.jpegData(compressionQuality: quality) {
            let text = data.base64EncodedString()
            var start = text.startIndex
            var part = 0
            while start < text.endIndex {
                let end = text.index(start, offsetBy: 3800, limitedBy: text.endIndex) ?? text.endIndex
                print("AVATAR_SNAPSHOT \(name).\(part) \(text[start..<end])")
                start = end
                part += 1
            }
        }
    }
}

/// Counts non-white pixels of a rendered image.
private struct PixelStats {
    let width: Int
    let height: Int
    let pixels: [UInt8]

    init?(_ image: UIImage) {
        guard let cg = image.cgImage else { return nil }
        width = cg.width
        height = cg.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let ok: Bool = buffer.withUnsafeMutableBytes { raw in
            guard let context = CGContext(data: raw.baseAddress, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: cg.width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
            return true
        }
        guard ok else { return nil }
        pixels = buffer
    }

    private func isBackground(_ i: Int) -> Bool { pixels[i] > 245 && pixels[i + 1] > 245 && pixels[i + 2] > 245 }

    var nonBackgroundFraction: Double { fraction { r, g, b in !(r > 245 && g > 245 && b > 245) } }

    func fraction(_ test: (UInt8, UInt8, UInt8) -> Bool) -> Double {
        var count = 0
        for i in stride(from: 0, to: pixels.count, by: 4) where test(pixels[i], pixels[i + 1], pixels[i + 2]) { count += 1 }
        return Double(count) / Double(width * height)
    }

    /// Span of non-background pixels in a row, ignoring the outer 20% (arms).
    func width(atRow row: Int) -> Int {
        let start = width / 5, end = width - width / 5
        var first = -1, last = -1
        for x in start..<end where !isBackground((row * width + x) * 4) {
            if first < 0 { first = x }
            last = x
        }
        return first < 0 ? 0 : last - first
    }
}
