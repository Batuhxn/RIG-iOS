import Foundation

/// One wardrobe image path, copied out of SwiftData before similarity work.
struct GarmentDuplicateSource: Sendable {
    let garmentID: UUID
    let category: GarmentCategory
    let imagePath: String
    /// Stored visual identity; when it is from the current encoder the photo is not even read.
    var identity: GarmentVisualIdentity? = nil
}

enum GarmentDuplicateCheck {
    enum Outcome: Equatable {
        case save
        case review(candidateImageData: Data, state: DuplicateReviewState)
    }

    /// Both import flows use the same category scope, matcher and thresholds.
    /// Matching always uses the identity image (the cutout when there is one),
    /// the same image a stored identity was computed from; the user's display
    /// choice only decides which photo the review sheet shows. Missing image
    /// data or a matcher failure yields no suggestions and leaves the garment
    /// saveable.
    static func evaluate(
        result: GarmentImportResult,
        choice: GarmentImageChoice,
        category: GarmentCategory,
        sources: [GarmentDuplicateSource],
        store: GarmentImageStore,
        matcher: any GarmentSimilarityMatching
    ) async -> Outcome {
        await evaluateReportingIdentities(
            result: result, choice: choice, category: category, sources: sources, store: store, matcher: matcher
        ).outcome
    }

    /// `evaluate`, plus the identities computed for existing garments that had none stored
    /// (or one from another encoder), keyed by garment, for the caller to persist.
    static func evaluateReportingIdentities(
        result: GarmentImportResult,
        choice: GarmentImageChoice,
        category: GarmentCategory,
        sources: [GarmentDuplicateSource],
        store: GarmentImageStore,
        matcher: any GarmentSimilarityMatching
    ) async -> (outcome: Outcome, computedIdentities: [UUID: GarmentVisualIdentity]) {
        guard let imageData = store.data(atRelativePath: result.identityImageRelativePath) else {
            return (.save, [:])
        }
        let displayData = store.data(atRelativePath: choice.relativePath(in: result)) ?? imageData
        let currentModelID = await matcher.identityModelID()
        let currentDimension = await matcher.identityDimension()
        let candidates = sources.compactMap { source -> WardrobeSimilarityCandidateItem? in
            guard source.category == category, source.garmentID != result.garmentID else { return nil }
            // A current stored identity makes the photo unnecessary; only items without one, or
            // with one from another encoder, are read from disk (and re-embedded by the matcher).
            // A stored identity is only usable when it comes from the current encoder and has
            // that encoder's length; a truncated or foreign vector is re-embedded from the photo.
            let isCurrent = source.identity.map { identity in
                (currentModelID == nil || identity.modelID == currentModelID)
                    && (currentDimension == nil || identity.vector.count == currentDimension)
            } ?? false
            let data = isCurrent ? Data() : store.data(atRelativePath: source.imagePath)
            guard let data, isCurrent || !data.isEmpty else { return nil }
            return WardrobeSimilarityCandidateItem(
                garmentID: source.garmentID,
                category: source.category,
                imageData: data,
                identity: source.identity
            )
        }
        let ranking = await matcher.rankSimilarItemsReportingIdentities(
            to: imageData,
            among: WardrobeSimilarityQuery.candidates(
                from: candidates,
                category: category,
                excluding: result.garmentID
            ),
            thresholds: .conservativeDefault
        )
        let review = DuplicateReviewState(matches: ranking.matches)
        let outcome: Outcome = review.isExhausted ? .save : .review(candidateImageData: displayData, state: review)
        return (outcome, ranking.computedIdentities)
    }
}
