import Foundation

/// v0.4 duplicate policy. Provisional production threshold, to be revisited after the iPhone
/// multi-view gate. Measured on garment-cropped cutouts:
/// - synthetic re-captures (217 CC0 garments, macOS Vision): 0.93 finds 47%, 0% false prompts
///   (0.89: 71% / 0.5%);
/// - real same-item photo pairs: 10/14 found (0.89: 14/14);
/// - real look-alike different garments, the hardest 68 pairs of ~10.8M: 13/68 prompt (0.89: 57/68).
/// The embedding cannot separate near-twin garments, so the threshold trades recall for fewer
/// prompts in wardrobes with look-alikes. Vision feature prints were worse at every point.
/// Product rule (2026-10-08): one suggestion at most, same category, no score shown.
enum WardrobeIdentityPolicy {
    static let threshold: Float = 0.93
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
/// on demand and reported back so the caller can store them. Any failure means
/// "no suggestion", never a blocked save.
struct EmbeddingSimilarityMatcher: GarmentSimilarityMatching {
    let provider: any GarmentIdentityProviding
    var threshold: Float = WardrobeIdentityPolicy.threshold

    func identityModelID() async -> String? {
        await provider.currentModelID()
    }

    func identityDimension() async -> Int? {
        await provider.currentDimension()
    }

    func rankSimilarItems(
        to candidateImageData: Data,
        among items: [WardrobeSimilarityCandidateItem],
        thresholds: SimilarityThresholds
    ) async -> [WardrobeSimilarityMatch] {
        await rankSimilarItemsReportingIdentities(to: candidateImageData, among: items, thresholds: thresholds).matches
    }

    func rankSimilarItemsReportingIdentities(
        to candidateImageData: Data,
        among items: [WardrobeSimilarityCandidateItem],
        thresholds: SimilarityThresholds
    ) async -> WardrobeSimilarityOutcome {
        guard !items.isEmpty, let candidate = await provider.identity(for: candidateImageData) else {
            return WardrobeSimilarityOutcome(matches: [])
        }
        var known: [(garmentID: UUID, identity: GarmentVisualIdentity)] = []
        var computed: [UUID: GarmentVisualIdentity] = [:]
        for item in items {
            // A stored identity of another length (truncated or corrupt) is never compared.
            if let stored = item.identity, stored.modelID == candidate.modelID, stored.vector.count == candidate.vector.count {
                known.append((item.garmentID, stored))
            } else if !item.imageData.isEmpty, let fresh = await provider.identity(for: item.imageData) {
                known.append((item.garmentID, fresh))
                computed[item.garmentID] = fresh
            }
        }
        guard let best = WardrobeIdentityMatching.best(candidate: candidate, among: known, threshold: threshold) else {
            return WardrobeSimilarityOutcome(matches: [], computedIdentities: computed)
        }
        // The band is no longer shown; `distance` keeps ordering semantics for callers and tests.
        let match = WardrobeSimilarityMatch(garmentID: best.garmentID, band: .verySimilar, distance: 1 - best.similarity)
        return WardrobeSimilarityOutcome(matches: [match], computedIdentities: computed)
    }
}
