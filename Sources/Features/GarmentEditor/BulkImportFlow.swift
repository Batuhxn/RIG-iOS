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
    @Environment(\.rigServices) private var services
    @Environment(\.dismiss) private var dismiss

    @State private var stage: Stage
    @State private var queue: BulkImportQueue
    @State private var drafts: [UUID: GarmentMetadataFields] = [:]
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
        VStack(spacing: 0) {
            RIGSheetHeader(
                title: "Toplu aktarım",
                leadingTitle: stage == .summary ? "Bitti" : "Kapat",
                leadingAction: stage == .summary ? finish : cancel
            )

            Group {
                switch stage {
                case .review: reviewStep
                case .summary: summaryStep
                }
            }
            .transition(.opacity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RIGTheme.pageBackground)
        .animation(NocturneMotion.screen, value: stage)
        .task(id: processingKey) {
            await processCurrentItem()
        }
    }

    // MARK: - Steps

    @ViewBuilder
    private var reviewStep: some View {
        if let item = queue.current {
            VStack(spacing: 0) {
                queueProgressHeader

                ScrollView {
                    VStack(alignment: .leading, spacing: RIGTheme.Spacing.l) {
                        switch item.status {
                        case .pending:
                            processingCard
                        case .failed(let message):
                            failureCard(message)
                        case .ready(let result):
                            previewCard(result)
                            NocturneMetadataFields(fields: fieldsBinding(for: item.id))
                        case .saved, .skipped:
                            EmptyView()
                        }
                    }
                    .padding(.horizontal, RIGTheme.Spacing.xl)
                    .padding(.top, RIGTheme.Spacing.m)
                    .padding(.bottom, RIGTheme.Spacing.xl)
                }

                actions(for: item)
            }
        } else {
            summaryStep
        }
    }

    /// The batch's own progress, above whichever photograph is in hand.
    private var queueProgressHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(queue.progressLabel)
                    .font(.system(size: 26, weight: .medium))
                    .tracking(-0.5)
                Spacer(minLength: 8)
                Text(queueStatusLine)
                    .font(.system(size: 12))
                    .foregroundStyle(RIGTheme.text(55))
            }
            RIGProgressBar(fraction: queueFraction)
        }
        .padding(.horizontal, RIGTheme.Spacing.xl)
        .padding(.top, RIGTheme.Spacing.m)
        .accessibilityElement(children: .combine)
    }

    private var processingCard: some View {
        VStack(spacing: RIGTheme.Spacing.l) {
            RIGSpinner(diameter: 26)
            Text("Arka plan kaldırılıyor…")
                .font(.system(size: 13))
                .foregroundStyle(RIGTheme.text(55))
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .background(RIGTheme.cardBackground, in: RoundedRectangle(cornerRadius: RIGTheme.Radius.large, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Fotoğraf işleniyor")
    }

    private func failureCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: RIGTheme.Spacing.m) {
            RIGErrorBanner(message: message)
            Button("Bu fotoğrafı tekrar dene") {
                queue.retry()
                attempt += 1
            }
            .buttonStyle(RIGSecondaryButtonStyle())
        }
    }

    private func previewCard(_ result: GarmentImportResult) -> some View {
        VStack(spacing: RIGTheme.Spacing.s) {
            ZStack {
                RIGCheckerboard()
                GarmentImageView(
                    relativePath: result.cutoutRelativePath ?? result.originalRelativePath,
                    symbolName: currentFields.category.symbolName
                )
                .padding(RIGTheme.Spacing.l)

                VStack {
                    HStack {
                        RIGTag(
                            text: result.isBackgroundRemoved ? "Arka plan kaldırıldı" : "Orijinal fotoğraf",
                            kind: .accent
                        )
                        Spacer(minLength: 0)
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
            }
            .frame(height: 240)
            .clipShape(RoundedRectangle(cornerRadius: RIGTheme.Radius.large, style: .continuous))
            .nocturneElevationSmall(radius: RIGTheme.Radius.large)

            if let message = result.backgroundRemovalMessage {
                Text("\(message) Orijinal fotoğraf kullanılacak.")
                    .font(.system(size: 12))
                    .foregroundStyle(RIGTheme.text(55))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func actions(for item: BulkImportQueueItem) -> some View {
        VStack(spacing: RIGTheme.Spacing.s) {
            if item.importResult != nil {
                Button("Kaydet ve devam et", action: saveAndAdvance)
                    .buttonStyle(RIGPrimaryButtonStyle())
                    .disabled(!(drafts[item.id]?.isValid ?? false))
                    .opacity((drafts[item.id]?.isValid ?? false) ? 1 : 0.45)
            }

            Button("Bu fotoğrafı atla", action: skip)
                .buttonStyle(RIGQuietButtonStyle())

            if queue.canGoBack {
                Button("Geri", action: goBack)
                    .buttonStyle(RIGQuietButtonStyle())
            }

            Text("Atlanan fotoğraflar saklanmaz. Kaydettiğin parçalar, şimdi çıksan bile dolabında kalır.")
                .font(.system(size: 11))
                .foregroundStyle(RIGTheme.text(48))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, RIGTheme.Spacing.xl)
        .padding(.top, RIGTheme.Spacing.m)
        .padding(.bottom, RIGTheme.Spacing.l)
    }

    private var summaryStep: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                RIGTheme.kicker("Toplu aktarım bitti")
                Text(summaryTitle)
                    .font(.system(size: 24, weight: .medium))
                Text(summaryMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(RIGTheme.text(55))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, RIGTheme.Spacing.xl)
            .padding(.bottom, RIGTheme.Spacing.l)

            BulkImportQueueList(queue: queue)

            Button("Dolabı gör", action: finish)
                .buttonStyle(RIGPrimaryButtonStyle())
                .padding(.horizontal, RIGTheme.Spacing.xl)
                .padding(.top, RIGTheme.Spacing.m)
                .padding(.bottom, RIGTheme.Spacing.l)
        }
        .padding(.top, RIGTheme.Spacing.m)
    }

    private var queueStatusLine: String {
        var parts: [String] = []
        if queue.savedCount > 0 { parts.append("\(queue.savedCount) hazır") }
        if queue.skippedCount > 0 { parts.append("\(queue.skippedCount) atlandı") }
        if queue.failedCount > 0 { parts.append("\(queue.failedCount) hata") }
        return parts.joined(separator: " · ")
    }

    private var queueFraction: Double {
        guard queue.count > 0 else { return 0 }
        let settled = queue.savedCount + queue.skippedCount + queue.failedCount
        return Double(settled) / Double(queue.count)
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
        queue.savedCount == 1 ? "1 parça eklendi" : "\(queue.savedCount) parça eklendi"
    }

    private var summaryMessage: String {
        var parts: [String] = []
        if queue.skippedCount > 0 { parts.append("\(queue.skippedCount) atlandı") }
        if queue.failedCount > 0 { parts.append("\(queue.failedCount) işlenemedi") }
        guard !parts.isEmpty else { return "İncelediğin her şey dolabında." }
        return parts.joined(separator: ", ") + ". Başka bir şey saklanmadı."
    }

    // MARK: - Work

    /// Loads, processes and files exactly one photograph. Nothing runs ahead of
    /// the cursor, so at most one full-resolution image is decoded at a time.
    @MainActor
    private func processCurrentItem() async {
        guard stage == .review, let item = queue.current, item.status == .pending else { return }
        guard items.indices.contains(item.position) else {
            queue.markFailed("Bu fotoğraf artık kullanılamıyor.")
            return
        }

        do {
            guard let data = try await items[item.position].loadTransferable(type: Data.self) else {
                queue.markFailed("Bu fotoğraf yüklenemedi. Atla ya da tekrar dene.")
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
            queue.markFailed(described ?? "Bu fotoğraf işlenemedi. Atla ya da tekrar dene.")
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
            queue.markFailed("Bu parça cihaza kaydedilemedi.")
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
    BulkImportFlow(items: [])
        .modelContainer(PreviewData.container(populated: false))
        .environment(\.rigServices, .preview())
}
