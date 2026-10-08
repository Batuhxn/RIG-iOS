import Foundation

/// v0.4 duplicate policy, from the wardrobe-identity benchmark (217 CC0 garments cut out by
/// Apple Vision, re-captures re-cut by Vision, same-category scope): at cosine 0.89 the
/// FashionCLIP identity raised a false "already in your wardrobe?" on 0.5% of new garments
/// and found 71% of re-captures; Vision feature prints were worse at every operating point.
/// Product rule (2026-10-08): one suggestion at most, false prompts <= ~1%, no score shown.
enum WardrobeIdentityPolicy {
    static let threshold: Float = 0.89
}

/// Picks the single best stored identity above the threshold. Foundation-only, so the
/// decision is unit-tested off-device and matches the offline benchmark.
enum WardrobeIdentityMatching {
    static func best(
        candidate: GarmentVisualIdentity,
        among items: [(garmentID: UUID, identity: GarmentVisualIdentity)],
        threshold: Float = WardrobeIdentityPolicy.threshold
    ) -> (garmentID: UUID, similarity: Float)? {
        var best: (garmentID: UUID, similarity: Float)?
        for item in items {
            guard let similarity = candidate.similarity(to: item.identity), similarity.isFinite,
                  similarity >= threshold else { continue }
            if let current = best {
                let better = similarity > current.similarity
                    || (similarity == current.similarity && item.garmentID.uuidString < current.garmentID.uuidString)
                if better { best = (item.garmentID, similarity) }
            } else {
                best = (item.garmentID, similarity)
            }
        }
        return best
    }
}

/// The wardrobe-identity matcher behind the existing `GarmentSimilarityMatching` seam.
/// It replaces Vision feature prints: one encoder, the same embedding v0.3 computes on import.
/// Items saved before v0.4, or under another encoder, are embedded from their stored photo
/// on demand. Any failure means "no suggestion", never a blocked save.
struct EmbeddingSimilarityMatcher: GarmentSimilarityMatching {
    let provider: any GarmentIdentityProviding
    var threshold: Float = WardrobeIdentityPolicy.threshold

    func rankSimilarItems(
        to candidateImageData: Data,
        among items: [WardrobeSimilarityCandidateItem],
        thresholds: SimilarityThresholds
    ) async -> [WardrobeSimilarityMatch] {
        guard !items.isEmpty, let candidate = await provider.identity(for: candidateImageData) else { return [] }
        var known: [(garmentID: UUID, identity: GarmentVisualIdentity)] = []
        for item in items {
            if let stored = item.identity, stored.modelID == candidate.modelID {
                known.append((item.garmentID, stored))
            } else if !item.imageData.isEmpty, let fresh = await provider.identity(for: item.imageData) {
                known.append((item.garmentID, fresh))
            }
        }
        guard let best = WardrobeIdentityMatching.best(candidate: candidate, among: known, threshold: threshold) else {
            return []
        }
        // The band is no longer shown; `distance` keeps ordering semantics for callers and tests.
        return [WardrobeSimilarityMatch(garmentID: best.garmentID, band: .verySimilar, distance: 1 - best.similarity)]
    }
}
