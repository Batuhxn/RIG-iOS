import Foundation

/// What one garment import produced.
struct GarmentImportResult: Hashable, Sendable {
    let garmentID: UUID
    let originalRelativePath: String
    let cutoutRelativePath: String?
    let thumbnailRelativePath: String?
    let isBackgroundRemoved: Bool
    /// Present when background removal did not succeed. Shown to the user as an
    /// explanation, never as a failure that blocks saving the garment.
    let backgroundRemovalMessage: String?
}

enum GarmentImportError: LocalizedError, Equatable {
    case unreadableImage

    var errorDescription: String? {
        switch self {
        case .unreadableImage:
            return "Bu fotoğraf okunamadı. Başka bir görsel dene."
        }
    }
}

/// Turns an imported photograph into the files a garment owns.
///
/// This is the orchestration half of the image pipeline and knows nothing about
/// Vision. Background removal arrives as a protocol, which is what allows the
/// whole flow — including the failure path — to be exercised without an Apple
/// runtime.
///
/// The contract that matters: **background removal failure never blocks import.**
/// A garment with only its original photograph is a perfectly good garment.
struct GarmentImportService: Sendable {
    let store: GarmentImageStore
    let backgroundRemover: any GarmentBackgroundRemoving

    init(store: GarmentImageStore, backgroundRemover: any GarmentBackgroundRemoving) {
        self.store = store
        self.backgroundRemover = backgroundRemover
    }

    /// - Parameters:
    ///   - imageData: the source pixels for the retained "original" — always
    ///     downscaled and written as JPEG. These are never expected to carry
    ///     alpha, so that conversion has never been the problem.
    func importImage(
        _ imageData: Data,
        garmentID: UUID = UUID()
    ) async throws -> GarmentImportResult {
        guard let originalData = GarmentImageProcessing.jpegData(
            from: imageData,
            maxDimension: GarmentImageProcessing.originalMaxDimension
        ) else {
            throw GarmentImportError.unreadableImage
        }

        let originalPath = try store.write(originalData, for: garmentID, kind: .original)

        var cutoutPath: String?
        var isolated = false
        var failureMessage: String?

        do {
            let result = try await backgroundRemover.removeBackground(from: originalData)
            if result.isolated,
               let cutoutData = GarmentImageProcessing.pngData(
                   from: result.imageData,
                   maxDimension: GarmentImageProcessing.cutoutMaxDimension
               ) {
                cutoutPath = try store.write(cutoutData, for: garmentID, kind: .cutout)
                isolated = true
            } else {
                failureMessage = BackgroundRemovalError.noForegroundFound.errorDescription
            }
        } catch let error as BackgroundRemovalError {
            failureMessage = error.errorDescription
        } catch {
            failureMessage = BackgroundRemovalError.maskGenerationFailed.errorDescription
        }

        let thumbnailSource = cutoutPath.flatMap { store.data(atRelativePath: $0) } ?? originalData
        var thumbnailPath: String?
        if let thumbnailData = GarmentImageProcessing.pngData(
            from: thumbnailSource,
            maxDimension: GarmentImageProcessing.thumbnailMaxDimension
        ) {
            thumbnailPath = try? store.write(thumbnailData, for: garmentID, kind: .thumbnail)
        }

        return GarmentImportResult(
            garmentID: garmentID,
            originalRelativePath: originalPath,
            cutoutRelativePath: cutoutPath,
            thumbnailRelativePath: thumbnailPath,
            isBackgroundRemoved: isolated,
            backgroundRemovalMessage: isolated ? nil : failureMessage
        )
    }
}
