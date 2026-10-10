import Metal
import SceneKit
import SwiftUI
import UIKit

/// Draws the avatar with SceneKit. SceneKit is deprecated for new development
/// but supported on the iOS 17 floor and needs no dependency; everything it
/// draws comes from `AvatarMesh`, so a RealityKit or Metal renderer can replace
/// this file without touching the body or garment code (docs/AVATAR_LAB.md).
struct AvatarStageView: UIViewRepresentable {
    let content: AvatarStageContent?
    let mode: AvatarPreviewMode
    /// Front orthographic camera for the 2D overlay; must match `AvatarFrontProjection`.
    let flatProjection: AvatarFrontProjection?
    /// Called (on the main queue) when the 3D camera turns to, or away from, the back.
    var onBackViewChange: (Bool) -> Void = { _ in }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.autoenablesDefaultLighting = false
        view.scene = context.coordinator.scene
        view.pointOfView = context.coordinator.cameraNode
        view.accessibilityLabel = "Avatar preview"
        context.coordinator.backWatcher.onChange = onBackViewChange
        view.delegate = context.coordinator.backWatcher
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        let coordinator = context.coordinator
        coordinator.configureCamera(flat: flatProjection, in: view)
        if let content {
            coordinator.show(content, mode: mode)
        }
    }

    func makeCoordinator() -> AvatarStageCoordinator { AvatarStageCoordinator() }

    typealias Coordinator = AvatarStageCoordinator
}

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

    static let current = AvatarStageStyle()
    static let engineV1 = AvatarStageStyle(softSeam: false, studioLight: false, fabricInterior: false, groundShadow: false,
                                           environmentIntensity: 1.1, keyIntensity: 650, keyShadows: false,
                                           mannequin: SIMD3(0.93, 0.92, 0.90))
}

/// Owns the SceneKit scene; rebuilt geometry is swapped in on every update.
@MainActor
final class AvatarStageCoordinator {
    let scene = SCNScene()
    let cameraNode = SCNNode()
    let backWatcher = AvatarBackViewWatcher()
    let style: AvatarStageStyle
    private let avatarNode = SCNNode()
    private var bodyNode: SCNNode?
    private var garmentNodes: [SCNNode] = []
    private var shadowNode: SCNNode?
    private var wasFlat: Bool?
    private var shown: (content: UUID, mode: AvatarPreviewMode)?

    init(style: AvatarStageStyle = .current) {
        self.style = style
        let camera = SCNCamera()
        camera.fieldOfView = 30
        camera.zNear = 0.05
        camera.zFar = 20
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)
        scene.rootNode.addChildNode(avatarNode)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = style.studioLight ? CGFloat(style.keyIntensity) : 900
        key.eulerAngles = SCNVector3(-0.5, 0.45, 0)
        if style.keyShadows, let light = key.light {
            light.castsShadow = true
            light.shadowMode = .deferred
            light.shadowMapSize = CGSize(width: 2048, height: 2048)
            light.shadowSampleCount = 16
            light.shadowRadius = 6
            light.shadowColor = UIColor(white: 0, alpha: 0.32)
            light.automaticallyAdjustsShadowProjection = true
            light.shadowBias = 0.02
        }
        scene.rootNode.addChildNode(key)
        if style.studioLight {
            scene.lightingEnvironment.contents = Self.studioEnvironment
            scene.lightingEnvironment.intensity = CGFloat(style.environmentIntensity)
        } else {
            let fill = SCNNode()
            fill.light = SCNLight()
            fill.light?.type = .ambient
            fill.light?.intensity = 420
            scene.rootNode.addChildNode(fill)
        }
        let rim = SCNNode()
        rim.light = SCNLight()
        rim.light?.type = .directional
        rim.light?.intensity = style.studioLight ? 250 : 350
        rim.eulerAngles = SCNVector3(-0.2, .pi, 0)
        scene.rootNode.addChildNode(rim)
    }

    func configureCamera(flat: AvatarFrontProjection?, in view: SCNView) {
        let isFlat = flat != nil
        guard let camera = cameraNode.camera else { return }
        if let flat {
            camera.usesOrthographicProjection = true
            camera.projectionDirection = .vertical
            camera.orthographicScale = Double(flat.visibleHeight / 2)
            cameraNode.position = SCNVector3(0, flat.centreY, 4)
            cameraNode.eulerAngles = SCNVector3Zero
            avatarNode.eulerAngles = SCNVector3Zero
            view.allowsCameraControl = false
            view.pointOfView = cameraNode
        } else if wasFlat != false {
            camera.usesOrthographicProjection = false
            cameraNode.position = SCNVector3(0, 0.92, 3.7)
            cameraNode.eulerAngles = SCNVector3Zero
            view.allowsCameraControl = true
            view.defaultCameraController.interactionMode = .orbitTurntable
            view.defaultCameraController.target = SCNVector3(0, 0.9, 0)
            view.defaultCameraController.maximumVerticalAngle = 25
            view.defaultCameraController.minimumVerticalAngle = -10
            view.pointOfView = cameraNode
        }
        wasFlat = isFlat
    }

    func show(_ content: AvatarStageContent, mode: AvatarPreviewMode) {
        // SwiftUI updates the view for unrelated state too; only rebuild on new geometry.
        if let shown, shown.content == content.id, shown.mode == mode { return }
        shown = (content.id, mode)
        let body = node(for: mode == .flat2D ? (content.bareBody ?? content.body) : content.body, materials: [skinMaterial])
        bodyNode?.removeFromParentNode()
        avatarNode.addChildNode(body)
        bodyNode = body

        shadowNode?.removeFromParentNode()
        shadowNode = nil
        if style.groundShadow, mode != .flat2D, let floor = content.body.positions.map(\.y).min() {
            let shadow = Self.contactShadow()
            shadow.position = SCNVector3(0, floor + 0.002, 0.01)
            avatarNode.addChildNode(shadow)
            shadowNode = shadow
        }

        garmentNodes.forEach { $0.removeFromParentNode() }
        garmentNodes = []
        guard mode != .flat2D else { return }
        for layer in content.garments where !layer.mesh.isEmpty {
            // Template garments have a back panel; the older shells are one body-hugging layer.
            let isTemplate = !layer.mesh.backTriangles.isEmpty
            let unknown = Self.unknownRegion(layer.colour)
            let front = Self.fabric(layer.colour)
            if mode == .photo3D, let texture = layer.texture {
                front.diffuse.contents = texture
                front.diffuse.wrapS = .clamp
                front.diffuse.wrapT = .clamp
            }
            // The back panel is what a single front photo cannot show: it gets the
            // garment's own main colour, slightly shaded, never an invented print.
            let back = Self.fabric(unknown)
            var seam: [Float]?
            if isTemplate, style.softSeam {
                seam = Self.seamWeights(layer.mesh)
                front.roughness.contents = Self.seamRamp
                front.roughness.mappingChannel = 1
                front.roughness.wrapS = .clamp
                front.shaderModifiers = [.surface: Self.softSeamModifier(unknown)]
            }
            let garment = node(for: layer.mesh, materials: [front, back], second: seam)
            garment.renderingOrder = layer.cut.layer
            avatarNode.addChildNode(garment)
            garmentNodes.append(garment)
            // Template triangles wind outward (GarmentDeformer), so culling is safe for them.
            // The inside is its own surface: reversed triangles and normals pointing in, so
            // it is lit as the inside of the fabric rather than as a face turned away
            // (which rendered almost black).
            if isTemplate, style.fabricInterior {
                front.isDoubleSided = false
                back.isDoubleSided = false
                let inside = Self.fabric(Self.interior(unknown))
                inside.isDoubleSided = false
                var inner = layer.mesh
                inner.normals = inner.normals.map { -$0 }
                inner.triangles = GarmentDeformer.reversed(inner.triangles + inner.backTriangles)
                inner.backTriangles = []
                let lining = node(for: inner, materials: [inside])
                lining.renderingOrder = layer.cut.layer
                avatarNode.addChildNode(lining)
                garmentNodes.append(lining)
            }
        }
    }

    /// Renders the current scene offscreen from the front (or turned by `yaw`),
    /// orthographic, on a plain background (white by default): onboarding thumbnails and tests.
    func snapshot(size: CGSize, yaw: Float = 0, background: UIColor = .white) -> UIImage {
        avatarNode.eulerAngles = SCNVector3(0, yaw, 0)
        let camera = SCNCamera()
        camera.usesOrthographicProjection = true
        camera.orthographicScale = 0.95
        camera.zNear = 0.05
        camera.zFar = 20
        let eye = SCNNode()
        eye.camera = camera
        eye.position = SCNVector3(0, 0.88, 4)
        scene.rootNode.addChildNode(eye)
        let previousBackground = scene.background.contents
        scene.background.contents = background
        defer {
            eye.removeFromParentNode()
            scene.background.contents = previousBackground
            avatarNode.eulerAngles = SCNVector3Zero
        }
        let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        renderer.scene = scene
        renderer.pointOfView = eye
        return renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
    }

    private lazy var skinMaterial: SCNMaterial = {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        let tone = style.mannequin
        material.diffuse.contents = UIColor(red: CGFloat(tone.x), green: CGFloat(tone.y), blue: CGFloat(tone.z), alpha: 1)  // a dress form, not a skin tone
        material.roughness.contents = 0.7
        material.metalness.contents = 0.0
        return material
    }()

    private static func fabric(_ colour: UIColor) -> SCNMaterial {
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

    /// Surface shader for a template's front panel: the photo fades into `unknown` where
    /// the garment turns away from the camera. It uses the garment-space normal, so the
    /// band stays on the fabric while the avatar turns. The colour is written into the
    /// source (linear, as SceneKit shades), so no argument binding is involved.
    static func softSeamModifier(_ unknown: UIColor) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        if !unknown.getRed(&r, green: &g, blue: &b, alpha: &a) { (r, g, b) = (0.5, 0.5, 0.5) }
        func linear(_ c: CGFloat) -> Double {
            let c = Double(min(max(c, 0), 1))
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        let colour = String(format: "float3(%.5f, %.5f, %.5f)", linear(r), linear(g), linear(b))
        let band = String(format: "%.3f, %.3f", seamBand.lowerBound, seamBand.upperBound)
        return """
        #pragma body
        float seam = _surface.roughness;
        _surface.roughness = 0.85;
        float3 garmentNormal = normalize((scn_node.inverseModelViewTransform * float4(_surface.normal, 0.0)).xyz);
        float photo = smoothstep(\(band), garmentNormal.z) * seam;
        _surface.diffuse.rgb = mix(\(colour), _surface.diffuse.rgb, photo);
        """
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
    private static func contactShadow() -> SCNNode {
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

    private static let shadowImage: UIImage = {
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

    /// One geometry; the back panel, when there is one, is a second element with its
    /// own material.
    /// `second`, when given, is a per-vertex value carried in texture channel 1 (the
    /// soft seam's distance weight).
    private func node(for mesh: AvatarMesh, materials: [SCNMaterial], second: [Float]? = nil) -> SCNNode {
        let vertices = mesh.positions.map { SCNVector3($0.x, $0.y, $0.z) }
        let normals = mesh.normals.map { SCNVector3($0.x, $0.y, $0.z) }
        let uvs = mesh.uvs.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) }
        var elements = [SCNGeometryElement(indices: mesh.triangles, primitiveType: .triangles)]
        if !mesh.backTriangles.isEmpty {
            elements.append(SCNGeometryElement(indices: mesh.backTriangles, primitiveType: .triangles))
        }
        var sources = [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals),
                       SCNGeometrySource(textureCoordinates: uvs)]
        if let second, second.count == mesh.positions.count {
            sources.append(SCNGeometrySource(textureCoordinates: second.map { CGPoint(x: CGFloat($0), y: 0.5) }))
        }
        let geometry = SCNGeometry(sources: sources, elements: elements)
        geometry.materials = Array(materials.prefix(elements.count))
        return SCNNode(geometry: geometry)
    }
}

/// Watches the 3D camera from SceneKit's render loop and reports, only on change,
/// whether the avatar is being seen from behind, where a single front photo shows
/// nothing real ("Approximate back view").
final class AvatarBackViewWatcher: NSObject, SCNSceneRendererDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var behind = false
    var onChange: (Bool) -> Void = { _ in }

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        guard let eye = renderer.pointOfView?.presentation.worldPosition else { return }
        // The avatar faces +z; beyond ~100° from the front the back dominates the view.
        let angle = abs(atan2(Double(eye.x), Double(eye.z)))
        let now = angle > 100 * Double.pi / 180
        lock.lock()
        let changed = now != behind
        behind = now
        let callback = onChange
        lock.unlock()
        if changed {
            DispatchQueue.main.async { callback(now) }
        }
    }
}
