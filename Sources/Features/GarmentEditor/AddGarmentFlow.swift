import PhotosUI
import SwiftData
import SwiftUI

/// Photograph or pick, process locally, review, describe, save.
///
/// The one rule that shapes this whole flow: **a failed cutout never blocks a
/// save.** If Vision cannot isolate the garment the user is told plainly and
/// carries on with the original photograph.
struct AddGarmentFlow: View {
    enum Step: Equatable {
        case chooseSource
        case processing
        case review
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
    @State var importResult: GarmentImportResult?
    @State var fields = GarmentMetadataFields()
    @State var errorMessage: String?
    @State private var didBootstrap = false

    @State var duplicateReview: DuplicateReviewState?
    @State var duplicateCandidateImageData: Data?
    @State var isCheckingForDuplicates = false

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .chooseSource:
                    sourceStep
                case .processing:
                    processingStep
                case .review:
                    reviewStep
                }
            }
            .background(RIGTheme.pageBackground)
            .navigationTitle("Add a garment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: cancel)
                }
                if step == .review {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save", action: beginSave)
                            .disabled(!fields.isValid || isCheckingForDuplicates)
                    }
                }
            }
            .sheet(isPresented: $isPresentingCamera) {
                CameraPicker(
                    onCapture: { data in
                        // The hop is explicit rather than inherited: these
                        // callbacks arrive from a UIKit delegate, and everything
                        // they touch here is main-actor state.
                        Task { @MainActor in
                            isPresentingCamera = false
                            await process(data)
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
        }
        // Attached outside the navigation stack, and deliberately not stacked
        // on the same view as the camera sheet: two sheet modifiers on one
        // view is a well-known way to lose one of them.
        .sheet(isPresented: duplicateSheetBinding) { duplicateSheet }
    }

    // MARK: - Steps

    private var sourceStep: some View {
        VStack(spacing: RIGTheme.Spacing.m) {
            Spacer(minLength: 0)

            Image(systemName: "tshirt")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("Photograph something you own")
                .font(.headline)
            Text("A plain background works best. Everything happens on this device — nothing is uploaded.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, RIGTheme.Spacing.l)

            if let errorMessage {
                RIGErrorBanner(message: errorMessage) {
                    self.errorMessage = nil
                }
                .padding(.horizontal, RIGTheme.Spacing.m)
            }

            Spacer(minLength: 0)

            VStack(spacing: RIGTheme.Spacing.s) {
                // No `photoLibrary:` argument on purpose. That overload gives the
                // picker in-process access to the library, which requires photo
                // library authorisation and an NSPhotoLibraryUsageDescription.
                // RIG only ever asks for the chosen image's bytes, so the
                // out-of-process picker is both sufficient and permission-free.
                PhotosPicker(selection: $photoSelection, matching: .images) {
                    Text("Choose from Photos")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Color.accentColor)
                        .foregroundStyle(Color(uiColor: .systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: RIGTheme.Radius.control, style: .continuous))
                }

                if CameraPicker.isAvailable {
                    Button("Take a photo") {
                        isPresentingCamera = true
                    }
                    .buttonStyle(RIGSecondaryButtonStyle())
                } else {
                    Text("No camera is available on this device.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, RIGTheme.Spacing.m)
            .padding(.bottom, RIGTheme.Spacing.l)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var processingStep: some View {
        VStack(spacing: RIGTheme.Spacing.m) {
            ProgressView()
            Text("Separating the garment…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Processing the photo")
    }

    @ViewBuilder
    private var reviewStep: some View {
        Form {
            Section {
                GarmentImageView(
                    relativePath: importResult.flatMap { $0.cutoutRelativePath ?? $0.originalRelativePath },
                    symbolName: fields.category.symbolName
                )
                .frame(height: 220)
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)

                if let message = importResult?.backgroundRemovalMessage {
                    Text("\(message) The original photo will be used instead.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if let errorMessage {
                Section {
                    RIGErrorBanner(message: errorMessage) {
                        self.errorMessage = nil
                    }
                }
            }

            GarmentMetadataForm(fields: $fields)
        }
    }

    // MARK: - Actions

    @MainActor
    private func loadFromPhotos(_ selection: PhotosPickerItem) async {
        step = .processing
        do {
            guard let data = try await selection.loadTransferable(type: Data.self) else {
                fail("That photo could not be loaded. Try another one.")
                return
            }
            await process(data)
        } catch {
            fail("That photo could not be loaded. Try another one.")
        }
    }

    @MainActor
    private func process(_ data: Data) async {
        step = .processing
        do {
            let result = try await services.importService.importImage(data)
            importResult = result
            step = .review
        } catch {
            fail((error as? LocalizedError)?.errorDescription ?? "That photo could not be processed.")
        }
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
