import Foundation

/// The user's place in reviewing duplicate suggestions for one candidate.
///
/// Pure state, no view code, so its cycling logic is directly testable
/// without SwiftUI. `DuplicateComparisonSheet` is a thin presentation over
/// this.
struct DuplicateReviewState: Equatable {
    let matches: [WardrobeSimilarityMatch]
    private(set) var index: Int = 0

    /// At most the three strongest matches — "up to the best 3", per the
    /// product requirement. Showing more would turn a quick comparison into
    /// a search.
    init(matches: [WardrobeSimilarityMatch]) {
        self.matches = Array(matches.prefix(3))
    }

    /// The match on screen right now, or nil once every candidate has been
    /// dismissed — the caller's signal to fall through to the ordinary
    /// add-as-new flow rather than keep showing a comparison screen with
    /// nothing left to compare against.
    var current: WardrobeSimilarityMatch? {
        matches.indices.contains(index) ? matches[index] : nil
    }

    var hasAnother: Bool { index + 1 < matches.count }

    /// True when there is nothing left to show — either no candidate ever
    /// qualified, or every one offered has been dismissed as "not a match".
    /// A caller building this state from an empty ranking should not present
    /// the sheet at all, per the product requirement that a weak or absent
    /// match must never interrupt the user.
    var isExhausted: Bool { matches.isEmpty || index >= matches.count }

    /// "Not a match" — advances to the next candidate. Past the last one,
    /// `current` becomes nil and `isExhausted` becomes true.
    mutating func showAnother() {
        index += 1
    }
}
