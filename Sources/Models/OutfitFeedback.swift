import Foundation
import SwiftData

/// The two reactions v0.1 records. A skipped suggestion is deliberately not
/// persisted: absence of an opinion is not an opinion.
enum OutfitRating: String, Codable, Hashable, Sendable {
    case liked
    case disliked
}

/// A recorded reaction to one outfit.
///
/// v0.1 captures feedback and does nothing with it. There is no personalisation
/// model behind this and the interface never suggests otherwise. The point is to
/// have honest local history available when preference learning is built.
@Model
final class OutfitFeedback {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    /// Order-independent identity of the scored outfit.
    var outfitSignature: String
    var ratingRaw: String

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        outfitSignature: String,
        rating: OutfitRating
    ) {
        self.id = id
        self.createdAt = createdAt
        self.outfitSignature = outfitSignature
        self.ratingRaw = rating.rawValue
    }
}

extension OutfitFeedback {
    var rating: OutfitRating? {
        OutfitRating(rawValue: ratingRaw)
    }
}
