import Foundation
import SwiftData
import SwiftUI

/// The wardrobe-duplicate comparison half of `OutfitPhotoSessionView`, split
/// into its own file purely for the static audit's line cap — see the type's
/// own doc comment in `OutfitPhotoSessionView.swift`.
extension OutfitPhotoSessionView {
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
                onAdjustCandidate: {
                    self.duplicateReview = nil
                    recrop()
                },
                onSkip: {
                    self.duplicateReview = nil
                    discard()
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
        guard let candidate = session.active,
              let result = candidate.importResult,
              fields.isValid else { return }

        guard let imageData = services.imageStore.data(
            atRelativePath: result.cutoutRelativePath ?? result.originalRelativePath
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
            guard item.category == category, item.id != candidate.id,
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
                among: WardrobeSimilarityQuery.candidates(from: items, category: category, excluding: candidate.id)
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
        duplicateReview = nil
        duplicateCandidateImageData = nil
    }

    /// "Use this existing item": no new `ClothingItem`, and the existing
    /// item's own stored image is never touched. This candidate's own files —
    /// which never became a garment of their own — are cleaned up exactly
    /// like any other unresolved candidate's.
    func useExisting(_ garmentID: UUID) {
        guard let candidate = session.active, candidate.importResult != nil else { return }
        try? services.imageStore.removeAll(for: candidate.id)
        session.markLinkedExisting(garmentID)
        fields = GarmentMetadataFields()
        duplicateReview = nil
        duplicateCandidateImageData = nil
    }
}
