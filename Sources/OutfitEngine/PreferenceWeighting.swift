import Foundation

/// The share of an outfit the user has explicitly marked as a favourite.
///
/// This is stated preference, not learned preference. RIG v0.1 has no model of
/// personal style and does not pretend to; favourites are simply a small nudge
/// toward garments the user already told us they like.
enum PreferenceWeighting {
    static func score(for items: [GarmentSnapshot]) -> Double {
        guard !items.isEmpty else { return 0 }
        let favorites = items.filter(\.isFavorite).count
        return Double(favorites) / Double(items.count)
    }
}
