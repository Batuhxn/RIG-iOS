import Foundation

/// Where a garment region came from.
///
/// **v0.4 seam.** An automatic proposer becomes another case here and nothing
/// downstream changes: the session, the review screen and the import pipeline
/// all treat a candidate the same way whether a finger or a model drew the
/// rectangle. Nothing in this file knows that cropping exists.
enum OutfitCandidateOrigin: Equatable, Sendable {
    case manualCrop
}

/// How far one garment has got.
enum OutfitCandidateStage: Equatable {
    /// The rectangle is being drawn or redrawn. No files exist yet.
    case drafting
    /// Cropped and processed. Files are on disk, metadata not yet confirmed.
    case ready(GarmentImportResult)
    /// Cropping, processing or saving failed. Recoverable, and local to this candidate.
    case failed(String)
    /// Persisted as a `ClothingItem`. Its files must survive the session.
    case saved
    /// Abandoned by the user. Its files must not survive.
    case discarded
}

/// One garment being pulled out of an outfit photograph.
struct OutfitGarmentCandidate: Identifiable, Equatable {
    /// Reserved before any work happens and used as the garment ID, so every
    /// file this candidate writes is already filed under its eventual owner.
    let id: UUID
    var region: NormalizedCropRect
    var origin: OutfitCandidateOrigin
    /// Unused in v0.3 — the user always picks the category. Present so that an
    /// automatic proposer has somewhere to put a guess without a model change.
    var suggestedCategory: GarmentCategory?
    var confidence: Double?
    var stage: OutfitCandidateStage

    init(
        id: UUID = UUID(),
        region: NormalizedCropRect = .centeredDefault,
        origin: OutfitCandidateOrigin = .manualCrop,
        suggestedCategory: GarmentCategory? = nil,
        confidence: Double? = nil,
        stage: OutfitCandidateStage = .drafting
    ) {
        self.id = id
        self.region = region
        self.origin = origin
        self.suggestedCategory = suggestedCategory
        self.confidence = confidence
        self.stage = stage
    }

    var importResult: GarmentImportResult? {
        if case .ready(let result) = stage { return result }
        return nil
    }

    var failureMessage: String? {
        if case .failed(let message) = stage { return message }
        return nil
    }

    var isSaved: Bool { stage == .saved }
    var isDrafting: Bool { stage == .drafting }
    var isFailed: Bool { failureMessage != nil }
}

/// One sitting with one outfit photograph.
///
/// Transient by design. The source photo and every candidate live exactly as
/// long as the sheet does; only a garment the user explicitly confirms becomes
/// a row. That is what makes cancelling safe — there is nothing half-written to
/// undo, just files to sweep.
///
/// It holds no image bytes, only identifiers and fractional rectangles, so the
/// whole session costs a few hundred bytes however many garments come out of it.
struct OutfitPhotoSession: Equatable {
    private(set) var candidates: [OutfitGarmentCandidate]
    private(set) var activeIndex: Int?

    init() {
        candidates = []
        activeIndex = nil
    }

    // MARK: - Reading

    var active: OutfitGarmentCandidate? {
        guard let activeIndex, candidates.indices.contains(activeIndex) else { return nil }
        return candidates[activeIndex]
    }

    /// True when the user is looking at the whole photograph rather than at one garment.
    var isIdle: Bool { active == nil }

    var savedCount: Int { candidates.filter(\.isSaved).count }
    var savedGarmentIDs: [UUID] { candidates.filter(\.isSaved).map(\.id) }
    var failedCount: Int { candidates.filter(\.isFailed).count }

    /// Every identifier whose files must not outlive the session.
    ///
    /// Saved garments own their files; everything else does not, including
    /// candidates that never got as far as writing one. Removing a directory
    /// that was never written is a no-op, so over-reporting here is safe and
    /// under-reporting is not.
    var garmentIDsPendingCleanup: [UUID] {
        candidates.filter { !$0.isSaved }.map(\.id)
    }

    // MARK: - Candidate lifecycle

    /// Starts a new garment. If one is already open, that one is returned
    /// untouched rather than a second being stacked behind it.
    @discardableResult
    mutating func beginCandidate(
        id: UUID = UUID(),
        region: NormalizedCropRect = .centeredDefault,
        origin: OutfitCandidateOrigin = .manualCrop,
        suggestedCategory: GarmentCategory? = nil,
        confidence: Double? = nil
    ) -> UUID {
        if let active { return active.id }
        candidates.append(
            OutfitGarmentCandidate(
                id: id,
                region: region,
                origin: origin,
                suggestedCategory: suggestedCategory,
                confidence: confidence
            )
        )
        activeIndex = candidates.count - 1
        return id
    }

    mutating func updateRegion(_ region: NormalizedCropRect) {
        guard let activeIndex, candidates.indices.contains(activeIndex) else { return }
        candidates[activeIndex].region = region.clamped()
    }

    mutating func markReady(_ result: GarmentImportResult) {
        guard let activeIndex, candidates.indices.contains(activeIndex) else { return }
        candidates[activeIndex].stage = .ready(result)
    }

    /// A failure is local to its candidate: the cursor stays on it so the user
    /// can re-crop or discard, and every other candidate is untouched.
    mutating func markFailed(_ message: String) {
        guard let activeIndex, candidates.indices.contains(activeIndex) else { return }
        candidates[activeIndex].stage = .failed(message)
    }

    /// Confirms the open garment. Returns false when there is nothing to save,
    /// which is also what makes a second call a no-op rather than a duplicate.
    @discardableResult
    mutating func markSaved() -> Bool {
        guard let activeIndex, candidates.indices.contains(activeIndex),
              candidates[activeIndex].importResult != nil else { return false }
        candidates[activeIndex].stage = .saved
        self.activeIndex = nil
        return true
    }

    mutating func discardActive() {
        guard let activeIndex, candidates.indices.contains(activeIndex) else { return }
        candidates[activeIndex].stage = .discarded
        self.activeIndex = nil
    }

    /// Sends a reviewed or failed candidate back to its rectangle. Any files it
    /// already wrote are the caller's to remove; the identifier is reused, so a
    /// second attempt overwrites rather than orphans.
    mutating func recrop() {
        guard let activeIndex, candidates.indices.contains(activeIndex),
              !candidates[activeIndex].isSaved else { return }
        candidates[activeIndex].stage = .drafting
    }
}
