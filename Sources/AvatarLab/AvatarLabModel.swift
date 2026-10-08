import Foundation
import Observation
import SwiftUI
import UIKit

/// How the outfit is drawn on the avatar.
enum AvatarPreviewMode: String, CaseIterable, Identifiable, Sendable {
    /// The garment photo laid flat over a front view of the avatar. The default:
    /// it keeps the real garment's look most faithfully.
    case flat2D
    /// The garment photo projected onto a 3D shell. Rotates. Experimental.
    case photo3D
    /// The garment's average colour on the 3D shell. Rotates.
    case colour3D

    var id: String { rawValue }

    var title: String {
        switch self {
        case .flat2D: return "Photo"
        case .photo3D: return "3D (experimental)"
        case .colour3D: return "3D colour"
        }
    }
}

/// Where a wardrobe garment goes on the avatar.
enum AvatarSlot: String, CaseIterable, Identifiable, Sendable {
    case top, bottom, outerwear, shoes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .top: return "Top or dress"
        case .bottom: return "Bottom"
        case .outerwear: return "Outerwear"
        case .shoes: return "Shoes"
        }
    }

    var categories: [GarmentCategory] {
        switch self {
        case .top: return [.top, .dress]
        case .bottom: return [.bottom]
        case .outerwear: return [.outerwear]
        case .shoes: return [.shoes]
        }
    }
}

/// A garment the avatar is wearing: what is needed to draw it, nothing more.
struct AvatarWornGarment: Identifiable, Equatable, Sendable {
    let id: UUID
    let cut: AvatarGarmentCut
    let imageRelativePath: String?
}

/// One garment layer, ready to draw.
struct AvatarGarmentLayer: Identifiable {
    let id: UUID
    let cut: AvatarGarmentCut
    let mesh: AvatarMesh
    /// The cutout with its gaps filled in the garment's colour, for 3D shells.
    let texture: UIImage?
    /// The cutout as photographed, transparency kept, for the 2D overlay.
    var photo: UIImage? = nil
    let colour: UIColor
}

/// Everything the stage draws for one body shape and outfit.
struct AvatarStageContent {
    let id = UUID()
    /// The body without the skin 3D garments cover.
    let body: AvatarMesh
    /// The whole body, for the 2D overlay (which draws no 3D garments).
    var bareBody: AvatarMesh? = nil
    let garments: [AvatarGarmentLayer]
    let computeMilliseconds: Int
}

@MainActor
@Observable
final class AvatarLabModel {
    enum Phase: Equatable {
        case loading
        case failed(String)
        case ready
    }

    private(set) var phase: Phase = .loading
    private(set) var content: AvatarStageContent?
    private(set) var hasSavedProfile = false
    private(set) var loadMilliseconds: Int?
    var profile = AvatarProfile()
    var mode: AvatarPreviewMode = .flat2D
    private(set) var worn: [AvatarSlot: AvatarWornGarment] = [:]
    /// Front thumbnails of the starting silhouettes, by silhouette ID.
    private(set) var silhouettePreviews: [String: UIImage] = [:]

    private var asset: AvatarBodyAsset?
    private var builder: AvatarOutfitBuilder?
    private var textures: [UUID: (image: UIImage?, photo: UIImage?, colour: UIColor, spans: [ClosedRange<Float>?])] = [:]
    private var updateTask: Task<Void, Never>?
    private let store: AvatarProfileStore?
    private let imageStore: GarmentImageStore

    init(store: AvatarProfileStore?, imageStore: GarmentImageStore) {
        self.store = store
        self.imageStore = imageStore
    }

    func load() async {
        guard phase == .loading, asset == nil else { return }
        let started = Date()
        do {
            let (asset, builder) = try await Task.detached(priority: .userInitiated) {
                let asset = try AvatarBodyAsset.bundled()
                // Garment Engine v1 templates are optional: without them every cut uses a shell.
                let templates = try? GarmentTemplateLibrary.bundled(for: asset)
                return (asset, AvatarOutfitBuilder(asset: asset, templates: templates))
            }.value
            self.asset = asset
            self.builder = builder
            loadMilliseconds = Int(Date().timeIntervalSince(started) * 1000)
            if let saved = store?.load() {
                profile = saved
                hasSavedProfile = true
            }
            phase = .ready
            refresh()
            await makeSilhouettePreviews(asset: asset)
        } catch {
            phase = .failed("The avatar could not be loaded.")
        }
    }

    private func makeSilhouettePreviews(asset: AvatarBodyAsset) async {
        for silhouette in AvatarStartingSilhouette.all {
            let shape = silhouette.shape
            let body = await Task.detached(priority: .utility) {
                let engine = AvatarMorphEngine(asset: asset)
                return engine.mesh(named: "body", positions: engine.positions(for: shape))
            }.value
            let stage = AvatarStageCoordinator()
            stage.show(AvatarStageContent(body: body, garments: [], computeMilliseconds: 0), mode: .colour3D)
            silhouettePreviews[silhouette.id] = stage.snapshot(size: CGSize(width: 120, height: 240))
        }
    }

    // MARK: Body

    func setValue(_ value: Float, for control: AvatarControl) {
        profile.shape[control] = value
        refresh()
    }

    func applyStartingSilhouette(_ silhouette: AvatarStartingSilhouette) {
        profile.shape = silhouette.shape
        refresh()
    }

    func resetBody() {
        profile.shape = .neutral
        refresh()
    }

    func saveProfile() {
        guard let store else { return }
        do {
            try store.save(profile)
            hasSavedProfile = true
        } catch {
            // Saving is a convenience; the preview keeps working without it.
        }
    }

    /// Set when deleting the stored profile failed; the profile is then kept as is.
    var deleteFailed = false

    /// Removes the stored profile entirely and returns to the neutral figure.
    /// Returns false, and changes nothing, when the file could not be removed:
    /// the screen must never claim a deletion that did not happen.
    @discardableResult
    func deleteProfile() -> Bool {
        do {
            try store?.delete()
        } catch {
            deleteFailed = true
            return false
        }
        deleteFailed = false
        profile = AvatarProfile()
        hasSavedProfile = false
        worn = [:]
        refresh()
        return true
    }

    // MARK: Outfit

    func wear(_ item: ClothingItem?, in slot: AvatarSlot) {
        guard let item, let cut = AvatarGarmentCut.forGarment(category: item.category, subtype: item.subtype) else {
            worn[slot] = nil
            syncOutfit()
            refresh()
            return
        }
        worn[slot] = AvatarWornGarment(id: item.id, cut: cut, imageRelativePath: item.preferredImageRelativePath)
        syncOutfit()
        refresh()
    }

    /// Puts back the garments of a stored outfit that still exist in the wardrobe.
    func restore(_ selection: AvatarOutfitSelection, from items: [ClothingItem]) {
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        worn = [:]
        let pairs: [(AvatarSlot, UUID?)] = [(.top, selection.top), (.bottom, selection.bottom), (.outerwear, selection.outerwear), (.shoes, selection.shoes)]
        for (slot, id) in pairs {
            if let id, let item = byID[id], let cut = AvatarGarmentCut.forGarment(category: item.category, subtype: item.subtype) {
                worn[slot] = AvatarWornGarment(id: item.id, cut: cut, imageRelativePath: item.preferredImageRelativePath)
            }
        }
        syncOutfit()
        refresh()
    }

    func saveCurrentOutfit() {
        guard !worn.isEmpty, !profile.savedOutfits.contains(profile.outfit) else { return }
        profile.savedOutfits.insert(profile.outfit, at: 0)
        saveProfile()
    }

    func removeSavedOutfit(_ selection: AvatarOutfitSelection) {
        profile.savedOutfits.removeAll { $0 == selection }
        saveProfile()
    }

    private func syncOutfit() {
        profile.outfit = AvatarOutfitSelection(top: worn[.top]?.id, bottom: worn[.bottom]?.id, shoes: worn[.shoes]?.id, outerwear: worn[.outerwear]?.id)
    }

    /// Garments in drawing order. A dress replaces the bottom.
    private var activeGarments: [AvatarWornGarment] {
        var list = worn.values.map { $0 }
        if case .dress = worn[.top]?.cut {
            list.removeAll { $0.id == worn[.bottom]?.id }
        }
        return list.sorted { $0.cut.layer < $1.cut.layer }
    }

    // MARK: Recompute

    /// Off the main actor; stops between garments once cancelled.
    nonisolated private static func loadTextures(_ garments: [AvatarWornGarment], from imageStore: GarmentImageStore) async -> [(UUID, UIImage?, UIImage?, UIColor, [ClosedRange<Float>?])] {
        var out: [(UUID, UIImage?, UIImage?, UIColor, [ClosedRange<Float>?])] = []
        for garment in garments {
            if Task.isCancelled { break }
            let data = garment.imageRelativePath.flatMap { imageStore.data(atRelativePath: $0) }
            let photo = data.flatMap(UIImage.init(data:)).map { AvatarGarmentTexture.downscaled($0, maxSide: 1024) }
            let prepared = photo.map(AvatarGarmentTexture.prepare)
            let spans = photo.map { AvatarGarmentTexture.photoSpans(of: $0) } ?? []
            out.append((garment.id, prepared?.image, photo, prepared?.colour ?? .gray, spans))
        }
        return out
    }

    /// Off the main actor; nil once cancelled.
    nonisolated private static func buildGeometry(builder: AvatarOutfitBuilder, shape: AvatarBodyShape,
                                                  cuts: [AvatarGarmentCut]) async -> (body: AvatarMesh, bareBody: AvatarMesh, garments: [AvatarMesh])? {
        builder.build(shape: shape, cuts: cuts)
    }

    /// Morphs the body and rebuilds the garment shells off the main thread.
    /// A newer request cancels an older one, so dragging a slider never queues work.
    private func refresh() {
        guard let builder else { return }
        updateTask?.cancel()
        let shape = profile.shape
        let garments = activeGarments
        let missing = garments.filter { textures[$0.id] == nil }
        let imageStore = imageStore
        updateTask = Task { [weak self] in
            // Coalesce: while a slider is being dragged, only the last value is built.
            try? await Task.sleep(nanoseconds: 25_000_000)
            guard !Task.isCancelled else { return }
            let started = Date()
            // Child tasks (not detached), so cancelling this refresh cancels them too.
            async let loaded = Self.loadTextures(missing, from: imageStore)
            async let geometryJob = Self.buildGeometry(builder: builder, shape: shape, cuts: garments.map(\.cut))
            let (newTextures, built) = await (loaded, geometryJob)
            guard let self, !Task.isCancelled, let geometry = built else { return }
            for (id, image, photo, colour, spans) in newTextures { self.textures[id] = (image, photo, colour, spans) }
            let layers = zip(garments, geometry.garments).map { garment, built -> AvatarGarmentLayer in
                var mesh = built
                // Template garments map the photo's outline onto the front panel's outline.
                if !mesh.backTriangles.isEmpty, let spans = self.textures[garment.id]?.spans, !spans.isEmpty {
                    mesh.uvs = GarmentPhotoMapping.uvs(for: mesh, photoSpans: spans)
                }
                return AvatarGarmentLayer(id: garment.id, cut: garment.cut, mesh: mesh,
                                   texture: self.textures[garment.id]?.image,
                                   photo: self.textures[garment.id]?.photo,
                                   colour: self.textures[garment.id]?.colour ?? .gray)
            }
            self.content = AvatarStageContent(body: geometry.body, bareBody: geometry.bareBody, garments: layers,
                                              computeMilliseconds: Int(Date().timeIntervalSince(started) * 1000))
        }
    }
}
