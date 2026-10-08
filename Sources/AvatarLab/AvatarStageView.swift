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

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.autoenablesDefaultLighting = false
        view.scene = context.coordinator.scene
        view.pointOfView = context.coordinator.cameraNode
        view.accessibilityLabel = "Avatar preview"
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
        let body = node(for: content.body, material: Self.skinMaterial)
        bodyNode?.removeFromParentNode()
        avatarNode.addChildNode(body)
        bodyNode = body

        garmentNodes.forEach { $0.removeFromParentNode() }
        garmentNodes = []
        guard mode != .flat2D else { return }
        for layer in content.garments where !layer.mesh.isEmpty {
            let material = SCNMaterial()
            material.lightingModel = .physicallyBased
            material.roughness.contents = 0.85
            material.metalness.contents = 0.0
            material.isDoubleSided = true
            if mode == .photo3D, let texture = layer.texture {
                material.diffuse.contents = texture
                material.diffuse.wrapS = .clamp
                material.diffuse.wrapT = .clamp
            } else {
                material.diffuse.contents = layer.colour
            }
            let garment = node(for: layer.mesh, material: material)
            garment.renderingOrder = layer.cut.layer
            avatarNode.addChildNode(garment)
            garmentNodes.append(garment)
        }
    }

    private static let skinMaterial: SCNMaterial = {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = UIColor(red: 0.80, green: 0.78, blue: 0.75, alpha: 1)
        material.roughness.contents = 0.7
        material.metalness.contents = 0.0
        return material
    }()

    private func node(for mesh: AvatarMesh, material: SCNMaterial) -> SCNNode {
        let vertices = mesh.positions.map { SCNVector3($0.x, $0.y, $0.z) }
        let normals = mesh.normals.map { SCNVector3($0.x, $0.y, $0.z) }
        let uvs = mesh.uvs.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) }
        let element = SCNGeometryElement(indices: mesh.triangles, primitiveType: .triangles)
        let geometry = SCNGeometry(sources: [
            SCNGeometrySource(vertices: vertices),
            SCNGeometrySource(normals: normals),
            SCNGeometrySource(textureCoordinates: uvs),
        ], elements: [element])
        geometry.materials = [material]
        return SCNNode(geometry: geometry)
    }
}
