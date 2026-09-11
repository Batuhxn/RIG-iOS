import Foundation

/// One photograph waiting to be reviewed during a bulk import.
///
/// The identifier is reserved *before* the image is processed and handed to
/// `GarmentImportService` as the garment ID. That is what makes clean-up
/// trivial: every byte this item will ever write already lives under a
/// directory named by this identifier, whether or not the item is ever saved.
struct BulkImportQueueItem: Identifiable, Equatable {
    enum Status: Equatable {
        /// Selected, not yet decoded. No files exist for it.
        case pending
        /// Processed. Files are on disk, metadata not yet confirmed.
        case ready(GarmentImportResult)
        /// Processing or saving failed. Recoverable: retry or skip.
        case failed(String)
        /// Persisted as a `ClothingItem`. Its files must survive.
        case saved
        /// Deliberately passed over. Its files must not survive.
        case skipped
    }

    let id: UUID
    /// Position in the user's selection, which also indexes the picker items
    /// the view holds. Stable for the life of the queue.
    let position: Int
    var status: Status = .pending

    var importResult: GarmentImportResult? {
        if case .ready(let result) = status { return result }
        return nil
    }

    var failureMessage: String? {
        if case .failed(let message) = status { return message }
        return nil
    }

    var isSaved: Bool { status == .saved }
    var isSkipped: Bool { status == .skipped }
    var isFailed: Bool { failureMessage != nil }
}

/// The review queue behind bulk import.
///
/// Deliberately transient: this is application state for the duration of one
/// sheet, never a persisted row. A half-finished import leaves nothing behind
/// in SwiftData because nothing is inserted until the user confirms a garment.
///
/// It also holds no image bytes — only identifiers, positions and paths — so a
/// twenty-item queue costs a few hundred bytes rather than twenty decoded
/// photographs.
struct BulkImportQueue: Equatable {
    /// The one place the batch size is decided. Twenty is comfortably more than
    /// a single review sitting and comfortably under the point where a user
    /// cannot remember what they selected.
    static let maximumSelectionCount = 20

    private(set) var items: [BulkImportQueueItem]
    private(set) var index: Int

    init(garmentIDs: [UUID] = []) {
        items = garmentIDs.enumerated().map { BulkImportQueueItem(id: $1, position: $0) }
        index = 0
    }

    /// Reserves one identifier per selected photograph, capped at the limit
    /// above so a picker that returns more than asked cannot overrun the queue.
    static func reserving(_ count: Int) -> BulkImportQueue {
        let bounded = min(max(count, 0), maximumSelectionCount)
        return BulkImportQueue(garmentIDs: (0..<bounded).map { _ in UUID() })
    }

    // MARK: - Reading

    var count: Int { items.count }
    var isEmpty: Bool { items.isEmpty }
    var isComplete: Bool { index >= items.count }

    var current: BulkImportQueueItem? {
        items.indices.contains(index) ? items[index] : nil
    }

    /// "3 of 12". Clamped so a finished queue reads as complete rather than
    /// as one past the end.
    var progressLabel: String {
        guard !items.isEmpty else { return "0 of 0" }
        let position = isComplete ? items.count : index + 1
        return "\(position) of \(items.count)"
    }

    /// Going back onto a saved garment is refused. A save is a commit, and the
    /// cheapest way to guarantee bulk import can never write the same garment
    /// twice is to make it unreachable.
    var canGoBack: Bool {
        index > 0 && items.indices.contains(index - 1) && !items[index - 1].isSaved
    }

    var savedGarmentIDs: [UUID] { items.filter(\.isSaved).map(\.id) }
    var savedCount: Int { items.filter(\.isSaved).count }
    var skippedCount: Int { items.filter(\.isSkipped).count }
    var failedCount: Int { items.filter(\.isFailed).count }

    /// Every identifier whose files must not outlive the sheet.
    ///
    /// Saved garments own their files; everything else does not, including
    /// items that were never processed. Removing a directory that was never
    /// written is a no-op, so over-reporting here is safe and under-reporting
    /// is not.
    var garmentIDsPendingCleanup: [UUID] {
        items.filter { !$0.isSaved }.map(\.id)
    }

    // MARK: - Advancing

    mutating func markReady(_ result: GarmentImportResult) {
        guard items.indices.contains(index) else { return }
        items[index].status = .ready(result)
    }

    /// A per-item failure never touches its neighbours: the cursor stays put so
    /// the user can retry or skip, and the rest of the queue is untouched.
    mutating func markFailed(_ message: String) {
        guard items.indices.contains(index) else { return }
        items[index].status = .failed(message)
    }

    /// Only a reviewed item can be saved, so a stray call cannot advance the
    /// queue past something the user never confirmed.
    @discardableResult
    mutating func markSaved() -> Bool {
        guard let item = current, item.importResult != nil else { return false }
        items[index].status = .saved
        index += 1
        return true
    }

    mutating func skip() {
        guard items.indices.contains(index) else { return }
        items[index].status = .skipped
        index += 1
    }

    /// Returns a failed item to the pending state so it is processed again from
    /// its original photograph.
    mutating func retry() {
        guard let item = current, item.isFailed else { return }
        items[index].status = .pending
    }

    /// A skipped item revisited becomes pending again, because skipping removed
    /// its files. A reviewed item keeps its result so Vision is not re-run.
    mutating func goBack() {
        guard canGoBack else { return }
        index -= 1
        if items[index].isSkipped {
            items[index].status = .pending
        }
    }
}
