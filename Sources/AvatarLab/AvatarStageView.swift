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

    static let current = AvatarStageStyle()
    static let engineV1 = AvatarStageStyle(softSeam: false, studioLight: false, fabricInterior: false, groundShadow: false)
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
        key.light?.intensity = style.studioLight ? 650 : 900
        key.eulerAngles = SCNVector3(-0.5, 0.45, 0)
        scene.rootNode.addChildNode(key)
        if style.studioLight {
            scene.lightingEnvironment.contents = Self.studioEnvironment
            scene.lightingEnvironment.intensity = 1.1
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
        let body = node(for: mode == .flat2D ? (content.bareBody ?? content.body) : content.body, materials: [Self.skinMaterial])
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
            if isTemplate, style.softSeam {
                front.shaderModifiers = [.surface: Self.softSeamModifier(unknown)]
            }
            let garment = node(for: layer.mesh, materials: [front, back])
            garment.renderingOrder = layer.cut.layer
            avatarNode.addChildNode(garment)
            garmentNodes.append(garment)
            // Template triangles wind outward (GarmentDeformer), so culling is safe for them.
            if isTemplate, style.fabricInterior, let geometry = garment.geometry?.copy() as? SCNGeometry {
                front.isDoubleSided = false
                back.isDoubleSided = false
                let inside = Self.fabric(Self.interior(unknown))
                inside.isDoubleSided = false
                inside.cullMode = .front
                geometry.materials = [inside, inside]
                let lining = SCNNode(geometry: geometry)
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
        let background = scene.background.contents
        scene.background.contents = background
        defer {
            eye.removeFromParentNode()
            scene.background.contents = background
            avatarNode.eulerAngles = SCNVector3Zero
        }
        let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        renderer.scene = scene
        renderer.pointOfView = eye
        return renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
    }

    private static let skinMaterial: SCNMaterial = {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = UIColor(red: 0.93, green: 0.92, blue: 0.90, alpha: 1)  // matte dress-form white, not a skin tone
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
        float3 garmentNormal = normalize((scn_node.inverseModelViewTransform * float4(_surface.normal, 0.0)).xyz);
        float photo = smoothstep(\(band), garmentNormal.z);
        _surface.diffuse.rgb = mix(\(colour), _surface.diffuse.rgb, photo);
        """
    }

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
    private func node(for mesh: AvatarMesh, materials: [SCNMaterial]) -> SCNNode {
        let vertices = mesh.positions.map { SCNVector3($0.x, $0.y, $0.z) }
        let normals = mesh.normals.map { SCNVector3($0.x, $0.y, $0.z) }
        let uvs = mesh.uvs.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) }
        var elements = [SCNGeometryElement(indices: mesh.triangles, primitiveType: .triangles)]
        if !mesh.backTriangles.isEmpty {
            elements.append(SCNGeometryElement(indices: mesh.backTriangles, primitiveType: .triangles))
        }
        let geometry = SCNGeometry(sources: [
            SCNGeometrySource(vertices: vertices),
            SCNGeometrySource(normals: normals),
            SCNGeometrySource(textureCoordinates: uvs),
        ], elements: elements)
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
