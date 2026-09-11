import Foundation
import SwiftUI

/// The AI mask proposal half of `OutfitPhotoSessionView`, split into its own
/// file purely for the static audit's line cap — see the type's own doc
/// comment in `OutfitPhotoSessionView.swift`.
extension OutfitPhotoSessionView {
    /// One embedding session for the whole sitting, created on first use and
    /// reused by every candidate after it — the "encode once, decode many"
    /// reuse `OutfitEmbeddingSession` is built around.
    func resolvedEmbeddingSession() -> OutfitEmbeddingSession {
        if let embeddingSession { return embeddingSession }
        let created = OutfitEmbeddingSession(segmenter: services.segmenter)
        embeddingSession = created
        return created
    }

    /// Asks the segmenter for an initial mask over `region`, seeded with
    /// whatever refinement points are already on the active candidate — in
    /// practice just the box's own center point, set by `previewDraft()`
    /// just before this is called (Goal B: "Initial prompt may use the
    /// current box plus a positive center point"). A silent no-op when no
    /// segmenter is available — the plain rectangular crop already stands
    /// on its own, so this is purely additive.
    func startMaskProposal(for region: NormalizedCropRect, source imageData: Data) {
        cancelMaskProposal()
        segmentationFailureMessage = nil
        let points = session.active?.refinementPoints ?? []
        isProposingMask = true
        maskProposalTask = Task { @MainActor in
            defer { isProposingMask = false }
            guard await resolvedEmbeddingSession().isAvailable else { return }
            await applyDecodeResult(for: region, points: points, source: imageData)
        }
    }

    func cancelMaskProposal() {
        maskProposalTask?.cancel()
        maskProposalTask = nil
        isProposingMask = false
        isRefiningMask = false
    }

    /// The user tapped the image in `MaskReviewSheet` to add a positive
    /// ("include this area") or negative ("exclude this area") point (Goal
    /// B). Appends it to the active candidate's accumulated points — so it
    /// survives this one re-decode and every one after it, until the box
    /// itself changes — and re-runs the decoder against the same cached
    /// embedding `OutfitEmbeddingSession` already holds. Ignored while a
    /// decode is already in flight, rather than queued, so taps can't pile
    /// up behind a slow decode.
    func refineMaskProposal(adding point: EdgeSAMGeometry.PromptPoint) {
        guard let sourceData, session.active != nil, !isRefiningMask else { return }
        let region = maskReviewRegion
        let points = (session.active?.refinementPoints ?? []) + [point]
        session.setRefinementPoints(points)
        maskProposalTask?.cancel()
        isRefiningMask = true
        maskProposalTask = Task { @MainActor in
            defer { isRefiningMask = false }
            await applyDecodeResult(for: region, points: points, source: sourceData)
        }
    }

    /// "Reset points" in `MaskReviewSheet`: drops every point the user
    /// added and falls back to just the box's own automatic center-point
    /// anchor, then re-runs the decoder once — a real reset, not merely
    /// clearing state, so the mask on screen always matches exactly what
    /// "Use mask" would save.
    func resetRefinementPoints() {
        guard let candidate = session.active, let sourceData, !isRefiningMask else { return }
        let anchor = EdgeSAMGeometry.centerPoint(of: candidate.region).map { [$0] } ?? []
        session.setRefinementPoints(anchor)
        let region = maskReviewRegion
        maskProposalTask?.cancel()
        isRefiningMask = true
        maskProposalTask = Task { @MainActor in
            defer { isRefiningMask = false }
            await applyDecodeResult(for: region, points: anchor, source: sourceData)
        }
    }

    /// Runs one decode and applies its outcome — shared by the initial
    /// proposal and every refinement re-decode, so all three follow exactly
    /// the same silent-vs-explicit failure rule (Goal C).
    ///
    /// A cancelled or superseded attempt (this candidate's box changed, a
    /// newer refinement was issued before this one returned) leaves
    /// whatever is already on screen untouched, silently — nothing the user
    /// is currently looking at was invalidated by it. `.modelUnavailable`
    /// is silent for the same reason `startMaskProposal` never surfaces it:
    /// "no segmenter configured" must behave exactly as if EdgeSAM did not
    /// exist, not as a user-visible error. Every other failure — the
    /// decoder itself rejecting this prompt, mask conversion failing — is
    /// shown via `segmentationFailureMessage`, because the user just took
    /// an explicit action (drew a box, tapped a point) that genuinely did
    /// not work; per Goal C, that must never be silently swallowed into
    /// what looks like the AI feature simply isn't there.
    @MainActor
    private func applyDecodeResult(
        for region: NormalizedCropRect, points: [EdgeSAMGeometry.PromptPoint], source imageData: Data
    ) async {
        do {
            let result = try await resolvedEmbeddingSession().proposeMask(for: region, source: imageData, points: points)
            guard !Task.isCancelled else { return }
            maskProposal = result
            maskReviewRegion = region
        } catch is CancellationError {
        } catch SegmentationError.cancelled, SegmentationError.stalePrompt, SegmentationError.modelUnavailable {
        } catch {
            segmentationFailureMessage = (error as? LocalizedError)?.errorDescription
                ?? "RIG could not propose a garment mask for that area."
        }
    }

    /// The user tapped "Use mask" in `MaskReviewSheet`: record it against the
    /// active candidate and run it straight through the ordinary import
    /// pipeline, exactly as `RawGarmentCropPreview`'s "Use this crop" does
    /// for the manual path.
    func acceptMask(_ mask: SegmentationMaskResult) {
        session.proposeMask(mask)
        maskProposal = nil
        cancelMaskProposal()
        Task { await processDraft() }
    }

    /// Imports the reviewed bytes: the plain rectangular crop, or — when the
    /// active candidate carries an accepted AI mask — that mask's own
    /// already-segmented cutout, preserved end to end by
    /// `GarmentImportService`'s `precomputedCutout` parameter.
    @MainActor
    func processDraft() async {
        guard !isProcessing, let cropped = rawCropData, let candidate = session.active else { return }
        isProcessing = true
        defer {
            isProcessing = false
            rawCropData = nil
        }
        do {
            let result = try await services.importService.importImage(
                cropped,
                garmentID: candidate.id,
                precomputedCutout: candidate.proposedMask?.cutoutData
            )
            session.markReady(result)
        } catch {
            let described = (error as? LocalizedError)?.errorDescription
            session.markFailed(described ?? "That garment could not be processed. Crop again or discard it.")
        }
    }
}
