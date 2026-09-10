import Foundation

/// The authority on what RIG suggests.
///
/// Flow:
///
///     wardrobe
///        -> candidate generation      (bounded, deterministic)
///        -> hard validity gate        (OutfitValidator, non-negotiable)
///        -> rule scoring              (colour, season, completeness, favourites)
///        -> optional compatibility signal on the top few only, capped
///        -> diversified ranking
///        -> suggestions
///
/// The engine is a value type with no state of its own, so it is safe to hold
/// in the SwiftUI environment and to call from any task.
struct OutfitEngine: Sendable {
    let configuration: OutfitEngineConfiguration
    let compatibilityProvider: (any CompatibilityProvider)?

    init(
        configuration: OutfitEngineConfiguration = .default,
        compatibilityProvider: (any CompatibilityProvider)? = nil
    ) {
        self.configuration = configuration
        self.compatibilityProvider = compatibilityProvider
    }

    var generator: CandidateGenerator {
        CandidateGenerator(configuration: configuration)
    }

    // MARK: - Scoring

    /// Pure, synchronous, side-effect free. Given the same garments it always
    /// returns the same numbers.
    func score(_ items: [GarmentSnapshot], compatibilitySignal: Double? = nil) -> OutfitScoreBreakdown {
        let color = ColorHarmony.score(for: items.map(\.colorFamily))
        let season = SeasonCoherence.score(for: items.map(\.seasons))
        let completeness = OutfitCompleteness.score(for: items)
        let preference = PreferenceWeighting.score(for: items)

        let weighted =
            color * configuration.colorWeight
            + season * configuration.seasonWeight
            + completeness * configuration.completenessWeight
            + preference * configuration.preferenceWeight
        let ruleTotal = Self.clamp(weighted)

        guard let rawSignal = compatibilitySignal else {
            return OutfitScoreBreakdown(
                color: color,
                season: season,
                completeness: completeness,
                preference: preference,
                ruleTotal: ruleTotal,
                compatibilitySignal: nil,
                total: ruleTotal
            )
        }

        let boundedSignal = Self.clamp(rawSignal)
        let weight = configuration.effectiveCompatibilitySignalWeight
        let blended = Self.clamp(ruleTotal * (1 - weight) + boundedSignal * weight)

        return OutfitScoreBreakdown(
            color: color,
            season: season,
            completeness: completeness,
            preference: preference,
            ruleTotal: ruleTotal,
            compatibilitySignal: boundedSignal,
            total: blended
        )
    }

    // MARK: - Suggestions

    /// Rules only. This is the path v0.1 actually runs, and the path tests use.
    ///
    /// `excluding` holds signatures the user has already been shown. "Show me
    /// another set" walks further down the same deterministic ranking rather
    /// than reshuffling, so a second tap is genuinely new rather than random.
    func rankedSuggestions(
        from wardrobe: [GarmentSnapshot],
        limit: Int = 3,
        excluding excludedSignatures: Set<String> = []
    ) -> [OutfitSuggestion] {
        let candidates = generator.candidates(from: wardrobe)
            .filter { !excludedSignatures.contains($0.signature) }
        let scored = candidates.map { OutfitSuggestion(candidate: $0, breakdown: score($0.items)) }
        return Self.diversify(Self.sorted(scored), limit: limit)
    }

    /// Rules first, then — only if a provider is enabled — a capped signal on
    /// the strongest few candidates. Re-scoring every candidate through a model
    /// would be the expensive mistake; the provider only ever sees a shortlist.
    func suggestions(
        from wardrobe: [GarmentSnapshot],
        limit: Int = 3,
        excluding excludedSignatures: Set<String> = []
    ) async -> [OutfitSuggestion] {
        let candidates = generator.candidates(from: wardrobe)
            .filter { !excludedSignatures.contains($0.signature) }
        guard !candidates.isEmpty else { return [] }

        let ruleScored = candidates.map { OutfitSuggestion(candidate: $0, breakdown: score($0.items)) }
        let ruleRanked = Self.sorted(ruleScored)

        guard let provider = compatibilityProvider, provider.isEnabled else {
            return Self.diversify(ruleRanked, limit: limit)
        }

        let depth = min(configuration.compatibilityRescoreDepth, ruleRanked.count)
        var rescored = ruleRanked
        for index in 0..<depth {
            let candidate = ruleRanked[index].candidate
            // A provider that fails or declines to answer must never break a
            // suggestion. Its absence simply leaves the rule score standing.
            // `try?` on an optional-returning throwing call nests two layers of
            // optionality; flatten before deciding whether there is an opinion.
            let signal = (try? await provider.compatibilitySignal(for: candidate.items)) ?? nil
            guard let signal else { continue }
            rescored[index] = OutfitSuggestion(
                candidate: candidate,
                breakdown: score(candidate.items, compatibilitySignal: signal)
            )
        }

        return Self.diversify(Self.sorted(rescored), limit: limit)
    }

    // MARK: - Ranking helpers

    /// Highest total first; ties broken by signature so ordering is total and
    /// reproducible rather than dependent on sort stability.
    static func sorted(_ suggestions: [OutfitSuggestion]) -> [OutfitSuggestion] {
        suggestions.sorted { lhs, rhs in
            if lhs.breakdown.total != rhs.breakdown.total {
                return lhs.breakdown.total > rhs.breakdown.total
            }
            return lhs.signature < rhs.signature
        }
    }

    /// Prefer a different structural base for each suggestion, then backfill.
    /// Without this a batch is often one pair of trousers wearing three
    /// different shoes, which reads as a broken feature.
    static func diversify(_ sortedSuggestions: [OutfitSuggestion], limit: Int) -> [OutfitSuggestion] {
        guard limit > 0 else { return [] }

        var picked: [OutfitSuggestion] = []
        var usedBases = Set<String>()
        for suggestion in sortedSuggestions {
            guard picked.count < limit else { break }
            let base = suggestion.candidate.baseSignature
            guard usedBases.insert(base).inserted else { continue }
            picked.append(suggestion)
        }

        if picked.count < limit {
            let alreadyPicked = Set(picked.map(\.signature))
            for suggestion in sortedSuggestions where !alreadyPicked.contains(suggestion.signature) {
                guard picked.count < limit else { break }
                picked.append(suggestion)
            }
        }
        return picked
    }

    static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
