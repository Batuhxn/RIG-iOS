import PhotosUI
import SwiftData
import SwiftUI

/// Photograph or pick, crop if you want to, process locally, review, describe,
/// save.
///
/// Two rules shape this flow, and they pull in opposite directions:
///
/// **A failed cutout never blocks a save.** If Vision cannot isolate the
/// garment the user is told plainly and carries on with the original
/// photograph. The design's failure screen honours this — "continue with the
/// original" is always one of the two ways out of it.
///
/// **Crop is optional and non-destructive.** The source bytes are held
/// untouched for the life of the flow. Cropping produces *new* bytes; skipping
/// passes the source through. Everything downstream — `GarmentImportService`
/// included — receives one `Data` and cannot tell which it got, which is
/// precisely why background removal operates on the crop without knowing that
/// cropping exists.
struct AddGarmentFlow: View {
    enum Step: Equatable {
        case chooseSource
        case crop
        case processing
        case review
        case removalFailure
        case details
        case done
    }

    /// A photograph the unified import flow already collected. When present the
    /// source step is skipped entirely — the user has answered that question
    /// once already and must not be asked it twice.
    var initialSelection: PhotosPickerItem? = nil
    /// Opens the camera straight away. Cancelling falls back to the ordinary
    /// source step rather than to a dead end.
    var startsWithCamera: Bool = false

    @Environment(\.modelContext) var modelContext
    @Environment(\.rigServices) var services
    @Environment(\.dismiss) var dismiss

    /// Everything already in the wardrobe, for the duplicate comparison. The
    /// query lives here rather than inside the matcher for the same reason
    /// `WardrobeSimilarityCandidateItem` is not a `ClothingItem`: the
    /// similarity layer must stay free of SwiftData.
    @Query(sort: [SortDescriptor(\ClothingItem.createdAt, order: .reverse)]) var wardrobeItems: [ClothingItem]

    @State var step: Step = .chooseSource
    @State private var photoSelection: PhotosPickerItem?
    @State private var isPresentingCamera = false

    /// The photograph as it arrived. Never mutated, so "crop again" always
    /// starts from the whole frame rather than from a previous crop.
    @State private var sourceImageData: Data?
    /// The bytes the user chose to process: the crop, or the source.
    @State private var didCrop = false

    @State var importResult: GarmentImportResult?
    @State private var isProcessingFinished = false
    @State var fields = GarmentMetadataFields()
    @State var errorMessage: String?
    @State private var didBootstrap = false

    @State var duplicateReview: DuplicateReviewState?
    @State var duplicateCandidateImageData: Data?
    @State var isCheckingForDuplicates = false

    var body: some View {
        ZStack {
            RIGTheme.pageBackground.ignoresSafeArea()

            Group {
                switch step {
                case .chooseSource: sourceStep
                case .crop: cropStep
                case .processing: processingStep
                case .review: reviewStep
                case .removalFailure: removalFailureStep
                case .details: detailsStep
                case .done: doneStep
                }
            }
            .transition(.opacity)
        }
        .animation(NocturneMotion.screen, value: step)
        .sheet(isPresented: $isPresentingCamera) {
            CameraPicker(
                onCapture: { data in
                    // The hop is explicit rather than inherited: these
                    // callbacks arrive from a UIKit delegate, and everything
                    // they touch here is main-actor state.
                    Task { @MainActor in
                        isPresentingCamera = false
                        accept(data)
                    }
                },
                onCancel: {
                    Task { @MainActor in isPresentingCamera = false }
                }
            )
            .ignoresSafeArea()
        }
        .onChange(of: photoSelection) { _, newValue in
            guard let newValue else { return }
            Task { @MainActor in await loadFromPhotos(newValue) }
        }
        .task {
            guard !didBootstrap else { return }
            didBootstrap = true
            if let initialSelection {
                await loadFromPhotos(initialSelection)
            } else if startsWithCamera, CameraPicker.isAvailable {
                isPresentingCamera = true
            }
        }
        // Attached outside the step switch, and deliberately not stacked on the
        // same view as the camera sheet: two sheet modifiers on one view is a
        // well-known way to lose one of them.
        .sheet(isPresented: duplicateSheetBinding) { duplicateSheet }
    }

    // MARK: - Steps

    private var sourceStep: some View {
        VStack(spacing: 0) {
            RIGSheetHeader(title: "Parça ekle", leadingTitle: "İptal", leadingAction: cancel)

            Spacer(minLength: 0)

            VStack(spacing: RIGTheme.Spacing.l) {
                Image(systemName: "tshirt")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(RIGTheme.text(45))
                    .accessibilityHidden(true)

                Text("Sahip olduğun bir parçayı çek")
                    .font(.system(size: 20, weight: .medium))
                Text("Sade bir arka plan en iyi sonucu verir. Her şey bu cihazda olur — hiçbir şey yüklenmez.")
                    .font(.system(size: 13))
                    .foregroundStyle(RIGTheme.text(55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, RIGTheme.Spacing.xl)

                if let errorMessage {
                    RIGErrorBanner(message: errorMessage) {
                        self.errorMessage = nil
                    }
                    .padding(.horizontal, RIGTheme.Spacing.xl)
                }
            }

            Spacer(minLength: 0)

            VStack(spacing: RIGTheme.Spacing.s) {
                // No `photoLibrary:` argument on purpose. That overload gives the
                // picker in-process access to the library, which requires photo
                // library authorisation and an NSPhotoLibraryUsageDescription.
                // RIG only ever asks for the chosen image's bytes, so the
                // out-of-process picker is both sufficient and permission-free.
                PhotosPicker(selection: $photoSelection, matching: .images) {
                    Text("Fotoğraflardan seç")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(RIGTheme.accent)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .overlay(
                            RoundedRectangle(cornerRadius: RIGTheme.Radius.large, style: .continuous)
                                .strokeBorder(RIGTheme.accent, lineWidth: 1)
                        )
                }

                if CameraPicker.isAvailable {
                    Button("Fotoğraf çek") {
                        isPresentingCamera = true
                    }
                    .buttonStyle(RIGSecondaryButtonStyle())
                } else {
                    Text("Bu cihazda kamera yok.")
                        .font(.system(size: 12))
                        .foregroundStyle(RIGTheme.text(55))
                }
            }
            .padding(.horizontal, RIGTheme.Spacing.xl)
            .padding(.bottom, RIGTheme.Spacing.l)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var cropStep: some View {
        if let sourceImageData {
            CropStep(
                imageData: sourceImageData,
                onBack: { step = .chooseSource },
                onContinue: { cropped in
                    Task { @MainActor in
                        await process(cropped ?? sourceImageData, didCrop: cropped != nil)
                    }
                }
            )
        } else {
            // Unreachable in practice; a blank step is still better than a
            // crash if it ever is reached.
            Color.clear.onAppear { step = .chooseSource }
        }
    }

    private var processingStep: some View {
        ProcessingStep(
            didCrop: didCrop,
            onCancel: cancel,
            isFinishing: isProcessingFinished
        )
    }

    @ViewBuilder
    private var reviewStep: some View {
        if let importResult {
            ReviewStep(
                result: importResult,
                didCrop: didCrop,
                onBack: { step = .crop },
                onRetry: retryProcessing,
                onContinue: { step = .details }
            )
        }
    }

    @ViewBuilder
    private var removalFailureStep: some View {
        RemovalFailureStep(
            message: importResult?.backgroundRemovalMessage
                ?? "Fotoğrafın arka planı çok karmaşık olabilir. Kırparak tekrar deneyebilir veya fotoğrafı olduğu gibi ekleyebilirsin.",
            onCropAndRetry: { step = .crop },
            onContinueWithOriginal: { step = .details }
        )
    }

    @ViewBuilder
    private var detailsStep: some View {
        if let importResult {
            GarmentDetailsStep(
                fields: $fields,
                previewPath: importResult.cutoutRelativePath ?? importResult.originalRelativePath,
                isBackgroundRemoved: importResult.isBackgroundRemoved,
                isSaving: isCheckingForDuplicates,
                errorMessage: errorMessage,
                onDismissError: { errorMessage = nil },
                onBack: { step = importResult.isBackgroundRemoved ? .review : .removalFailure },
                onSave: beginSave
            )
        }
    }

    @ViewBuilder
    private var doneStep: some View {
        SuccessStep(
            garmentName: fields.trimmedName,
            categoryName: fields.category.displayName,
            thumbnailPath: importResult?.thumbnailRelativePath ?? importResult?.cutoutRelativePath,
            onDone: { dismiss() },
            onAddAnother: startAnother
        )
    }

    // MARK: - Actions

    @MainActor
    private func loadFromPhotos(_ selection: PhotosPickerItem) async {
        do {
            guard let data = try await selection.loadTransferable(type: Data.self) else {
                fail("Bu fotoğraf yüklenemedi. Başka bir tane dene.")
                return
            }
            accept(data)
        } catch {
            fail("Bu fotoğraf yüklenemedi. Başka bir tane dene.")
        }
    }

    /// A photograph has arrived. The crop step comes next — it is offered, not
    /// imposed, and it is the only place the source bytes are read.
    @MainActor
    private func accept(_ data: Data) {
        sourceImageData = data
        errorMessage = nil
        step = .crop
    }

    @MainActor
    private func process(_ data: Data, didCrop: Bool) async {
        // A retry writes a fresh set of files, so the previous attempt's files
        // are removed first rather than left behind as orphans.
        discardCandidateFiles()
        importResult = nil

        self.didCrop = didCrop
        isProcessingFinished = false
        step = .processing

        do {
            let result = try await services.importService.importImage(data)
            importResult = result
            isProcessingFinished = true
            // Lets the ring finish its travel to 100 before the step changes.
            try? await Task.sleep(nanoseconds: 450_000_000)
            step = result.isBackgroundRemoved ? .review : .removalFailure
        } catch {
            isProcessingFinished = true
            fail((error as? LocalizedError)?.errorDescription ?? "Bu fotoğraf işlenemedi.")
        }
    }

    private func retryProcessing() {
        guard let sourceImageData else { return }
        Task { @MainActor in
            await process(sourceImageData, didCrop: false)
        }
    }

    /// "Add another": the saved garment's files belong to the wardrobe now, so
    /// this must not discard them — it only clears the flow's own state.
    @MainActor
    private func startAnother() {
        importResult = nil
        sourceImageData = nil
        didCrop = false
        fields = GarmentMetadataFields()
        errorMessage = nil
        photoSelection = nil
        step = .chooseSource
    }

    private func fail(_ message: String) {
        errorMessage = message
        photoSelection = nil
        step = .chooseSource
    }

    private func cancel() {
        discardCandidateFiles()
        dismiss()
    }

    /// Abandoning the flow must not leave written files behind.
    func discardCandidateFiles() {
        if let importResult {
            try? services.imageStore.removeAll(for: importResult.garmentID)
        }
    }
}

#Preview {
    AddGarmentFlow()
        .modelContainer(PreviewData.container(populated: false))
        .environment(\.rigServices, .preview())
}
