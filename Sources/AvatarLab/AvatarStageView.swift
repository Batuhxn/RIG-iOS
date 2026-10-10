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
        Self.applyOcclusion(style, to: camera)
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
            var channels: [[Float]] = []
            if isTemplate, style.softSeam || style.hemShading {
                // Channel 1: distance weight from the photo/plain boundary; channel 2: from the
                // open edges. Read back in the surface shaders through two identity ramps.
                let count = layer.mesh.positions.count
                channels = [style.softSeam ? Self.seamWeights(layer.mesh) : [Float](repeating: 1, count: count),
                            style.hemShading ? Self.hemWeights(layer.mesh) : [Float](repeating: 1, count: count)]
                for material in [front, back] {
                    material.roughness.contents = Self.seamRamp
                    material.roughness.mappingChannel = 1
                    material.roughness.wrapS = .clamp
                    material.metalness.contents = Self.seamRamp
                    material.metalness.mappingChannel = 2
                    material.metalness.wrapS = .clamp
                }
                front.shaderModifiers = [.surface: Self.surfaceModifier(unknown: style.softSeam ? unknown : nil, hem: style.hemShading)]
                back.shaderModifiers = [.surface: Self.surfaceModifier(unknown: nil, hem: style.hemShading)]
            }
            let garment = node(for: layer.mesh, materials: [front, back], channels: channels)
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
    /// `halfHeight` and `centre` frame a close-up (metres; the default shows the whole body).
    func snapshot(size: CGSize, yaw: Float = 0, background: UIColor = .white,
                  halfHeight: Double = 0.95, centre: SIMD2<Float> = SIMD2(0, 0.88)) -> UIImage {
        avatarNode.eulerAngles = SCNVector3(0, yaw, 0)
        let camera = SCNCamera()
        camera.usesOrthographicProjection = true
        camera.orthographicScale = halfHeight
        camera.zNear = 0.05
        camera.zFar = 20
        Self.applyOcclusion(style, to: camera)
        let eye = SCNNode()
        eye.camera = camera
        eye.position = SCNVector3(centre.x, centre.y, 4)
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

    /// One geometry; the back panel, when there is one, is a second element with its
    /// own material.
    /// `channels` are per-vertex values carried in texture channels 1, 2, ... (the soft
    /// seam's and the hem's distance weights).
    private func node(for mesh: AvatarMesh, materials: [SCNMaterial], channels: [[Float]] = []) -> SCNNode {
        let vertices = mesh.positions.map { SCNVector3($0.x, $0.y, $0.z) }
        let normals = mesh.normals.map { SCNVector3($0.x, $0.y, $0.z) }
        let uvs = mesh.uvs.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) }
        var elements = [SCNGeometryElement(indices: mesh.triangles, primitiveType: .triangles)]
        if !mesh.backTriangles.isEmpty {
            elements.append(SCNGeometryElement(indices: mesh.backTriangles, primitiveType: .triangles))
        }
        var sources = [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals),
                       SCNGeometrySource(textureCoordinates: uvs)]
        for channel in channels where channel.count == mesh.positions.count {
            sources.append(SCNGeometrySource(textureCoordinates: channel.map { CGPoint(x: CGFloat($0), y: 0.5) }))
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
