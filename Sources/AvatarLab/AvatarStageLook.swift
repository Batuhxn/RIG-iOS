import SceneKit
import UIKit

/// How the stage draws garments and light. Switchable so review renders can show the
/// Garment Engine v1 look next to the current one under the same camera and morphs.
struct AvatarStageStyle: Equatable, Sendable {
    /// The photo fades into the unknown-region colour over a narrow band of surface
    /// angle (garment normal z 0.35...0.55, about 57°-69° from the camera) instead of
    /// ending at a hard material edge. Nothing is invented: past the band the surface is
    /// the plain unknown-region colour, as before.
    var softSeam = true
    /// A soft studio environment (image-based light: bright above, darker below) in
    /// place of the flat ambient fill that made fabric read as plastic.
    var studioLight = true
    /// Template garments are drawn single-sided outside, with a darker inside, so
    /// necklines, sleeves and hems read as fabric with an inside, not paper.
    var fabricInterior = true
    /// A soft contact shadow under the feet (3D only).
    var groundShadow = true
    /// Studio light levels (used when `studioLight` is on). Chosen from the lighting
    /// study (variant D): a soft environment and a clear key light give the fabric form
    /// without dramatic shadows.
    var environmentIntensity: Float = 0.6
    var keyIntensity: Float = 900
    /// Soft shadows from the key light: a sleeve on the arm, a hem on the trousers.
    var keyShadows = true
    /// The mannequin's albedo (sRGB): a light warm grey dress form, so white and cream
    /// garments stay visible against it (on the earlier near-white form the sides of a
    /// red-and-white tee disappeared).
    var mannequin = SIMD3<Float>(0.80, 0.78, 0.75)
    /// Screen-space ambient occlusion strength (0 = off): contact shading where fabric
    /// meets the body or another garment.
    var occlusion: Float = 0
    /// Template garments darken slightly towards their open edges (hems, cuffs,
    /// necklines), as a turned hem does, so where the fabric ends reads at a glance.
    var hemShading = false

    static let current = AvatarStageStyle()
    static let engineV1 = AvatarStageStyle(softSeam: false, studioLight: false, fabricInterior: false, groundShadow: false,
                                           environmentIntensity: 1.1, keyIntensity: 650, keyShadows: false,
                                           mannequin: SIMD3(0.93, 0.92, 0.90), occlusion: 0, hemShading: false)
}

/// Materials, shaders and generated images of the stage (split from AvatarStageView.swift).
extension AvatarStageCoordinator {
    static func fabric(_ colour: UIColor) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = colour
        material.roughness.contents = 0.85
        material.metalness.contents = 0.0
        material.isDoubleSided = true
        return material
    }

    static func unknownRegion(_ colour: UIColor) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard colour.getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return colour }
        // Only slightly shaded (product decision): it reads as plain fabric, not a hole.
        return UIColor(hue: h, saturation: s * 0.95, brightness: b * 0.95, alpha: 1)
    }

    /// The inside of a garment: its own colour in shadow.
    static func interior(_ colour: UIColor) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard colour.getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return colour }
        return UIColor(hue: h, saturation: s, brightness: b * 0.62, alpha: 1)
    }

    /// Garment-space normal z over which the photo fades out. The lower end matches the
    /// offline front/back panel split (Tools/AvatarAssets/build_garment_templates.py).
    static let seamBand: ClosedRange<Float> = 0.35...0.55

    /// Surface shader for template garments. With `unknown` (the front panel): the photo
    /// fades into that colour where the garment turns away from the camera (garment-space
    /// normal, so the band stays on the fabric while the avatar turns) and near the
    /// photo/plain boundary (channel 1). With `hem`: darker towards open edges (channel 2).
    /// Channels arrive through the roughness and metalness slots, which are then reset to
    /// the fabric's real values. Colours are written into the source (linear, as SceneKit
    /// shades), so no argument binding is involved.
    static func surfaceModifier(unknown: UIColor?, hem: Bool) -> String {
        var body = """
        #pragma body
        float seam = _surface.roughness;
        float hem = _surface.metalness;
        _surface.roughness = 0.85;
        _surface.metalness = 0.0;

        """
        if let unknown {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            if !unknown.getRed(&r, green: &g, blue: &b, alpha: &a) { (r, g, b) = (0.5, 0.5, 0.5) }
            func linear(_ c: CGFloat) -> Double {
                let c = Double(min(max(c, 0), 1))
                return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
            }
            let colour = String(format: "float3(%.5f, %.5f, %.5f)", linear(r), linear(g), linear(b))
            let band = String(format: "%.3f, %.3f", seamBand.lowerBound, seamBand.upperBound)
            body += """
            float3 garmentNormal = normalize((scn_node.inverseModelViewTransform * float4(_surface.normal, 0.0)).xyz);
            float photo = smoothstep(\(band), garmentNormal.z) * seam;
            _surface.diffuse.rgb = mix(\(colour), _surface.diffuse.rgb, photo);

            """
        }
        if hem {
            body += """
            _surface.diffuse.rgb *= mix(\(String(format: "%.3f", hemDarkening)), 1.0, hem);

            """
        }
        return body
    }

    /// How dark the very edge of a hem is, relative to the fabric.
    static let hemDarkening: Float = 0.74
    static let hemWidth: Float = 0.018

    /// 0 on the open edges (hems, cuffs, necklines), rising to 1 over `hemWidth`. Panel
    /// seams are not open edges: seam duplicates are welded by position first.
    static func hemWeights(_ mesh: AvatarMesh) -> [Float] {
        var slot: [SIMD3<UInt32>: Int] = [:]
        let key: [Int] = mesh.positions.map { p in
            let bits = SIMD3(p.x.bitPattern, p.y.bitPattern, p.z.bitPattern)
            if let s = slot[bits] { return s }
            slot[bits] = slot.count
            return slot.count - 1
        }
        var uses: [UInt64: Int] = [:]
        for list in [mesh.triangles, mesh.backTriangles] {
            var t = 0
            while t + 2 < list.count {
                for e in 0..<3 {
                    let a = key[Int(list[t + e])], b = key[Int(list[t + (e + 1) % 3])]
                    uses[UInt64(min(a, b)) << 32 | UInt64(max(a, b)), default: 0] += 1
                }
                t += 3
            }
        }
        var onEdge = Set<Int>()
        for (edge, count) in uses where count == 1 {
            onEdge.insert(Int(edge >> 32))
            onEdge.insert(Int(edge & 0xFFFF_FFFF))
        }
        let edgePoints = mesh.positions.indices.filter { onEdge.contains(key[$0]) }.map { mesh.positions[$0] }
        guard !edgePoints.isEmpty else { return [Float](repeating: 1, count: mesh.positions.count) }
        let grid = HashGrid(points: edgePoints, cell: hemWidth)
        return mesh.positions.indices.map { k in
            if onEdge.contains(key[k]) { return 0 }
            guard let j = grid.nearest(to: mesh.positions[k], within: hemWidth, in: edgePoints) else { return 1 }
            let d = mesh.positions[k] - edgePoints[j]
            let s = min((d * d).sum().squareRoot() / hemWidth, 1)
            return s * s * (3 - 2 * s)
        }
    }

    static func applyOcclusion(_ style: AvatarStageStyle, to camera: SCNCamera) {
        guard style.occlusion > 0 else { return }
        camera.screenSpaceAmbientOcclusionIntensity = CGFloat(style.occlusion)
        camera.screenSpaceAmbientOcclusionRadius = 0.06
        camera.screenSpaceAmbientOcclusionBias = 0.02
        camera.screenSpaceAmbientOcclusionDepthThreshold = 0.1
        camera.screenSpaceAmbientOcclusionNormalThreshold = 0.3
    }

    /// Distance from the photo panel's material boundary, as a 0...1 weight per vertex:
    /// 0 on every vertex the back panel also uses, rising smoothly over `seamWidth`.
    /// With the angle band alone, vertices on the boundary could keep the full photo
    /// beside plain-colour faces (Codex review: 27 on the neutral tee).
    static let seamWidth: Float = 0.035

    static func seamWeights(_ mesh: AvatarMesh) -> [Float] {
        let backUsed = Set(mesh.backTriangles.map(Int.init))
        let backPoints = backUsed.map { mesh.positions[$0] }
        guard !backPoints.isEmpty else { return [Float](repeating: 1, count: mesh.positions.count) }
        let grid = HashGrid(points: backPoints, cell: seamWidth)
        return mesh.positions.indices.map { k in
            if backUsed.contains(k) { return 0 }
            guard let j = grid.nearest(to: mesh.positions[k], within: seamWidth, in: backPoints) else { return 1 }
            let d = mesh.positions[k] - backPoints[j]
            let s = min((d * d).sum().squareRoot() / seamWidth, 1)
            return s * s * (3 - 2 * s)
        }
    }

    /// Identity ramp: the roughness slot samples it with channel 1, so the shader reads
    /// the seam weight back (and then sets the real roughness).
    static let seamRamp: UIImage = {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let size = CGSize(width: 256, height: 1)
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            for x in 0..<256 {
                UIColor(white: CGFloat(x) / 255, alpha: 1).setFill()
                context.fill(CGRect(x: x, y: 0, width: 1, height: 1))
            }
        }
    }()

    /// Soft studio light for image-based lighting: bright overhead, a light horizon and
    /// a darker floor, the same all the way round (no direction to get wrong).
    static let studioEnvironment: UIImage = {
        let size = CGSize(width: 64, height: 32)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let colours = [UIColor(white: 1.0, alpha: 1), UIColor(white: 0.86, alpha: 1),
                           UIColor(white: 0.62, alpha: 1), UIColor(white: 0.30, alpha: 1)].map(\.cgColor)
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colours as CFArray,
                                            locations: [0, 0.42, 0.55, 1]) else { return }
            context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
        }
    }()

    /// A soft dark ellipse on the floor where the feet stand.
    static func contactShadow() -> SCNNode {
        let plane = SCNPlane(width: 0.75, height: 0.42)
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = shadowImage
        material.writesToDepthBuffer = false
        material.blendMode = .alpha
        plane.materials = [material]
        let node = SCNNode(geometry: plane)
        node.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        node.renderingOrder = -1
        node.castsShadow = false
        return node
    }

    static let shadowImage: UIImage = {
        let size = CGSize(width: 128, height: 128)
        return UIGraphicsImageRenderer(size: size).image { context in
            let colours = [UIColor(white: 0, alpha: 0.28), UIColor(white: 0, alpha: 0.10), UIColor(white: 0, alpha: 0)].map(\.cgColor)
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colours as CFArray,
                                            locations: [0, 0.45, 1]) else { return }
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            context.cgContext.drawRadialGradient(gradient, startCenter: centre, startRadius: 0, endCenter: centre,
                                                 endRadius: size.width / 2, options: [])
        }
    }()
}
