import Foundation
import Observation
import SwiftUI
import UIKit

/// How the outfit is drawn on the avatar.
enum AvatarPreviewMode: String, CaseIterable, Identifiable, Sendable {
    /// The garment photo projected onto a 3D shell. Rotates.
    case photo3D
    /// The garment's average colour on the 3D shell. Rotates.
    case colour3D
    /// The garment photo laid flat over a front view of the avatar.
    case flat2D

    var id: String { rawValue }

    var title: String {
        switch self {
        case .photo3D: return "3D photo"
        case .colour3D: return "3D colour"
        case .flat2D: return "2D"
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
    let texture: UIImage?
    let colour: UIColor
}

/// Everything the stage draws for one body shape and outfit.
struct AvatarStageContent {
    let id = UUID()
    let body: AvatarMesh
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
    var mode: AvatarPreviewMode = .photo3D
    private(set) var worn: [AvatarSlot: AvatarWornGarment] = [:]

    private var asset: AvatarBodyAsset?
    private var builder: AvatarGarmentShellBuilder?
    private var textures: [UUID: (image: UIImage?, colour: UIColor)] = [:]
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
                return (asset, AvatarGarmentShellBuilder(asset: asset))
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
        } catch {
            phase = .failed("The avatar could not be loaded.")
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

    /// Removes the stored profile entirely and returns to the neutral figure.
    func deleteProfile() {
        try? store?.delete()
        profile = AvatarProfile()
        hasSavedProfile = false
        worn = [:]
        refresh()
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

    /// Morphs the body and rebuilds the garment shells off the main thread.
    /// A newer request cancels an older one, so dragging a slider never queues work.
    private func refresh() {
        guard let asset, let builder else { return }
        updateTask?.cancel()
        let shape = profile.shape
        let garments = activeGarments
        let missing = garments.filter { textures[$0.id] == nil }
        let imageStore = imageStore
        updateTask = Task { [weak self] in
            let started = Date()
            async let loaded = Task.detached(priority: .userInitiated) {
                missing.map { garment -> (UUID, UIImage?, UIColor) in
                    let data = garment.imageRelativePath.flatMap { imageStore.data(atRelativePath: $0) }
                    let prepared = data.flatMap(UIImage.init(data:)).map(AvatarGarmentTexture.prepare)
                    return (garment.id, prepared?.image, prepared?.colour ?? .gray)
                }
            }.value
            let geometry = await Task.detached(priority: .userInitiated) { () -> (AvatarMesh, [AvatarMesh]) in
                let engine = AvatarMorphEngine(asset: asset)
                let positions = engine.positions(for: shape)
                return (engine.mesh(named: "body", positions: positions), builder.shells(for: garments.map(\.cut), positions: positions))
            }.value
            let newTextures = await loaded
            guard let self, !Task.isCancelled else { return }
            for (id, image, colour) in newTextures { self.textures[id] = (image, colour) }
            let layers = zip(garments, geometry.1).map { garment, mesh in
                AvatarGarmentLayer(id: garment.id, cut: garment.cut, mesh: mesh,
                                   texture: self.textures[garment.id]?.image,
                                   colour: self.textures[garment.id]?.colour ?? .gray)
            }
            self.content = AvatarStageContent(body: geometry.0, garments: layers,
                                              computeMilliseconds: Int(Date().timeIntervalSince(started) * 1000))
        }
    }
}

/// Turns a garment cutout into something a shell can wear: transparent areas
/// (between sleeves and body in a flat photo) are filled with the garment's own
/// average colour, so the shell never shows holes.
enum AvatarGarmentTexture {
    static func prepare(_ image: UIImage) -> (image: UIImage, colour: UIColor) {
        let colour = averageColour(of: image)
        let maxSide: CGFloat = 1024
        let scale = min(1, maxSide / max(image.size.width, image.size.height, 1))
        let size = CGSize(width: max(1, image.size.width * scale), height: max(1, image.size.height * scale))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let filled = UIGraphicsImageRenderer(size: size, format: format).image { context in
            colour.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return (filled, colour)
    }

    /// Alpha-weighted mean colour, from an 8×8 downsample.
    static func averageColour(of image: UIImage) -> UIColor {
        guard let cg = image.cgImage else { return .gray }
        let side = 8
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return .gray }
        var r = 0.0, g = 0.0, b = 0.0, a = 0.0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            r += Double(pixels[i]); g += Double(pixels[i + 1]); b += Double(pixels[i + 2]); a += Double(pixels[i + 3])
        }
        guard a > 0 else { return .gray }
        // Premultiplied: the sums of colour over the sum of alpha give the mean.
        return UIColor(red: r / a, green: g / a, blue: b / a, alpha: 1)
    }
}
