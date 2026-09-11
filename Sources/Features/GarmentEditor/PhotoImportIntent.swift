import Foundation

/// What the user says they are adding, answered before the picker opens.
///
/// Asking is the whole safety mechanism for v0.3. RIG cannot yet tell a mirror
/// selfie from a photograph of one folded jumper, and a wrong guess produces a
/// garment that is actually a whole person. So it asks, once, in plain words,
/// and every decision below this point follows from the answer.
enum PhotoImportIntent: String, CaseIterable, Identifiable, Sendable {
    /// One garment per photograph, however many photographs that is.
    case individualItems
    /// A single photograph holding a whole look, to be taken apart by hand.
    case outfitPhoto

    var id: String { rawValue }

    var title: String {
        switch self {
        case .individualItems: return "Individual items"
        case .outfitPhoto: return "An outfit photo"
        }
    }

    var subtitle: String {
        switch self {
        case .individualItems: return "One garment per photo"
        case .outfitPhoto: return "A full look or mirror photo"
        }
    }

    var symbolName: String {
        switch self {
        case .individualItems: return "square.grid.2x2"
        case .outfitPhoto: return "figure.stand"
        }
    }

    /// How many photographs the picker accepts for this answer. An outfit is
    /// one photograph in v0.3; batching outfits is a later milestone.
    var maximumSelectionCount: Int {
        switch self {
        case .individualItems: return BulkImportQueue.maximumSelectionCount
        case .outfitPhoto: return 1
        }
    }
}

/// Where a finished selection goes.
enum PhotoImportRoute: Equatable {
    /// No answer yet, or the picker was dismissed empty.
    case awaitingSelection
    /// The existing single-garment review.
    case singleGarment
    /// The existing bulk review queue.
    case bulkReview(count: Int)
    /// The outfit extraction session, over one source photograph.
    case outfitSession
}

/// The whole import decision, as one pure function.
///
/// The user is never asked to choose between "single" and "bulk" — that was an
/// implementation detail leaking into the interface. The number of photographs
/// they picked decides. Keeping the rule here rather than inside a view is what
/// makes it testable, and what stops a third import path quietly appearing.
enum PhotoImportRouter {
    static func route(for intent: PhotoImportIntent?, selectionCount: Int) -> PhotoImportRoute {
        guard let intent, selectionCount > 0 else { return .awaitingSelection }
        switch intent {
        case .individualItems:
            guard selectionCount > 1 else { return .singleGarment }
            return .bulkReview(count: min(selectionCount, intent.maximumSelectionCount))
        case .outfitPhoto:
            return .outfitSession
        }
    }
}
