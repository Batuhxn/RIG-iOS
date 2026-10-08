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
        let asset = try loadAsset()
        let started = Date()
        let engine = AvatarMorphEngine(asset: asset)
        let builder = AvatarGarmentShellBuilder(asset: asset)
        let positions = engine.positions(for: shape)
        let shells = builder.shells(for: cuts, positions: positions)
        let layers = zip(cuts, shells).map { cut, mesh in
            AvatarGarmentLayer(id: UUID(), cut: cut, mesh: mesh, texture: texture, colour: .systemTeal)
        }
        return AvatarStageContent(body: engine.mesh(named: "body", positions: positions), garments: layers,
                                  computeMilliseconds: Int(Date().timeIntervalSince(started) * 1000))
    }

    private func render(_ content: AvatarStageContent, mode: AvatarPreviewMode, yaw: Float = 0, size: CGSize = CGSize(width: 240, height: 480)) -> UIImage {
        let coordinator = AvatarStageCoordinator()
        coordinator.show(content, mode: mode)
        coordinator.scene.rootNode.childNodes.forEach { node in
            if node.geometry == nil, node.light == nil, node.camera == nil { node.eulerAngles.y = yaw }
        }
        let camera = coordinator.cameraNode.camera
        camera?.usesOrthographicProjection = true
        camera?.orthographicScale = 0.95
        coordinator.cameraNode.position = SCNVector3(0, 0.88, 4)
        let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        renderer.scene = coordinator.scene
        renderer.pointOfView = coordinator.cameraNode
        coordinator.scene.background.contents = UIColor.white
        return renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
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
        emit("neutral-front", neutral)
        emit("neutral-side", side)
        emit("hips-front", curvy)
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
        emit("outfit-photo", photo)
        emit("outfit-colour", colour)
        emit("dress-curvy", dressed)
        emit("outfit-side", render(outfit, mode: .photo3D, yaw: .pi / 2))
    }

    // MARK: Helpers

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

    /// Prints a small PNG as base64 so CI logs and annotations carry it.
    private func emit(_ name: String, _ image: UIImage) {
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let small = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 240)).image { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: 120, height: 240))
        }
        if let data = small.jpegData(compressionQuality: 0.55) {
            print("AVATAR_SNAPSHOT \(name) \(data.base64EncodedString())")
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
