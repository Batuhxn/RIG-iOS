import Foundation
import Observation

/// State for one "Suggest a Look" session.
///
/// "Show me another set" walks further down the same deterministic ranking
/// rather than reshuffling. When the wardrobe runs out of unseen looks it says
/// so and starts again from the top, which is honest about a small wardrobe
/// instead of quietly repeating.
@MainActor
@Observable
final class SuggestionsModel {
    private(set) var suggestions: [OutfitSuggestion] = []
    private(set) var readiness = WardrobeReadiness(canSuggest: false, missing: [])
    private(set) var isLoading = false
    private(set) var hasWrappedAround = false
    var errorMessage: String?

    private var seenSignatures: Set<String> = []

    func generate(
        wardrobe: [GarmentSnapshot],
        engine: OutfitEngine,
        limit: Int = 3,
        startOver: Bool = false
    ) async {
        if startOver {
            seenSignatures.removeAll()
            hasWrappedAround = false
        }

        readiness = WardrobeReadiness.evaluate(wardrobe)
        guard readiness.canSuggest else {
            suggestions = []
            return
        }

        isLoading = true
        defer { isLoading = false }

        var result = await engine.suggestions(from: wardrobe, limit: limit, excluding: seenSignatures)

        if result.isEmpty && !seenSignatures.isEmpty {
            seenSignatures.removeAll()
            hasWrappedAround = true
            result = await engine.suggestions(from: wardrobe, limit: limit)
        } else {
            hasWrappedAround = false
        }

        suggestions = result
        seenSignatures.formUnion(result.map(\.signature))
    }
}
