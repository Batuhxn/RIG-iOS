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

    /// Asks the segmenter for a mask over `region`. A no-op, silently, when
    /// no segmenter is available — the plain rectangular crop from
    /// `previewDraft()` already stands on its own, so this is purely
    /// additive.
    func startMaskProposal(for region: NormalizedCropRect, source imageData: Data) {
        cancelMaskProposal()
        let maskSession = resolvedEmbeddingSession()
        isProposingMask = true
        maskProposalTask = Task { @MainActor in
            defer { isProposingMask = false }
            guard await maskSession.isAvailable else { return }
            do {
                let result = try await maskSession.proposeMask(for: region, source: imageData)
                guard !Task.isCancelled else { return }
                maskProposal = result
                maskReviewRegion = region
            } catch {
                // Cancelled, stale, or the model failed on this attempt: the
                // honest fallback is exactly what v0.4 Slice 1 already did —
                // the rectangular crop stands on its own, silently, since
                // nothing the user asked for has failed.
                maskProposal = nil
            }
        }
    }

    func cancelMaskProposal() {
        maskProposalTask?.cancel()
        maskProposalTask = nil
        isProposingMask = false
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
