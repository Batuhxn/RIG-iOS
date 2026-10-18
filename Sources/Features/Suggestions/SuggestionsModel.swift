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
    /// Only the latest generate may publish. A re-rank triggered by a new
    /// forecast must never be overwritten by an older run finishing late.
    @ObservationIgnored private var generation = LatestRequestGate()

    /// Ready wardrobes can still return no looks (for example after filtering).
    /// That is not evidence that a particular category is missing.
    var emptyResultMessage: String {
        readiness.canSuggest
            ? "No looks are available right now. Try again after reviewing your wardrobe."
            : readiness.explanation
    }

    /// Nonisolated on purpose: this is created as a `@State` default value
    /// inside a view struct, which is not itself actor-isolated. Every
    /// stored property above starts from a `Sendable` constant, so there is
    /// nothing isolated to touch here.
    nonisolated init() {}

    func generate(
        wardrobe: [GarmentSnapshot],
        engine: OutfitEngine,
        limit: Int = 3,
        startOver: Bool = false,
        weather: WeatherContext? = nil
    ) async {
        let ticket = generation.issue()
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

        var result = await Self.rank(wardrobe, engine: engine, limit: limit, excluding: seenSignatures, weather: weather)
        guard generation.isCurrent(ticket) else { return }

        if result.isEmpty && !seenSignatures.isEmpty {
            seenSignatures.removeAll()
            hasWrappedAround = true
            result = await Self.rank(wardrobe, engine: engine, limit: limit, excluding: [], weather: weather)
            guard generation.isCurrent(ticket) else { return }
        } else {
            hasWrappedAround = false
        }

        isLoading = false
        suggestions = result
        seenSignatures.formUnion(result.map(\.signature))
    }
}

extension SuggestionsModel {
    /// With a usable forecast, the engine's weather-aware rule ranking; without
    /// one, exactly the path RIG ran before weather existed. The weather path is
    /// rules only: v0.1 wires no compatibility provider, so nothing is skipped
    /// today, but enabling one later must revisit this (see PR #2 review).
    nonisolated static func rank(
        _ wardrobe: [GarmentSnapshot],
        engine: OutfitEngine,
        limit: Int,
        excluding excluded: Set<String>,
        weather: WeatherContext?
    ) async -> [OutfitSuggestion] {
        if let weather, weather.isUsable {
            return engine.weatherRankedSuggestions(from: wardrobe, weather: weather, limit: limit, excluding: excluded)
        }
        return await engine.suggestions(from: wardrobe, limit: limit, excluding: excluded)
    }
}
