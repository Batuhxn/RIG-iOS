import Foundation

/// A duplicate suggestion belongs to exactly one bulk queue item. Clearing
/// this single value dismisses its image and matches together.
struct BulkDuplicateReview: Equatable {
    let itemID: UUID
    let candidateImageData: Data
    var state: DuplicateReviewState

    mutating func showAnother() {
        state.showAnother()
    }
}
