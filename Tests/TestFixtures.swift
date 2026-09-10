import Foundation
@testable import RIG

/// Deterministic fixtures. Every identifier is derived from an integer so a
/// failing assertion names the same garment on every run.
enum Fixture {
    static func id(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value)) ?? UUID()
    }

    static func garment(
        _ index: Int,
        _ category: GarmentCategory,
        _ color: ColorFamily = .black,
        seasons: SeasonSet = .all,
        favorite: Bool = false,
        name: String? = nil
    ) -> GarmentSnapshot {
        GarmentSnapshot(
            id: id(index),
            category: category,
            colorFamily: color,
            seasons: seasons,
            displayName: name ?? "\(category.rawValue)-\(index)",
            isFavorite: favorite
        )
    }

    /// A wardrobe that can produce valid looks in every category.
    static func smallWardrobe() -> [GarmentSnapshot] {
        [
            garment(1, .top, .white),
            garment(2, .top, .navy, seasons: [.autumn, .winter]),
            garment(3, .bottom, .gray),
            garment(4, .bottom, .blue, seasons: [.spring, .summer]),
            garment(5, .shoes, .white, seasons: [.spring, .summer]),
            garment(6, .shoes, .brown, seasons: [.autumn, .winter]),
            garment(7, .outerwear, .beige, seasons: [.spring, .autumn]),
            garment(8, .dress, .black),
            garment(9, .bag, .brown),
            garment(10, .accessory, .metallic)
        ]
    }

    /// Large enough that unbounded generation would produce far more than the cap.
    static func largeWardrobe() -> [GarmentSnapshot] {
        var wardrobe: [GarmentSnapshot] = []
        for index in 0..<20 {
            wardrobe.append(garment(100 + index, .top, ColorFamily.allCases[index % ColorFamily.allCases.count]))
        }
        for index in 0..<20 {
            wardrobe.append(garment(200 + index, .bottom, ColorFamily.allCases[index % ColorFamily.allCases.count]))
        }
        for index in 0..<6 {
            wardrobe.append(garment(300 + index, .shoes, .black))
        }
        for index in 0..<4 {
            wardrobe.append(garment(400 + index, .outerwear, .navy))
        }
        for index in 0..<4 {
            wardrobe.append(garment(500 + index, .accessory, .metallic))
        }
        return wardrobe
    }
}

/// A provider that always answers with a fixed value. Used to prove the ML seam
/// is capped, not to simulate any real model.
struct ConstantCompatibilityProvider: CompatibilityProvider {
    let isEnabled: Bool
    let value: Double?

    init(isEnabled: Bool = true, value: Double?) {
        self.isEnabled = isEnabled
        self.value = value
    }

    func compatibilitySignal(for items: [GarmentSnapshot]) async throws -> Double? {
        value
    }
}

struct ThrowingCompatibilityProvider: CompatibilityProvider {
    struct Failure: Error {}
    let isEnabled = true

    func compatibilitySignal(for items: [GarmentSnapshot]) async throws -> Double? {
        throw Failure()
    }
}
