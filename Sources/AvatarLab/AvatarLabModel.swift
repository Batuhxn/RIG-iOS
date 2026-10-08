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
    var mode: AvatarPreviewMode = .flat2D
    private(set) var worn: [AvatarSlot: AvatarWornGarment] = [:]
    /// Front thumbnails of the starting silhouettes, by silhouette ID.
    private(set) var silhouettePreviews: [String: UIImage] = [:]

    private var asset: AvatarBodyAsset?
    private var builder: AvatarGarmentShellBuilder?
    private var textures: [UUID: (image: UIImage?, photo: UIImage?, colour: UIColor)] = [:]
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
                missing.map { garment -> (UUID, UIImage?, UIImage?, UIColor) in
                    let data = garment.imageRelativePath.flatMap { imageStore.data(atRelativePath: $0) }
                    let photo = data.flatMap(UIImage.init(data:)).map { AvatarGarmentTexture.downscaled($0, maxSide: 1024) }
                    let prepared = photo.map(AvatarGarmentTexture.prepare)
                    return (garment.id, prepared?.image, photo, prepared?.colour ?? .gray)
                }
            }.value
            let geometry = await Task.detached(priority: .userInitiated) { () -> (AvatarMesh, [AvatarMesh]) in
                let engine = AvatarMorphEngine(asset: asset)
                let positions = engine.positions(for: shape)
                return (engine.mesh(named: "body", positions: positions), builder.shells(for: garments.map(\.cut), positions: positions))
            }.value
            let newTextures = await loaded
            guard let self, !Task.isCancelled else { return }
            for (id, image, photo, colour) in newTextures { self.textures[id] = (image, photo, colour) }
            let layers = zip(garments, geometry.1).map { garment, mesh in
                AvatarGarmentLayer(id: garment.id, cut: garment.cut, mesh: mesh,
                                   texture: self.textures[garment.id]?.image,
                                   photo: self.textures[garment.id]?.photo,
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
    /// A copy no larger than `maxSide` on its long edge, at scale 1.
    static func downscaled(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let scale = min(1, maxSide / max(image.size.width, image.size.height, 1))
        guard scale < 1 else { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }

    /// Draws `photo` warped into `bands` (see `AvatarFrontProjection.warpBands`).
    /// Each horizontal strip of the photo is first cropped to the garment's own
    /// opaque pixels in that strip, so transparent margins are never stretched
    /// onto the body.
    static func drawWarped(_ photo: UIImage, into bands: [CGRect]) {
        guard let cg = photo.cgImage, !bands.isEmpty else { return }
        let raw = opaqueSpans(of: cg, bands: bands.count)
        // Smooth the photo's outline the same way as the body's, skipping empty rows.
        let present = raw.compactMap { $0 }.map { (lo: $0.lowerBound, hi: $0.upperBound) }
        var smoothed = AvatarFrontProjection.smooth(present).makeIterator()
        let spans: [ClosedRange<CGFloat>?] = raw.map { span in
            guard span != nil, let s = smoothed.next() else { return nil }
            return s.lo...max(s.lo + 1, s.hi)
        }
        let rowHeight = CGFloat(cg.height) / CGFloat(bands.count)
        for (k, rect) in bands.enumerated() {
            guard let span = spans[k] else { continue }
            let source = CGRect(x: span.lowerBound, y: (CGFloat(k) * rowHeight).rounded(.down),
                                width: max(1, span.upperBound - span.lowerBound), height: rowHeight.rounded(.up) + 1)
            if let strip = cg.cropping(to: source) {
                UIImage(cgImage: strip).draw(in: rect.insetBy(dx: 0, dy: -0.5))
            }
        }
    }

    /// For each horizontal band of the image, the x range holding opaque pixels.
    static func opaqueSpans(of cg: CGImage, bands: Int) -> [ClosedRange<CGFloat>?] {
        let width = min(cg.width, 256)
        let height = max(bands * 4, min(cg.height, 512))
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return [ClosedRange<CGFloat>?](repeating: 0...CGFloat(cg.width), count: bands) }
        let toSource = CGFloat(cg.width) / CGFloat(width)
        return (0..<bands).map { band in
            var lo = Int.max, hi = Int.min
            // A bitmap context's memory starts at the image's top row, like band 0.
            for row in (band * height / bands)..<((band + 1) * height / bands) {
                for x in 0..<width where pixels[(row * width + x) * 4 + 3] > 40 {
                    lo = min(lo, x)
                    hi = max(hi, x)
                }
            }
            guard lo <= hi else { return nil }
            return CGFloat(lo) * toSource...CGFloat(hi + 1) * toSource
        }
    }

    static func prepare(_ image: UIImage) -> (image: UIImage, colour: UIColor) {
        let colour = averageColour(of: image)
        let maxSide: CGFloat = 1024
        let scale = min(1, maxSide / max(image.size.width, image.size.height, 1))
        let size = CGSize(width: max(1, image.size.width * scale), height: max(1, image.size.height * scale))
        if let padded = padded(image, size: size) {
            return (padded, colour)
        }
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

    /// The cutout with its transparent pixels edge-padded (`AvatarTexturePadding`).
    private static func padded(_ image: UIImage, size: CGSize) -> UIImage? {
        guard let cg = image.cgImage else { return nil }
        let width = Int(size.width), height = Int(size.height)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: space, bitmapInfo: info) else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn, AvatarTexturePadding.pad(&pixels, width: width, height: height) else { return nil }
        let result: CGImage? = pixels.withUnsafeMutableBytes { buffer in
            CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                      bytesPerRow: width * 4, space: space, bitmapInfo: info)?.makeImage()
        }
        return result.map { UIImage(cgImage: $0) }
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
