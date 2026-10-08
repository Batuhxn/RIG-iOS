import Foundation

/// The garments shown on the avatar, by wardrobe item ID. A dress or one-piece
/// goes in `top`, and `bottom` is then ignored.
struct AvatarOutfitSelection: Codable, Equatable, Sendable {
    var top: UUID?
    var bottom: UUID?
    var shoes: UUID?
    var outerwear: UUID?

    init(top: UUID? = nil, bottom: UUID? = nil, shoes: UUID? = nil, outerwear: UUID? = nil) {
        self.top = top
        self.bottom = bottom
        self.shoes = shoes
        self.outerwear = outerwear
    }
}

/// Everything the avatar feature stores. One small JSON file on the device:
/// body controls (no measurements, no photo) and the last outfit shown.
struct AvatarProfile: Codable, Equatable, Sendable {
    var shape: AvatarBodyShape = .neutral
    var outfit = AvatarOutfitSelection()
    var savedOutfits: [AvatarOutfitSelection] = []
}

/// Stores the profile under Application Support. Deliberately not SwiftData:
/// the avatar adds no model, so it can never be the cause of a store migration,
/// and deleting the profile is deleting one file.
struct AvatarProfileStore: Sendable {
    let directory: URL

    var fileURL: URL { directory.appendingPathComponent("avatar-profile.json") }

    static func applicationSupport() throws -> AvatarProfileStore {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return AvatarProfileStore(directory: base.appendingPathComponent("Avatar", isDirectory: true))
    }

    /// nil when there is no profile yet, or the file cannot be read.
    func load() -> AvatarProfile? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(AvatarProfile.self, from: data)
    }

    func save(_ profile: AvatarProfile) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(profile).write(to: fileURL, options: [.atomic])
    }

    func delete() throws {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }
}

extension AvatarGarmentCut {
    /// The cut for a wardrobe garment, from its category and free-text subtype.
    /// nil for things the avatar does not wear (bags, accessories).
    static func forGarment(category: GarmentCategory, subtype: String) -> AvatarGarmentCut? {
        let s = subtype.lowercased()
        func has(_ words: String...) -> Bool { words.contains { s.contains($0) } }
        switch category {
        case .top:
            if has("tank", "cami", "sleeveless", "vest", "strap", "atlet") { return .top(sleeve: .none) }
            if has("crop") { return .top(sleeve: .short, hem: .cropped) }
            if has("long", "sweat", "sweater", "hoodie", "jumper", "cardigan", "shirt", "blouse", "knit", "turtle", "kazak", "gömlek")
                && !has("t-shirt", "tshirt", "tee", "polo", "short sleeve") {
                return .top(sleeve: .long)
            }
            return .top(sleeve: .short)
        case .bottom:
            if has("skirt", "etek") {
                if has("mini") { return .skirt(length: .mini) }
                if has("maxi", "long") { return .skirt(length: .maxi) }
                if has("midi") { return .skirt(length: .midi) }
                return .skirt(length: .knee)
            }
            if has("short", "şort") { return .shorts }
            return .trousers
        case .dress:
            if has("mini") { return .dress(length: .mini) }
            if has("maxi", "long") { return .dress(length: .maxi) }
            if has("midi") { return .dress(length: .midi) }
            return .dress(length: .knee)
        case .outerwear:
            return .outerwear
        case .shoes:
            return .shoes
        case .bag, .accessory:
            return nil
        }
    }
}
