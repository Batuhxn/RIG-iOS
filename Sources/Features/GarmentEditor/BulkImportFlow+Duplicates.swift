import Foundation
import SwiftUI

/// Duplicate review for the current bulk queue item.
extension BulkImportFlow {
    var duplicateSheetBinding: Binding<Bool> {
        Binding(get: { duplicateReview != nil }, set: { if !$0 { clearDuplicateReview() } })
    }

    @ViewBuilder
    var duplicateSheet: some View {
        if let duplicateReview,
           let item = queue.current, item.id == duplicateReview.itemID,
           let category = drafts[item.id]?.category {
            DuplicateComparisonSheet(
                candidateImageData: duplicateReview.candidateImageData,
                candidateCategory: category,
                state: duplicateReview.state,
                existingItemImagePath: { id in wardrobeItems.first { $0.id == id }?.displayImageRelativePath },
                existingItemName: { id in wardrobeItems.first { $0.id == id }?.displayName },
                onUseExisting: useExisting,
                onAddAsNew: commitSaveAndAdvance,
                onShowAnother: showAnotherDuplicate,
                onSkip: skip
            )
        }
    }

    func clearDuplicateReview() {
        duplicateReview = nil
    }

    func showAnotherDuplicate() {
        guard var updated = duplicateReview else { return }
        updated.showAnother()
        if updated.state.isExhausted {
            clearDuplicateReview()
            commitSaveAndAdvance()
        } else {
            duplicateReview = updated
        }
    }

    func beginSaveAndAdvance() {
        guard let item = queue.current, let result = item.importResult,
              let fields = drafts[item.id], fields.isValid,
              let category = fields.category else { return }
        let sources: [GarmentDuplicateSource] = wardrobeItems.compactMap { garment in
            guard let path = garment.preferredImageRelativePath else { return nil }
            return GarmentDuplicateSource(garmentID: garment.id, category: garment.category, imagePath: path)
        }
        let choice = imageChoices.choice(for: result)
        isCheckingForDuplicates = true
        Task { @MainActor in
            defer { isCheckingForDuplicates = false }
            let outcome = await GarmentDuplicateCheck.evaluate(
                result: result,
                choice: choice,
                category: category,
                sources: sources,
                store: services.imageStore,
                matcher: services.similarityMatcher
            )
            guard queue.current?.id == item.id else { return }
            switch outcome {
            case .save:
                commitSaveAndAdvance()
            case .review(let imageData, let review):
                duplicateReview = BulkDuplicateReview(
                    itemID: item.id, candidateImageData: imageData, state: review
                )
            }
        }
    }

    func useExisting(_ garmentID: UUID) {
        guard duplicateReview?.state.current?.garmentID == garmentID,
              let item = queue.current, item.id == duplicateReview?.itemID else { return }
        guard discardFiles(for: item.id) else { return }
        drafts[item.id] = nil
        imageChoices.remove(for: item.id)
        imageErrorMessage = nil
        clearDuplicateReview()
        queue.markUsedExisting()
        finishIfComplete()
    }

    @discardableResult
    func discardFiles(for id: UUID) -> Bool {
        do {
            try services.imageStore.removeAll(for: id)
            return true
        } catch {
            clearDuplicateReview()
            imageErrorMessage = "That photo could not be discarded. Try again."
            return false
        }
    }
}
