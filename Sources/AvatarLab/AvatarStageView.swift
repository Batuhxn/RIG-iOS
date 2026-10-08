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

/// Owns the SceneKit scene; rebuilt geometry is swapped in on every update.
@MainActor
final class AvatarStageCoordinator {
    let scene = SCNScene()
    let cameraNode = SCNNode()
    let backWatcher = AvatarBackViewWatcher()
    private let avatarNode = SCNNode()
    private var bodyNode: SCNNode?
    private var garmentNodes: [SCNNode] = []
    private var wasFlat: Bool?
    private var shown: (content: UUID, mode: AvatarPreviewMode)?

    init() {
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
        key.light?.intensity = 900
        key.eulerAngles = SCNVector3(-0.5, 0.45, 0)
        scene.rootNode.addChildNode(key)
        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .ambient
        fill.light?.intensity = 420
        scene.rootNode.addChildNode(fill)
        let rim = SCNNode()
        rim.light = SCNLight()
        rim.light?.type = .directional
        rim.light?.intensity = 350
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

        garmentNodes.forEach { $0.removeFromParentNode() }
        garmentNodes = []
        guard mode != .flat2D else { return }
        for layer in content.garments where !layer.mesh.isEmpty {
            let front = Self.fabric(layer.colour)
            if mode == .photo3D, let texture = layer.texture {
                front.diffuse.contents = texture
                front.diffuse.wrapS = .clamp
                front.diffuse.wrapT = .clamp
            }
            // The back panel is what a single front photo cannot show: it gets the
            // garment's own average colour, a shade darker, never an invented print.
            let back = Self.fabric(Self.unknownRegion(layer.colour))
            let garment = node(for: layer.mesh, materials: [front, back])
            garment.renderingOrder = layer.cut.layer
            avatarNode.addChildNode(garment)
            garmentNodes.append(garment)
        }
    }

    /// Renders the current scene offscreen from the front (or turned by `yaw`),
    /// orthographic, on a white background: onboarding thumbnails and tests.
    func snapshot(size: CGSize, yaw: Float = 0) -> UIImage {
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
        scene.background.contents = UIColor.white
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
