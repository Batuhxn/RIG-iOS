import PhotosUI
import SwiftData
import SwiftUI

/// Review photographs of individual garments, one at a time.
///
/// Selection happens upstream, in the unified import flow — this screen is
/// reached only when the user picked more than one photograph, and they are
/// never told that a different code path handled the single-photo case.
///
/// Two rules shape it.
///
/// **Nothing is saved without confirmation.** RIG cannot yet tell a shirt from
/// a shoe, so every garment still passes under the user's eye.
///
/// **One photograph is in memory at a time.** The queue holds identifiers, not
/// images; a photograph is loaded, downscaled to disk by the existing import
/// pipeline, and released before the next one is touched.
struct BulkImportFlow: View {
    private enum Stage: Equatable {
        case review
        case summary
    }

    /// The photographs the user chose, in the order they chose them.
    let items: [PhotosPickerItem]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.rigServices) var services
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\ClothingItem.createdAt, order: .reverse)])
    var wardrobeItems: [ClothingItem]

    @State private var stage: Stage
    @State var queue: BulkImportQueue
    @State var drafts: [UUID: GarmentMetadataFields] = [:]
    @State var imageChoices = GarmentImageChoices()
    @State var imageErrorMessage: String?
    @State var duplicateReview: BulkDuplicateReview?
    @State var isCheckingForDuplicates = false
    @State private var attempt = 0

    init(items: [PhotosPickerItem]) {
        // Capped here as well as at the picker: a queue must never be longer
        // than the selection it indexes into.
        let bounded = Array(items.prefix(BulkImportQueue.maximumSelectionCount))
        self.items = bounded
        _queue = State(initialValue: BulkImportQueue.reserving(bounded.count))
        _stage = State(initialValue: bounded.isEmpty ? Stage.summary : Stage.review)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .review:
                    reviewStep
                case .summary:
                    summaryStep
                }
            }
            .background(RIGTheme.pageBackground)
            .navigationTitle("Import photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .task(id: processingKey) {
                await processCurrentItem()
            }
        }
        .sheet(isPresented: duplicateSheetBinding) { duplicateSheet }
    }

    // MARK: - Steps

    @ViewBuilder
    private var reviewStep: some View {
        if let item = queue.current {
            Form {
                Section {
                    Text(queue.progressLabel)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(Color.clear)
                        .accessibilityLabel("Garment \(queue.progressLabel)")
                }

                switch item.status {
                case .pending:
                    processingSection
                case .failed(let message):
                    failureSection(message)
                case .ready(let result):
                    previewSection(result)
                    GarmentMetadataForm(fields: fieldsBinding(for: item.id))
                        .disabled(isCheckingForDuplicates)
                case .saved, .usedExisting, .skipped:
                    EmptyView()
                }

                if let imageErrorMessage {
                    Section {
                        RIGErrorBanner(message: imageErrorMessage) {
                            self.imageErrorMessage = nil
                        }
                    }
                }

                navigationSection
            }
        } else {
            summaryStep
        }
    }

    private var processingSection: some View {
        Section {
            HStack(spacing: RIGTheme.Spacing.s) {
                ProgressView()
                Text("Separating the garment…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 120)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Processing the photo")
        }
    }

    private func failureSection(_ message: String) -> some View {
        Section {
            RIGErrorBanner(message: message)
            Button("Try this photo again") {
                queue.retry()
                attempt += 1
            }
        }
    }

    private func previewSection(_ result: GarmentImportResult) -> some View {
        Section {
            GarmentImageReview(
                result: result,
                choice: imageChoiceBinding(for: result),
                symbolName: currentFields.category?.symbolName ?? "photo",
                imageHeight: 200,
                choiceEnabled: !isCheckingForDuplicates
            )
        }
    }

    private var navigationSection: some View {
        Section {
            Button("Skip this photo", action: skip)
                .disabled(isCheckingForDuplicates)
            if queue.canGoBack {
                Button("Back", action: goBack)
                    .disabled(isCheckingForDuplicates)
            }
        } footer: {
            Text("Skipped photos are discarded. Garments you have already saved stay in your wardrobe even if you leave now.")
        }
    }

    private var summaryStep: some View {
        RIGEmptyState(
            symbol: "checkmark.circle",
            title: summaryTitle,
            message: summaryMessage,
            actionTitle: "Done",
            action: finish
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            if stage == .summary {
                Button("Done", action: finish)
            } else {
                Button("Cancel", action: cancel)
                    .disabled(isCheckingForDuplicates)
            }
        }
        if stage == .review, let item = queue.current, item.importResult != nil {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save & Next", action: beginSaveAndAdvance)
                    .disabled(!(drafts[item.id]?.isValid ?? false) || isCheckingForDuplicates)
            }
        }
    }

    // MARK: - Derived state

    /// Re-runs the processing task when the cursor moves, and again when a
    /// failed item is retried.
    private var processingKey: String {
        guard stage == .review, let item = queue.current else { return "idle" }
        return "\(item.id.uuidString)-\(attempt)"
    }

    private var currentFields: GarmentMetadataFields {
        queue.current.flatMap { drafts[$0.id] } ?? GarmentMetadataFields()
    }

    private func fieldsBinding(for id: UUID) -> Binding<GarmentMetadataFields> {
        Binding(
            get: { drafts[id] ?? GarmentMetadataFields() },
            set: { drafts[id] = $0 }
        )
    }

    private func imageChoiceBinding(for result: GarmentImportResult) -> Binding<GarmentImageChoice> {
        Binding(
            get: { imageChoices.choice(for: result) },
            set: { imageChoices.select($0, for: result) }
        )
    }

    private var summaryTitle: String {
        if queue.savedCount == 0 { return "Import complete" }
        return queue.savedCount == 1 ? "1 garment added" : "\(queue.savedCount) garments added"
    }

    private var summaryMessage: String {
        var parts: [String] = []
        if queue.usedExistingCount > 0 { parts.append("\(queue.usedExistingCount) already in your wardrobe") }
        if queue.skippedCount > 0 { parts.append("\(queue.skippedCount) skipped") }
        if queue.failedCount > 0 { parts.append("\(queue.failedCount) could not be processed") }
        guard !parts.isEmpty else { return "Everything you reviewed is in your wardrobe." }
        return parts.joined(separator: ", ") + ". Nothing else was kept."
    }

    // MARK: - Work

    /// Loads, processes and files exactly one photograph. Nothing runs ahead of
    /// the cursor, so at most one full-resolution image is decoded at a time.
    @MainActor
    private func processCurrentItem() async {
        guard stage == .review, let item = queue.current, item.status == .pending else { return }
        imageErrorMessage = nil
        guard items.indices.contains(item.position) else {
            queue.markFailed("That photo is no longer available.")
            return
        }

        do {
            guard let data = try await items[item.position].loadTransferable(type: Data.self) else {
                queue.markFailed("That photo could not be loaded. Skip it or try again.")
                return
            }
            let result = try await services.importService.importImage(data, garmentID: item.id)
            guard !Task.isCancelled else {
                // The cursor moved out from under this item; its files are
                // already filed under an identifier the clean-up sweep covers.
                return
            }
            queue.markReady(result)
        } catch {
            let described = (error as? LocalizedError)?.errorDescription
            queue.markFailed(described ?? "That photo could not be processed. Skip it or try again.")
        }
    }

    func commitSaveAndAdvance() {
        guard let item = queue.current, let result = item.importResult else { return }
        let fields = drafts[item.id] ?? GarmentMetadataFields()
        guard fields.isValid, let category = fields.category,
              let colorFamily = fields.colorFamily else { return }

        let presentation: GarmentImagePresentation
        do {
            presentation = try imageChoices.choice(for: result).presentation(for: result, in: services.imageStore)
        } catch {
            imageErrorMessage = "That image could not be prepared. Try saving again."
            return
        }

        let garment = ClothingItem(
            id: result.garmentID,
            displayName: fields.trimmedName,
            subtype: fields.subtype.trimmingCharacters(in: .whitespacesAndNewlines),
            category: category,
            primaryColor: colorFamily,
            seasons: fields.seasons,
            isFavorite: fields.isFavorite,
            notes: fields.notes,
            originalImageRelativePath: result.originalRelativePath,
            cutoutImageRelativePath: result.cutoutRelativePath,
            thumbnailRelativePath: presentation.thumbnailRelativePath,
            isBackgroundRemoved: presentation.usesCutout
        )
        modelContext.insert(garment)

        do {
            try modelContext.save()
        } catch {
            // The row did not persist, so neither the record nor its files are
            // left behind. The item becomes a recoverable failure rather than
            // taking the rest of the batch down with it.
            modelContext.delete(garment)
            try? services.imageStore.removeAll(for: result.garmentID)
            queue.markFailed("That garment could not be saved to this device.")
            clearDuplicateReview()
            return
        }

        drafts[item.id] = nil
        imageChoices.remove(for: item.id)
        imageErrorMessage = nil
        clearDuplicateReview()
        queue.markSaved()
        finishIfComplete()
    }

    func skip() {
        if let item = queue.current {
            guard discardFiles(for: item.id) else { return }
            drafts[item.id] = nil
            imageChoices.remove(for: item.id)
        }
        imageErrorMessage = nil
        clearDuplicateReview()
        queue.skip()
        finishIfComplete()
    }

    private func goBack() {
        imageErrorMessage = nil
        queue.goBack()
        attempt += 1
    }

    func finishIfComplete() {
        if queue.isComplete { stage = .summary }
    }

    /// Saved garments stay. Everything else — reviewed but unconfirmed, failed,
    /// skipped, never reached — leaves no files behind.
    private func discardUnsavedArtifacts() {
        for id in queue.garmentIDsPendingCleanup {
            try? services.imageStore.removeAll(for: id)
        }
    }

    private func finish() {
        discardUnsavedArtifacts()
        dismiss()
    }

    private func cancel() {
        discardUnsavedArtifacts()
        dismiss()
    }
}

#Preview {
    BulkImportFlow(items: [])
        .modelContainer(PreviewData.container(populated: false))
        .environment(\.rigServices, .preview())
}
