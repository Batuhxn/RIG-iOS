import PhotosUI
import SwiftData
import SwiftUI

/// Bring an existing wardrobe in: select many photographs once, then review
/// them one at a time through the ordinary single-garment controls.
///
/// Two rules shape this flow.
///
/// **Nothing is saved without confirmation.** RIG cannot yet tell a shirt from
/// a shoe, so every garment still passes under the user's eye.
///
/// **One photograph is in memory at a time.** The queue holds identifiers, not
/// images; a photograph is loaded, downscaled to disk by the existing import
/// pipeline, and released before the next one is touched.
struct BulkImportFlow: View {
    private enum Stage: Equatable {
        case selection
        case review
        case summary
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.rigServices) private var services
    @Environment(\.dismiss) private var dismiss

    @State private var stage: Stage = .selection
    @State private var selections: [PhotosPickerItem] = []
    @State private var queue = BulkImportQueue()
    @State private var drafts: [UUID: GarmentMetadataFields] = [:]
    @State private var attempt = 0
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .selection:
                    selectionStep
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
            .onChange(of: selections) { _, newValue in
                guard stage == .selection, !newValue.isEmpty else { return }
                queue = BulkImportQueue.reserving(newValue.count)
                stage = queue.isEmpty ? .summary : .review
            }
            .task(id: processingKey) {
                await processCurrentItem()
            }
        }
    }

    // MARK: - Steps

    private var selectionStep: some View {
        VStack(spacing: RIGTheme.Spacing.m) {
            Spacer(minLength: 0)

            Image(systemName: "square.stack")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("Bring in several at once")
                .font(.headline)
            Text("Pick up to \(BulkImportQueue.maximumSelectionCount) photos. RIG processes them one by one and asks you to describe each garment before it is saved. Everything happens on this device.")
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

            // As in the single-garment flow, no `photoLibrary:` argument: the
            // out-of-process picker hands over the chosen bytes and needs no
            // photo library authorisation.
            PhotosPicker(
                selection: $selections,
                maxSelectionCount: BulkImportQueue.maximumSelectionCount,
                selectionBehavior: .ordered,
                matching: .images
            ) {
                Text("Choose photos")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Color.accentColor)
                    .foregroundStyle(Color(uiColor: .systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: RIGTheme.Radius.control, style: .continuous))
            }
            .padding(.horizontal, RIGTheme.Spacing.m)
            .padding(.bottom, RIGTheme.Spacing.l)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

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
                case .saved, .skipped:
                    EmptyView()
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
            GarmentImageView(
                relativePath: result.cutoutRelativePath ?? result.originalRelativePath,
                symbolName: currentFields.category.symbolName
            )
            .frame(height: 200)
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)

            if let message = result.backgroundRemovalMessage {
                Text("\(message) The original photo will be used instead.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var navigationSection: some View {
        Section {
            Button("Skip this photo", action: skip)
            if queue.canGoBack {
                Button("Back", action: goBack)
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
            }
        }
        if stage == .review, let item = queue.current, item.importResult != nil {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save & Next", action: saveAndAdvance)
                    .disabled(!(drafts[item.id]?.isValid ?? false))
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

    private var summaryTitle: String {
        queue.savedCount == 1 ? "1 garment added" : "\(queue.savedCount) garments added"
    }

    private var summaryMessage: String {
        var parts: [String] = []
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
        guard selections.indices.contains(item.position) else {
            queue.markFailed("That photo is no longer available.")
            return
        }

        do {
            guard let data = try await selections[item.position].loadTransferable(type: Data.self) else {
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

    private func saveAndAdvance() {
        guard let item = queue.current, let result = item.importResult else { return }
        let fields = drafts[item.id] ?? GarmentMetadataFields()
        guard fields.isValid else { return }

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
            // The row did not persist, so neither the record nor its files are
            // left behind. The item becomes a recoverable failure rather than
            // taking the rest of the batch down with it.
            modelContext.delete(garment)
            try? services.imageStore.removeAll(for: result.garmentID)
            queue.markFailed("That garment could not be saved to this device.")
            return
        }

        drafts[item.id] = nil
        queue.markSaved()
        finishIfComplete()
    }

    private func skip() {
        if let item = queue.current {
            try? services.imageStore.removeAll(for: item.id)
            drafts[item.id] = nil
        }
        queue.skip()
        finishIfComplete()
    }

    private func goBack() {
        queue.goBack()
        attempt += 1
    }

    private func finishIfComplete() {
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
    BulkImportFlow()
        .modelContainer(PreviewData.container(populated: false))
        .environment(\.rigServices, .preview())
}
