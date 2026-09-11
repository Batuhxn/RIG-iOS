import Foundation

/// Where a garment region came from.
///
/// **v0.4 seam.** An automatic proposer becomes another case here and nothing
/// downstream changes: the session, the review screen and the import pipeline
/// all treat a candidate the same way whether a finger or a model drew the
/// rectangle. Nothing in this file knows that cropping exists.
enum OutfitCandidateOrigin: Equatable, Sendable {
    case manualCrop
    /// The saved region's content came from an EdgeSAM mask proposed inside a
    /// manually drawn box and accepted by the user. The box itself was still
    /// drawn by hand — v0.4 Slice 2 never proposes a region on its own, only
    /// a mask within one already drawn.
    case aiAssistedCrop
}

/// How far one garment has got.
enum OutfitCandidateStage: Equatable {
    /// The rectangle is being drawn or redrawn. No files exist yet.
    case drafting
    /// Cropped and processed. Files are on disk, metadata not yet confirmed.
    case ready(GarmentImportResult)
    /// Cropping, processing or saving failed. Recoverable, and local to this candidate.
    case failed(String)
    /// Persisted as a new `ClothingItem`. Its files must survive the session.
    case saved
    /// Resolved to a wardrobe item that already existed, instead of becoming
    /// a new one. No new `ClothingItem` was created and no existing item's
    /// canonical image was touched, so — unlike `.saved` — this candidate's
    /// own files own nothing that must survive; they are cleaned up exactly
    /// like a discarded candidate's.
    case linkedExisting(garmentID: UUID)
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
    /// The AI mask currently proposed or accepted for this candidate, when
    /// `origin == .aiAssistedCrop`. `qualityScore` on it describes
    /// segmentation quality only — see `SegmentationMaskResult` — and must
    /// never be presented as garment confidence.
    var proposedMask: SegmentationMaskResult?
    /// Positive/negative points accumulated for this candidate's *current*
    /// box, sent alongside it on every re-decode (v0.4 Slice 2.1). Reset
    /// with `proposedMask` wherever the box itself changes — a new region
    /// makes a prior refinement point's placement meaningless. Living on
    /// the candidate rather than on the view means a fresh
    /// `OutfitGarmentCandidate` (every `beginCandidate` call) starts with an
    /// empty array by construction: nothing here can leak from one garment
    /// into the next.
    var refinementPoints: [EdgeSAMGeometry.PromptPoint] = []
    var stage: OutfitCandidateStage

    init(
        id: UUID = UUID(),
        region: NormalizedCropRect = .centeredDefault,
        origin: OutfitCandidateOrigin = .manualCrop,
        suggestedCategory: GarmentCategory? = nil,
        confidence: Double? = nil,
        proposedMask: SegmentationMaskResult? = nil,
        refinementPoints: [EdgeSAMGeometry.PromptPoint] = [],
        stage: OutfitCandidateStage = .drafting
    ) {
        self.id = id
        self.region = region
        self.origin = origin
        self.suggestedCategory = suggestedCategory
        self.confidence = confidence
        self.proposedMask = proposedMask
        self.refinementPoints = refinementPoints
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

    var linkedGarmentID: UUID? {
        if case .linkedExisting(let garmentID) = stage { return garmentID }
        return nil
    }

    var isSaved: Bool { stage == .saved }
    /// A final resolution the user actually chose: either a new garment, or a
    /// link to one that already existed. Used wherever the session needs to
    /// count what this photo produced, not just what got persisted as a
    /// brand-new row.
    var isResolved: Bool { isSaved || linkedGarmentID != nil }
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
    /// Candidates resolved to an existing wardrobe item rather than saved as
    /// new. Their own identifiers are never real garments — see
    /// `OutfitCandidateStage.linkedExisting`.
    var linkedCount: Int { candidates.filter { $0.linkedGarmentID != nil }.count }
    /// Every candidate this photograph actually resolved, new or linked.
    var resolvedCount: Int { candidates.filter(\.isResolved).count }
    var failedCount: Int { candidates.filter(\.isFailed).count }

    /// Every identifier whose files must not outlive the session.
    ///
    /// Only a newly saved garment owns files that must survive. Everything
    /// else does not — including a candidate linked to an existing item,
    /// which never became a garment of its own, and any candidate that never
    /// got as far as writing one. Removing a directory that was never written
    /// is a no-op, so over-reporting here is safe and under-reporting is not.
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
        // A mask (and any refinement points) proposed for the previous
        // rectangle no longer describes this one. Clearing them here,
        // rather than trusting every call site to remember to, is what
        // keeps a stale overlay — or a stale point sitting outside the new
        // box — from ever being shown.
        candidates[activeIndex].proposedMask = nil
        candidates[activeIndex].refinementPoints = []
        candidates[activeIndex].origin = .manualCrop
    }

    /// Records an AI-proposed mask against the open candidate without
    /// changing its stage — the user still has to accept it (`markReady`) or
    /// reject it before anything is written to disk. Passing `nil` clears a
    /// previously proposed mask, e.g. when the user asks to see the plain
    /// rectangular crop instead.
    mutating func proposeMask(_ mask: SegmentationMaskResult?) {
        guard let activeIndex, candidates.indices.contains(activeIndex) else { return }
        candidates[activeIndex].proposedMask = mask
        candidates[activeIndex].origin = mask != nil ? .aiAssistedCrop : .manualCrop
    }

    /// Replaces the open candidate's accumulated refinement points —
    /// every positive/negative point sent alongside its box on the next
    /// decode. Separate from `proposeMask` because a refinement re-decode
    /// updates points and mask together but from two independent pieces of
    /// state, and because seeding the very first prompt's default center
    /// point (v0.4 Slice 2.1) needs to set points before any mask exists.
    mutating func setRefinementPoints(_ points: [EdgeSAMGeometry.PromptPoint]) {
        guard let activeIndex, candidates.indices.contains(activeIndex) else { return }
        candidates[activeIndex].refinementPoints = points
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

    /// Resolves the open candidate to an existing wardrobe item instead of
    /// saving it as new. Returns false, exactly like `markSaved`, when there
    /// is nothing processed yet to resolve.
    ///
    /// This never creates a `ClothingItem` and never touches the linked
    /// item's own stored image — the caller is only recording that this
    /// source-photo garment refers to `garmentID`. See
    /// `OutfitCandidateStage.linkedExisting`.
    @discardableResult
    mutating func markLinkedExisting(_ garmentID: UUID) -> Bool {
        guard let activeIndex, candidates.indices.contains(activeIndex),
              candidates[activeIndex].importResult != nil else { return false }
        candidates[activeIndex].stage = .linkedExisting(garmentID: garmentID)
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
    /// second attempt overwrites rather than orphans. Any previously proposed
    /// mask, and any refinement points accumulated against it, are cleared
    /// along with it — a fresh crop starts fresh.
    mutating func recrop() {
        guard let activeIndex, candidates.indices.contains(activeIndex),
              !candidates[activeIndex].isSaved,
              candidates[activeIndex].linkedGarmentID == nil else { return }
        candidates[activeIndex].stage = .drafting
        candidates[activeIndex].proposedMask = nil
        candidates[activeIndex].refinementPoints = []
        candidates[activeIndex].origin = .manualCrop
    }
}
