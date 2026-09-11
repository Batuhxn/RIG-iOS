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
struct OutfitPhotoSessionView: View {
    let source: PhotosPickerItem

    @Environment(\.modelContext) private var modelContext
    @Environment(\.rigServices) private var services
    @Environment(\.dismiss) private var dismiss

    /// The crop authority: one bounded copy of the photograph, held for the
    /// life of the session so every crop comes from the same pixels.
    @State private var sourceData: Data?
    /// A smaller decoded copy, and the only thing ever drawn. Rectangles are
    /// fractions, so the small copy and the big one always agree.
    @State private var displayImage: UIImage?
    @State private var sourcePixelSize: CGSize = .zero
    @State private var rawCropData: Data?
    @State private var session = OutfitPhotoSession()
    @State private var draftRegion: NormalizedCropRect = .centeredDefault
    @State private var fields = GarmentMetadataFields()
    @State private var isProcessing = false
    @State private var loadFailure: String?

    private static let displayMaxDimension: CGFloat = 1000

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
        }
    }

    // MARK: - Screens

    @ViewBuilder
    private func content(_ image: UIImage) -> some View {
        if let candidate = session.active {
            if let result = candidate.importResult {
                reviewScreen(result)
            } else if let message = candidate.failureMessage {
                candidateFailureScreen(message)
            } else if isProcessing {
                processingScreen
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

    private var loadingScreen: some View {
        VStack(spacing: RIGTheme.Spacing.m) {
            ProgressView()
            Text("Opening your photo…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var processingScreen: some View {
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

    private func sourceScreen(_ image: UIImage) -> some View {
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

    private func croppingScreen(_ image: UIImage) -> some View {
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

    private func reviewScreen(_ result: GarmentImportResult) -> some View {
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

    private func candidateFailureScreen(_ message: String) -> some View {
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

    private func sourceFailureScreen(_ message: String) -> some View {
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
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(session.savedCount > 0 ? "Done" : "Cancel", action: finish)
        }
        if session.active?.importResult != nil {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(!fields.isValid)
            }
        }
    }

    private var savedSummary: String {
        switch session.savedCount {
        case 0: return "Nothing saved from this photo yet."
        case 1: return "1 garment saved from this photo."
        default: return "\(session.savedCount) garments saved from this photo."
        }
    }

    // MARK: - Work

    /// Loads the photograph once, bounds it once, and releases the original
    /// bytes. Nothing else in the session ever touches a full-resolution image.
    @MainActor
    private func loadSource() async {
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

    private func beginCandidate() {
        rawCropData = nil
        draftRegion = .centeredDefault
        fields = GarmentMetadataFields()
        session.beginCandidate(region: draftRegion)
    }

    /// Export once. Review these exact bytes before any background removal or
    /// file writes; the confirmation action imports the same bytes.
    private func previewDraft() {
        guard let sourceData, session.active != nil else { return }
        session.updateRegion(draftRegion)
        guard let cropped = GarmentImageCropping.croppedData(from: sourceData, region: draftRegion) else {
            session.markFailed("That area could not be cropped. Try a slightly bigger box.")
            return
        }
        rawCropData = cropped
    }

    @MainActor
    private func processDraft() async {
        guard !isProcessing, let cropped = rawCropData, let candidate = session.active else { return }
        isProcessing = true
        defer {
            isProcessing = false
            rawCropData = nil
        }
        do {
            let result = try await services.importService.importImage(cropped, garmentID: candidate.id)
            session.markReady(result)
        } catch {
            let described = (error as? LocalizedError)?.errorDescription
            session.markFailed(described ?? "That garment could not be processed. Crop again or discard it.")
        }
    }

    private func save() {
        guard let candidate = session.active,
              let result = candidate.importResult,
              fields.isValid else { return }

        let garment = ClothingItem(
            id: result.garmentID,
            displayName: fields.trimmedName,
            subtype: fields.subtype.trimmingCharacters(in: .whitespacesAndNewlines),
            category: fields.category,
            primaryColor: fields.colorFamily,
            seasons: fields.seasons,
            isFavorite: fields.isFavorite,
            notes: fields.notes,
            originalImageRelativePath: result.originalRelativePath,
            cutoutImageRelativePath: result.cutoutRelativePath,
            thumbnailRelativePath: result.thumbnailRelativePath,
            isBackgroundRemoved: result.isBackgroundRemoved
        )
        modelContext.insert(garment)

        do {
            try modelContext.save()
        } catch {
            // Neither the row nor its files are left behind, and the session
            // carries on with the photograph still open.
            modelContext.delete(garment)
            try? services.imageStore.removeAll(for: result.garmentID)
            session.markFailed("That garment could not be saved to this device.")
            return
        }

        session.markSaved()
        fields = GarmentMetadataFields()
    }

    /// Back to the rectangle. The previous attempt's files go now; the
    /// identifier is reused, so a second attempt overwrites rather than orphans.
    private func recrop() {
        rawCropData = nil
        if let candidate = session.active {
            try? services.imageStore.removeAll(for: candidate.id)
            draftRegion = candidate.region
        }
        session.recrop()
    }

    private func discard() {
        rawCropData = nil
        if let candidate = session.active {
            try? services.imageStore.removeAll(for: candidate.id)
        }
        session.discardActive()
        fields = GarmentMetadataFields()
    }

    /// Saved garments stay. Everything else leaves no files behind.
    private func finish() {
        rawCropData = nil
        for id in session.garmentIDsPendingCleanup {
            try? services.imageStore.removeAll(for: id)
        }
        dismiss()
    }
}
