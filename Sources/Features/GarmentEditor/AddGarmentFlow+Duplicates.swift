import Foundation
import SwiftData
import SwiftUI

/// The wardrobe-duplicate half of `AddGarmentFlow`, in its own file purely
/// for the static audit's line cap.
///
/// Single-item presentation and decisions for the shared duplicate check.
extension AddGarmentFlow {
    var duplicateSheetBinding: Binding<Bool> {
        Binding(get: { duplicateReview != nil }, set: {
            if !$0 {
                duplicateReview = nil
                duplicateCandidateImageData = nil
            }
        })
    }

    @ViewBuilder
    var duplicateSheet: some View {
        if let duplicateReview, let duplicateCandidateImageData, let category = fields.category {
            DuplicateComparisonSheet(
                candidateImageData: duplicateCandidateImageData,
                candidateCategory: category,
                state: duplicateReview,
                existingItemImagePath: { id in wardrobeItems.first { $0.id == id }?.displayImageRelativePath },
                existingItemName: { id in wardrobeItems.first { $0.id == id }?.displayName },
                onUseExisting: useExisting,
                onAddAsNew: commitSave,
                onShowAnother: showAnotherDuplicate,
                onSkip: {
                    self.duplicateReview = nil
                    self.duplicateCandidateImageData = nil
                    discardCandidateFiles()
                    dismiss()
                }
            )
        }
    }

    func showAnotherDuplicate() {
        guard var updated = duplicateReview else { return }
        updated.showAnother()
        if updated.isExhausted {
            duplicateReview = nil
            commitSave()
        } else {
            duplicateReview = updated
        }
    }

    /// Tapping "Save" never writes a garment directly. It first asks whether
    /// the wardrobe already looks like it owns this, and only proceeds to
    /// `commitSave()` — immediately, if nothing qualifies — once that
    /// question has an answer. Duplicate-matching failure is not fatal: any
    /// problem here falls straight through to `commitSave()`, exactly as if
    /// nothing had been asked.
    func beginSave() {
        guard let importResult, fields.isValid, let category = fields.category else {
            errorMessage = "There is no processed photo to save."
            return
        }

        let sources: [GarmentDuplicateSource] = wardrobeItems.compactMap { item in
            guard let path = item.preferredImageRelativePath else { return nil }
            return GarmentDuplicateSource(garmentID: item.id, category: item.category, imagePath: path)
        }
        isCheckingForDuplicates = true
        Task { @MainActor in
            defer { isCheckingForDuplicates = false }
            let outcome = await GarmentDuplicateCheck.evaluate(
                result: importResult,
                choice: imageChoice,
                category: category,
                sources: sources,
                store: services.imageStore,
                matcher: services.similarityMatcher
            )
            switch outcome {
            case .save:
                commitSave()
            case .review(let imageData, let review):
                duplicateCandidateImageData = imageData
                duplicateReview = review
            }
        }
    }

    func commitSave() {
        guard let importResult, fields.isValid,
              let category = fields.category, let colorFamily = fields.colorFamily else {
            errorMessage = "There is no processed photo to save."
            return
        }

        let presentation: GarmentImagePresentation
        do {
            presentation = try imageChoice.presentation(for: importResult, in: services.imageStore)
        } catch {
            errorMessage = "That image could not be prepared. Try saving again."
            return
        }

        let item = ClothingItem(
            id: importResult.garmentID,
            displayName: fields.trimmedName,
            subtype: fields.subtype.trimmingCharacters(in: .whitespacesAndNewlines),
            category: category,
            primaryColor: colorFamily,
            seasons: fields.seasons,
            isFavorite: fields.isFavorite,
            notes: fields.notes,
            originalImageRelativePath: importResult.originalRelativePath,
            cutoutImageRelativePath: importResult.cutoutRelativePath,
            thumbnailRelativePath: presentation.thumbnailRelativePath,
            isBackgroundRemoved: presentation.usesCutout
        )
        modelContext.insert(item)

        do {
            try modelContext.save()
        } catch {
            // The row did not persist, so the files it would have owned are
            // removed too rather than left behind as orphans.
            modelContext.delete(item)
            try? services.imageStore.removeAll(for: importResult.garmentID)
            duplicateReview = nil
            duplicateCandidateImageData = nil
            errorMessage = "That garment could not be saved to this device."
            return
        }

        duplicateReview = nil
        duplicateCandidateImageData = nil
        dismiss()
    }

    /// "Use this existing item": no new `ClothingItem`, and the existing
    /// item's own stored image is never touched. This candidate's own files —
    /// which never became a garment of their own — are removed exactly like
    /// any other abandoned import's.
    func useExisting(_ garmentID: UUID) {
        guard importResult != nil else { return }
        discardCandidateFiles()
        duplicateReview = nil
        duplicateCandidateImageData = nil
        dismiss()
    }
}
