import Foundation

/// One wardrobe image path, copied out of SwiftData before similarity work.
struct GarmentDuplicateSource: Sendable {
    let garmentID: UUID
    let category: GarmentCategory
    let imagePath: String
}

enum GarmentDuplicateCheck {
    enum Outcome: Equatable {
        case save
        case review(candidateImageData: Data, state: DuplicateReviewState)
    }

    /// Both import flows use the selected rendition and the same category
    /// scope, matcher and thresholds. Missing image data or a Vision failure
    /// yields no suggestions and leaves the garment saveable.
    static func evaluate(
        result: GarmentImportResult,
        choice: GarmentImageChoice,
        category: GarmentCategory,
        sources: [GarmentDuplicateSource],
        store: GarmentImageStore,
        matcher: any GarmentSimilarityMatching
    ) async -> Outcome {
        guard let imageData = store.data(atRelativePath: choice.relativePath(in: result)) else {
            return .save
        }
        let candidates = sources.compactMap { source -> WardrobeSimilarityCandidateItem? in
            guard source.category == category, source.garmentID != result.garmentID,
                  let data = store.data(atRelativePath: source.imagePath) else { return nil }
            return WardrobeSimilarityCandidateItem(
                garmentID: source.garmentID,
                category: source.category,
                imageData: data
            )
        }
        let matches = await matcher.rankSimilarItems(
            to: imageData,
            among: WardrobeSimilarityQuery.candidates(
                from: candidates,
                category: category,
                excluding: result.garmentID
            )
        )
        let review = DuplicateReviewState(matches: matches)
        return review.isExhausted ? .save : .review(candidateImageData: imageData, state: review)
    }
}
