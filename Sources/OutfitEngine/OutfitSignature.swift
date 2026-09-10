import Foundation

/// Order-independent identity for a set of garments.
///
/// Two outfits containing the same garments produce the same signature no matter
/// what order they were assembled in. This is what makes feedback comparable and
/// what stops the same look being suggested twice under two different orderings.
enum OutfitSignature {
    static let separator = "|"

    static func signature(forGarmentIDs ids: [UUID]) -> String {
        ids
            .map { $0.uuidString.uppercased() }
            .sorted()
            .joined(separator: separator)
    }

    static func signature(for items: [GarmentSnapshot]) -> String {
        signature(forGarmentIDs: items.map(\.id))
    }
}
