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
/// Neither detour changes what already worked: with no segmenter and no
/// similarity match, this is exactly the v0.4 Slice 1 flow.
///
/// This type's implementation is split across three files purely to stay
/// under the static audit's per-file line cap — it is one type throughout,
/// and every stored property below is touched from all three. Swift's
/// `private` is file-scoped even for extensions of the same type, so
/// properties and cross-file members are left at their default (internal)
/// access rather than exposed to the rest of the module some other way.
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
                    onSkip: discard
                )
            } else if let rawCropData, let preview = UIImage(data: rawCropData) {
                RawGarmentCropPreview(image: preview, onAdjust: { self.rawCropData = nil }) {
                    Task { await processDraft() }
                }
            } else {
                croppingScreen(image)
            }
        } else {
            sourceScreen(image)
        }
    }

    var loadingScreen: some View {
        VStack(spacing: RIGTheme.Spacing.m) {
            ProgressView()
            Text("Opening your photo…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var processingScreen: some View {
        VStack(spacing: RIGTheme.Spacing.m) {
            ProgressView()
            Text("Separating the garment…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Processing the cropped garment")
    }

    func sourceScreen(_ image: UIImage) -> some View {
        VStack(spacing: RIGTheme.Spacing.m) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: RIGTheme.Radius.card, style: .continuous))
                .padding(.horizontal, RIGTheme.Spacing.m)
                .accessibilityHidden(true)

            Text(savedSummary)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(spacing: RIGTheme.Spacing.s) {
                Button("Add garment", action: beginCandidate)
                    .buttonStyle(RIGPrimaryButtonStyle())
                Button("Finish", action: finish)
                    .buttonStyle(RIGSecondaryButtonStyle())
            }
            .padding(.horizontal, RIGTheme.Spacing.m)
            .padding(.bottom, RIGTheme.Spacing.l)
        }
    }

    func croppingScreen(_ image: UIImage) -> some View {
        VStack(spacing: RIGTheme.Spacing.s) {
            GarmentCropView(image: image, sourcePixelSize: sourcePixelSize, region: $draftRegion)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, RIGTheme.Spacing.s)

            Text("Drag the box over one garment.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            VStack(spacing: RIGTheme.Spacing.s) {
                Button("Preview crop", action: previewDraft)
                .buttonStyle(RIGPrimaryButtonStyle())
                .disabled(!draftRegion.isUsable)

                Button("Cancel", action: discard)
                    .buttonStyle(RIGSecondaryButtonStyle())
            }
            .padding(.horizontal, RIGTheme.Spacing.m)
            .padding(.bottom, RIGTheme.Spacing.l)
        }
    }

    func reviewScreen(_ result: GarmentImportResult) -> some View {
        Form {
            Section {
                GarmentImageView(
                    relativePath: result.cutoutRelativePath ?? result.originalRelativePath,
                    symbolName: fields.category.symbolName
                )
                .frame(height: 200)
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)

                if let message = result.backgroundRemovalMessage {
                    Text("\(message) The cropped photo will be used instead.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if isCheckingForDuplicates {
                    HStack(spacing: RIGTheme.Spacing.s) {
                        ProgressView().controlSize(.small)
                        Text("Checking your wardrobe for anything similar…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            GarmentMetadataForm(fields: $fields)

            Section {
                Button("Crop again", action: recrop)
                Button("Discard this garment", role: .destructive, action: discard)
            } footer: {
                Text("Garments you have already saved stay in your wardrobe.")
            }
        }
    }

    func candidateFailureScreen(_ message: String) -> some View {
        VStack(spacing: RIGTheme.Spacing.m) {
            Spacer(minLength: 0)
            RIGErrorBanner(message: message)
                .padding(.horizontal, RIGTheme.Spacing.m)
            Text("The rest of this photo is untouched.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            VStack(spacing: RIGTheme.Spacing.s) {
                Button("Crop again", action: recrop)
                    .buttonStyle(RIGPrimaryButtonStyle())
                Button("Discard this garment", action: discard)
                    .buttonStyle(RIGSecondaryButtonStyle())
            }
            .padding(.horizontal, RIGTheme.Spacing.m)
            .padding(.bottom, RIGTheme.Spacing.l)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func sourceFailureScreen(_ message: String) -> some View {
        RIGEmptyState(
            symbol: "exclamationmark.triangle",
            title: "That photo could not be opened",
            message: message,
            actionTitle: "Close",
            action: finish
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(session.resolvedCount > 0 ? "Done" : "Cancel", action: finish)
        }
        if session.active?.importResult != nil {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: beginSave)
                    .disabled(!fields.isValid || isCheckingForDuplicates)
            }
        }
    }

    var savedSummary: String {
        switch session.resolvedCount {
        case 0:
            return "Nothing saved from this photo yet."
        default:
            if session.linkedCount == 0 {
                return session.savedCount == 1
                    ? "1 garment saved from this photo."
                    : "\(session.savedCount) garments saved from this photo."
            }
            if session.savedCount == 0 {
                return session.linkedCount == 1
                    ? "1 garment linked to your wardrobe from this photo."
                    : "\(session.linkedCount) garments linked to your wardrobe from this photo."
            }
            return "\(session.savedCount) new, \(session.linkedCount) linked to your wardrobe, from this photo."
        }
    }

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
        guard let sourceData, session.active != nil else { return }
        session.updateRegion(draftRegion)
        guard let cropped = GarmentImageCropping.croppedData(from: sourceData, region: draftRegion) else {
            session.markFailed("That area could not be cropped. Try a slightly bigger box.")
            return
        }
        rawCropData = cropped
        maskProposal = nil
        startMaskProposal(for: draftRegion, source: sourceData)
    }

    /// Back to the rectangle. The previous attempt's files go now; the
    /// identifier is reused, so a second attempt overwrites rather than orphans.
    func recrop() {
        rawCropData = nil
        maskProposal = nil
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
