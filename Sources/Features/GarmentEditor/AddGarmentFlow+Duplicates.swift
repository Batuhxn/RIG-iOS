import Foundation
import SwiftData
import SwiftUI

/// The wardrobe-duplicate half of `AddGarmentFlow`, in its own file purely
/// for the static audit's line cap.
///
/// Duplicate protection belongs to the canonical single-item import: it is
/// the only place in RIG where a new `ClothingItem` is created from a fresh
/// photograph one at a time, and so the only place where "you may already own
/// this" is a question worth interrupting for.
extension AddGarmentFlow {
    var duplicateSheetBinding: Binding<Bool> {
        Binding(get: { duplicateReview != nil }, set: { if !$0 { duplicateReview = nil } })
    }

    @ViewBuilder
    var duplicateSheet: some View {
        if let duplicateReview, let duplicateCandidateImageData {
            DuplicateComparisonSheet(
                candidateImageData: duplicateCandidateImageData,
                candidateCategory: fields.category,
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
        guard let importResult, fields.isValid else {
            errorMessage = "There is no processed photo to save."
            return
        }

        guard let imageData = services.imageStore.data(
            atRelativePath: importResult.cutoutRelativePath ?? importResult.originalRelativePath
        ) else {
            commitSave()
            return
        }

        let category = fields.category
        let matcher = services.similarityMatcher
        let store = services.imageStore
        // Extracted to plain Sendable values before crossing into the Task:
        // `ClothingItem` is a SwiftData model and must not cross an actor
        // boundary, only the handful of facts this comparison actually needs.
        let sameCategoryItems: [(garmentID: UUID, imagePath: String)] = wardrobeItems.compactMap { item in
            guard item.category == category, item.id != importResult.garmentID,
                  let path = item.preferredImageRelativePath else { return nil }
            return (item.id, path)
        }

        isCheckingForDuplicates = true
        Task { @MainActor in
            defer { isCheckingForDuplicates = false }

            let items: [WardrobeSimilarityCandidateItem] = sameCategoryItems.compactMap { entry in
                guard let data = store.data(atRelativePath: entry.imagePath) else { return nil }
                return WardrobeSimilarityCandidateItem(garmentID: entry.garmentID, category: category, imageData: data)
            }

            let matches = await matcher.rankSimilarItems(
                to: imageData,
                among: WardrobeSimilarityQuery.candidates(
                    from: items,
                    category: category,
                    excluding: importResult.garmentID
                )
            )
            let review = DuplicateReviewState(matches: matches)
            if review.isExhausted {
                commitSave()
            } else {
                duplicateCandidateImageData = imageData
                duplicateReview = review
            }
        }
    }

    func commitSave() {
        guard let importResult, fields.isValid else {
            errorMessage = "There is no processed photo to save."
            return
        }

        let item = ClothingItem(
            id: importResult.garmentID,
            displayName: fields.trimmedName,
            subtype: fields.subtype.trimmingCharacters(in: .whitespacesAndNewlines),
            category: fields.category,
            primaryColor: fields.colorFamily,
            seasons: fields.seasons,
            isFavorite: fields.isFavorite,
            notes: fields.notes,
            originalImageRelativePath: importResult.originalRelativePath,
            cutoutImageRelativePath: importResult.cutoutRelativePath,
            thumbnailRelativePath: importResult.thumbnailRelativePath,
            isBackgroundRemoved: importResult.isBackgroundRemoved
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
