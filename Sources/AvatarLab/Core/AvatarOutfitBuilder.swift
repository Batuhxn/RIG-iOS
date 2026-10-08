import Foundation

/// Builds everything the stage draws for one body shape and outfit: the morphed body,
/// minus the triangles garments cover, and one mesh per garment. Cuts with a Garment
/// Engine template use it; the others fall back to the body-hugging shells.
struct AvatarOutfitBuilder: Sendable {
    let asset: AvatarBodyAsset
    let shells: AvatarGarmentShellBuilder
    let templates: GarmentTemplateLibrary?

    init(asset: AvatarBodyAsset, templates: GarmentTemplateLibrary?) {
        self.asset = asset
        self.shells = AvatarGarmentShellBuilder(asset: asset)
        self.templates = templates
    }

    func template(for cut: AvatarGarmentCut) -> GarmentTemplate? {
        cut.templateName.flatMap { templates?.templates[$0] }
    }

    /// - Returns: `body` without the skin garments cover (for 3D), `bareBody` complete
    ///   (for the 2D overlay, which draws no 3D garments), and the garments; nil once the
    ///   calling task is cancelled.
    func build(shape: AvatarBodyShape, cuts: [AvatarGarmentCut]) -> (body: AvatarMesh, bareBody: AvatarMesh, garments: [AvatarMesh])? {
        let engine = AvatarMorphEngine(asset: asset)
        let positions = engine.positions(for: shape)
        let bodyTriangles = asset.submeshes["body"] ?? []
        let bodyNormals = AvatarMorphEngine.normals(positions: positions, triangles: bodyTriangles)
        guard !Task.isCancelled else { return nil }

        var hidden = Set<Int32>()
        var garments: [AvatarMesh] = []
        let fallback = shells.shells(for: cuts, positions: positions)
        for (cut, shell) in zip(cuts, fallback) {
            if let template = template(for: cut) {
                garments.append(GarmentDeformer.mesh(for: template, positions: positions, bodyNormals: bodyNormals))
                hidden.formUnion(template.hiddenBodyTriangles)
            } else {
                garments.append(shell)
            }
        }
        guard !Task.isCancelled else { return nil }
        var visible: [UInt32] = []
        visible.reserveCapacity(bodyTriangles.count)
        var t = 0
        while t + 2 < bodyTriangles.count {
            if !hidden.contains(Int32(t / 3)) { visible += bodyTriangles[t..<(t + 3)] }
            t += 3
        }
        let body = AvatarMorphEngine.compact(triangles: visible, positions: positions, offset: 0)
        let bare = hidden.isEmpty ? body : AvatarMorphEngine.compact(triangles: bodyTriangles, positions: positions, offset: 0)
        return (body, bare, garments)
    }
}
