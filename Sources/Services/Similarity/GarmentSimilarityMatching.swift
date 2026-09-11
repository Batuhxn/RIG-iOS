import Foundation

/// How similar RIG judges two garment images to be, in the vocabulary the
/// interface is allowed to use.
///
/// Never a percentage. This is visual similarity retrieval, not semantic
/// duplicate detection, and there is no calibrated probability behind it —
/// the same reasoning that keeps `MatchBadge` to words instead of a number
/// (see docs/DECISIONS.md, "The interface shows bands, never numbers").
enum SimilarityBand: String, CaseIterable, Sendable, Equatable {
    case possibleMatch
    case similar
    case verySimilar

    var displayLabel: String {
        switch self {
        case .possibleMatch: return "Possible match"
        case .similar: return "Similar"
        case .verySimilar: return "Very similar"
        }
    }
}

/// Where the bands sit on a feature-print distance, and the cutoff above
/// which nothing is surfaced at all.
///
/// `VNFeaturePrintObservation.computeDistance` produces a non-negative float
/// where 0 is identical and larger values are less alike; it is not bounded
/// to `[0, 1]` and its useful range depends on the feature-print revision.
/// The literal numbers below are a conservative starting point, not a
/// calibrated result — see the v0.4 Slice 2 report's "known limitations" for
/// why these specifically still need real wardrobe photographs to tune.
/// Change only these three numbers to retune the bands; nothing else in this
/// file depends on their values.
struct SimilarityThresholds: Sendable, Equatable {
    var verySimilar: Float
    var similar: Float
    /// Above this distance, nothing is surfaced — anything past "possible
    /// match" is not worth interrupting the user for.
    var possibleMatch: Float

    static let conservativeDefault = SimilarityThresholds(verySimilar: 0.3, similar: 0.5, possibleMatch: 0.75)

    /// The band for one distance, or nil when it does not clear even the
    /// weakest threshold — the caller's signal to surface nothing for it.
    func band(forDistance distance: Float) -> SimilarityBand? {
        guard distance.isFinite, distance >= 0 else { return nil }
        if distance <= verySimilar { return .verySimilar }
        if distance <= similar { return .similar }
        if distance <= possibleMatch { return .possibleMatch }
        return nil
    }
}

/// One existing wardrobe item eligible for comparison.
///
/// Deliberately `Data` and a plain category, not a `ClothingItem`: this file
/// must not import SwiftData, for the same reason `OutfitEngine` scores
/// `GarmentSnapshot` rather than a model — see docs/DECISIONS.md, "The
/// outfit engine works on snapshots, not on models".
struct WardrobeSimilarityCandidateItem: Sendable, Equatable {
    let garmentID: UUID
    let category: GarmentCategory
    let imageData: Data
}

/// One ranked result: an existing item, and how similar RIG judges it.
struct WardrobeSimilarityMatch: Identifiable, Sendable, Equatable {
    var id: UUID { garmentID }
    let garmentID: UUID
    let band: SimilarityBand
    /// Kept for ranking and for tests only. Never shown to the user as a
    /// number — see `SimilarityBand`.
    let distance: Float
}

/// Turns already-computed distances into ranked, banded matches.
///
/// Split out from `GarmentSimilarityMatching` so the ordering and threshold
/// behaviour — the part v0.4 Slice 2's tests actually need to pin down — is
/// plain Foundation logic with no dependency on Vision ever running.
enum WardrobeSimilarityRanking {
    /// Bands and sorts, most similar first. A distance that does not clear
    /// even the weakest threshold is dropped rather than included as "no
    /// match" — the empty case is silence, not a fourth band.
    static func rank(
        distances: [(garmentID: UUID, distance: Float)],
        thresholds: SimilarityThresholds = .conservativeDefault
    ) -> [WardrobeSimilarityMatch] {
        distances
            .compactMap { entry -> WardrobeSimilarityMatch? in
                guard let band = thresholds.band(forDistance: entry.distance) else { return nil }
                return WardrobeSimilarityMatch(garmentID: entry.garmentID, band: band, distance: entry.distance)
            }
            .sorted { $0.distance < $1.distance }
    }
}

/// Builds the candidate set for one similarity check.
enum WardrobeSimilarityQuery {
    /// Existing items in the same confirmed category as the one being
    /// imported, excluding the candidate's own eventual garment id so a
    /// re-check against a half-imported wardrobe can never match itself.
    ///
    /// Category filtering happens here, at the call site, rather than inside
    /// the matching protocol — deliberately, so it can only ever run once a
    /// category is actually confirmed. v0.4 Slice 2 asks for that
    /// confirmation during metadata review, before this is ever called.
    static func candidates(
        from items: [WardrobeSimilarityCandidateItem],
        category: GarmentCategory,
        excluding excludedID: UUID? = nil
    ) -> [WardrobeSimilarityCandidateItem] {
        items.filter { $0.category == category && $0.garmentID != excludedID }
    }
}

/// The seam between "does the wardrobe already have this" and whatever
/// answers it.
///
/// Advisory only, and never fatal: a caller that gets `[]` back must proceed
/// exactly as though nothing had been asked, because that is one of the
/// possible honest answers, not a special case — "no comparison suggestion
/// available" is success, not failure. `GarmentSimilarityMatching` deals in
/// `Data` and Foundation-only value types for the same reason
/// `GarmentBackgroundRemoving` and `GarmentSegmenting` do.
protocol GarmentSimilarityMatching: Sendable {
    /// Ranks `items` by visual similarity to `candidateImageData`, most
    /// similar first, keeping only matches at or above `thresholds`' weakest
    /// band. Implementations must not throw: an internal failure should be
    /// caught and reported as `[]`, because duplicate-matching failure must
    /// never block garment creation.
    func rankSimilarItems(
        to candidateImageData: Data,
        among items: [WardrobeSimilarityCandidateItem],
        thresholds: SimilarityThresholds
    ) async -> [WardrobeSimilarityMatch]
}

extension GarmentSimilarityMatching {
    func rankSimilarItems(
        to candidateImageData: Data,
        among items: [WardrobeSimilarityCandidateItem]
    ) async -> [WardrobeSimilarityMatch] {
        await rankSimilarItems(to: candidateImageData, among: items, thresholds: .conservativeDefault)
    }
}

/// Always answers "no comparison suggestion available". Used in previews,
/// tests, and as the safe fallback wherever similarity matching itself is
/// unavailable — mirrors `PassthroughBackgroundRemover`.
struct PassthroughSimilarityMatcher: GarmentSimilarityMatching {
    func rankSimilarItems(
        to candidateImageData: Data,
        among items: [WardrobeSimilarityCandidateItem],
        thresholds: SimilarityThresholds
    ) async -> [WardrobeSimilarityMatch] {
        []
    }
}
