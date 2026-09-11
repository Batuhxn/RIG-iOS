import PhotosUI
import SwiftData
import SwiftUI
import UIKit

/// One outfit photograph, taken apart one garment at a time.
///
/// This exists because the foreground pipeline is honest but literal: handed a
/// mirror selfie it isolates the person, and the user ends up with one garment
/// called "me". So an outfit photo gets its own sitting — the source stays on
/// screen, the user draws a box round one thing at a time, and each box goes
/// through the ordinary garment pipeline as if it had been photographed alone.
///
/// **v0.4 Slice 2** adds two optional detours inside that same sitting, both
/// off by construction unless their model actually answers:
///
/// - after a box is drawn, EdgeSAM may propose a mask for what is inside it
///   (`MaskReviewSheet`), with the plain rectangular crop always one tap away
///   — see `OutfitPhotoSessionView+Segmentation.swift`;
/// - before a garment is saved as new, RIG may find the wardrobe already
///   looks like it owns something similar (`DuplicateComparisonSheet`), and
///   asks rather than guessing — see `OutfitPhotoSessionView+Duplicates.swift`.
///
/// **v0.4 Slice 2.1** makes that first detour interactive — the user can add
/// positive/negative points to refine a proposed mask before accepting it —
/// and fixes it to actually run for every garment in a sitting, not just the
/// first; see the doc comments in `OutfitPhotoSessionView+Segmentation.swift`.
///
/// Neither detour changes what already worked: with no segmenter and no
/// similarity match, this is exactly the v0.4 Slice 1 flow.
///
/// This type's implementation is split across several files purely to stay
/// under the static audit's per-file line cap — it is one type throughout,
/// and every stored property below is touched from more than one of them.
/// Swift's `private` is file-scoped even for extensions of the same type, so
/// properties and cross-file members are left at their default (internal)
/// access rather than exposed to the rest of the module some other way.
/// `OutfitPhotoSessionView+Screens.swift` holds the individual screen bodies
/// `content(_:)` dispatches between.
struct OutfitPhotoSessionView: View {
    let source: PhotosPickerItem

    @Environment(\.modelContext) var modelContext
    @Environment(\.rigServices) var services
    @Environment(\.dismiss) var dismiss

    @Query var wardrobeItems: [ClothingItem]

    /// The crop authority: one bounded copy of the photograph, held for the
    /// life of the session so every crop comes from the same pixels. It is
    /// also the one image EdgeSAM's encoder ever sees — see
    /// `OutfitEmbeddingSession`.
    @State var sourceData: Data?
    /// A smaller decoded copy, and the only thing ever drawn. Rectangles are
    /// fractions, so the small copy and the big one always agree.
    @State var displayImage: UIImage?
    @State var sourcePixelSize: CGSize = .zero
    @State var rawCropData: Data?
    @State var session = OutfitPhotoSession()
    @State var draftRegion: NormalizedCropRect = .centeredDefault
    @State var fields = GarmentMetadataFields()
    @State var isProcessing = false
    @State var loadFailure: String?

    /// One embedding session for the whole sitting — created once the first
    /// candidate asks for a mask, reused by every candidate after it, and
    /// invalidated only when this view goes away. See "Session embedding
    /// reuse" in the v0.4 Slice 2 report.
    @State var embeddingSession: OutfitEmbeddingSession?
    @State var maskProposalTask: Task<Void, Never>?
    @State var isProposingMask = false
    @State var maskProposal: SegmentationMaskResult?
    /// The region `maskProposal` was actually computed for — needed to place
    /// the overlay correctly even if `draftRegion` has since moved on.
    @State var maskReviewRegion: NormalizedCropRect = .centeredDefault
    /// True while a refinement re-decode (an added point, not the initial
    /// proposal) is in flight — `MaskReviewSheet` stays on screen throughout,
    /// unlike `isProposingMask`. See "v0.4 Slice 2.1" in
    /// `OutfitPhotoSessionView+Segmentation.swift`.
    @State var isRefiningMask = false
    /// Set only when EdgeSAM was available and actually attempted a
    /// proposal that then failed — never for "no segmenter configured" or a
    /// superseded/cancelled attempt, both of which stay silent by design.
    /// Shown as an explicit notice on the manual-crop fallback screen so a
    /// failure never just looks like the AI feature silently isn't there
    /// (the real-device finding this exists to address) — see Goal C in the
    /// v0.4 Slice 2.1 report.
    @State var segmentationFailureMessage: String?
    #if DEBUG
    @State var showingEdgeSAMDiagnostics = false
    #endif

    @State var isCheckingForDuplicates = false
    @State var duplicateReview: DuplicateReviewState?
    @State var duplicateCandidateImageData: Data?

    static let displayMaxDimension: CGFloat = 1000

    var body: some View {
        NavigationStack {
            Group {
                if let loadFailure {
                    sourceFailureScreen(loadFailure)
                } else if let displayImage {
                    content(displayImage)
                } else {
                    loadingScreen
                }
            }
            .background(RIGTheme.pageBackground)
            .navigationTitle("Outfit photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            #if DEBUG
            .sheet(isPresented: $showingEdgeSAMDiagnostics) {
                EdgeSAMDiagnosticsView()
            }
            #endif
            .task { await loadSource() }
            .sheet(isPresented: duplicateSheetBinding) {
                duplicateSheet
            }
        }
    }

    // MARK: - Screens

    @ViewBuilder
    func content(_ image: UIImage) -> some View {
        if let candidate = session.active {
            if let result = candidate.importResult {
                reviewScreen(result)
            } else if let message = candidate.failureMessage {
                candidateFailureScreen(message)
            } else if isProcessing {
                processingScreen
            } else if isProposingMask {
                MaskProposingScreen()
            } else if let maskProposal, let rawCropData, let preview = UIImage(data: rawCropData) {
                MaskReviewSheet(
                    rawCropImage: preview,
                    cropRegion: maskReviewRegion,
                    mask: maskProposal,
                    refinementPoints: session.active?.refinementPoints ?? [],
                    isRefining: isRefiningMask,
                    onUseMask: { acceptMask(maskProposal) },
                    onAdjustSelection: {
                        self.rawCropData = nil
                        self.maskProposal = nil
                        cancelMaskProposal()
                    },
                    onUseRectangularCrop: {
                        self.maskProposal = nil
                        cancelMaskProposal()
                    },
                    onSkip: discard,
                    onAddPoint: { point in refineMaskProposal(adding: point) },
                    onResetPoints: resetRefinementPoints
                )
            } else if let rawCropData, let preview = UIImage(data: rawCropData) {
                RawGarmentCropPreview(
                    image: preview,
                    notice: segmentationFailureMessage,
                    onAdjust: { self.rawCropData = nil },
                    onUse: { Task { await processDraft() } }
                )
            } else {
                croppingScreen(image)
            }
        } else {
            sourceScreen(image)
        }
    }

    // Screen bodies (loadingScreen, processingScreen, sourceScreen,
    // croppingScreen, reviewScreen, candidateFailureScreen,
    // sourceFailureScreen), toolbarContent, and savedSummary all live in
    // `OutfitPhotoSessionView+Screens.swift` — split out purely for the
    // static audit's per-file line cap.

    // MARK: - Work

    /// Loads the photograph once, bounds it once, and releases the original
    /// bytes. Nothing else in the session ever touches a full-resolution image.
    @MainActor
    func loadSource() async {
        guard sourceData == nil, loadFailure == nil else { return }
        do {
            guard let raw = try await source.loadTransferable(type: Data.self) else {
                loadFailure = "Try picking it again, or choose another photo."
                return
            }
            guard let bounded = GarmentImageProcessing.jpegData(
                from: raw,
                maxDimension: GarmentImageProcessing.originalMaxDimension
            ) else {
                loadFailure = "RIG could not read that image."
                return
            }
            guard let prepared = UIImage(data: bounded), let raster = prepared.cgImage else {
                loadFailure = "RIG could not read that image."
                return
            }
            sourceData = bounded
            sourcePixelSize = CGSize(width: raster.width, height: raster.height)
            displayImage = GarmentImageProcessing.resized(prepared, maxDimension: Self.displayMaxDimension)
        } catch {
            loadFailure = "Try picking it again, or choose another photo."
        }
    }

    func beginCandidate() {
        rawCropData = nil
        maskProposal = nil
        segmentationFailureMessage = nil
        cancelMaskProposal()
        draftRegion = .centeredDefault
        fields = GarmentMetadataFields()
        session.beginCandidate(region: draftRegion)
    }

    /// Export once. Review these exact bytes before any background removal or
    /// file writes; the confirmation action imports the same bytes. Also
    /// kicks off an AI mask proposal for the same region — see
    /// `OutfitPhotoSessionView+Segmentation.swift` — which is purely
    /// additive: `rawCropData` alone is already everything the manual flow
    /// needs.
    func previewDraft() {
        #if DEBUG
        EdgeSAMDiagnostics().event("cropConfirmation", ["crop": "\(draftRegion)", "sourcePixelSize": "\(sourcePixelSize)"])
        #endif
        guard let sourceData, session.active != nil else { return }
        session.updateRegion(draftRegion)
        guard let cropped = GarmentImageCropping.croppedData(from: sourceData, region: draftRegion) else {
            session.markFailed("That area could not be cropped. Try a slightly bigger box.")
            return
        }
        rawCropData = cropped
        maskProposal = nil
        // Goal B: seed the initial prompt with the box's own center as a
        // positive point, rather than the box alone — the real-device
        // finding this addresses is a box-only prompt bleeding into
        // unrelated regions (leg/chest skin around a sweater). `updateRegion`
        // just above already cleared any refinement points left over from a
        // previous box on this same candidate.
        let anchor = EdgeSAMGeometry.centerPoint(of: draftRegion).map { [$0] } ?? []
        session.setRefinementPoints(anchor)
        startMaskProposal(for: draftRegion, source: sourceData)
    }

    /// Back to the rectangle. The previous attempt's files go now; the
    /// identifier is reused, so a second attempt overwrites rather than orphans.
    func recrop() {
        rawCropData = nil
        maskProposal = nil
        segmentationFailureMessage = nil
        cancelMaskProposal()
        if let candidate = session.active {
            try? services.imageStore.removeAll(for: candidate.id)
            draftRegion = candidate.region
        }
        session.recrop()
    }

    func discard() {
        rawCropData = nil
        maskProposal = nil
        segmentationFailureMessage = nil
        cancelMaskProposal()
        if let candidate = session.active {
            try? services.imageStore.removeAll(for: candidate.id)
        }
        session.discardActive()
        fields = GarmentMetadataFields()
    }

    /// Saved and linked garments stay. Everything else leaves no files
    /// behind, and any cached AI embedding for this photograph goes with it.
    func finish() {
        rawCropData = nil
        maskProposal = nil
        cancelMaskProposal()
        for id in session.garmentIDsPendingCleanup {
            try? services.imageStore.removeAll(for: id)
        }
        if let embeddingSession {
            Task { await embeddingSession.invalidate() }
        }
        dismiss()
    }
}
