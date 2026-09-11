import Foundation

/// Where a finished photo selection goes.
enum PhotoImportRoute: Equatable {
    /// Nothing picked yet, or the picker was dismissed empty.
    case awaitingSelection
    /// The single-garment review.
    case singleGarment
    /// The bulk review queue.
    case bulkReview(count: Int)
}

/// The whole import decision, as one pure function.
///
/// The user is never asked to choose between "single" and "bulk" — that was an
/// implementation detail leaking into the interface. The number of photographs
/// they picked decides. Keeping the rule here rather than inside a view is what
/// makes it testable, and what stops a third import path quietly appearing.
enum PhotoImportRouter {
    /// How many photographs the picker accepts. One garment per photograph,
    /// however many photographs that is.
    static var maximumSelectionCount: Int { BulkImportQueue.maximumSelectionCount }

    static func route(selectionCount: Int) -> PhotoImportRoute {
        guard selectionCount > 0 else { return .awaitingSelection }
        guard selectionCount > 1 else { return .singleGarment }
        return .bulkReview(count: min(selectionCount, maximumSelectionCount))
    }
}
