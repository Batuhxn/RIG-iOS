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
            return "That photo could not be read. Try another image."
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
    ///   - imageData: the raw crop or source pixels for the retained
    ///     "original" — always downscaled and written as JPEG, exactly as
    ///     before. These are never expected to carry alpha, so that
    ///     conversion has never been the problem.
    ///   - precomputedCutout: an already-segmented, user-approved cutout —
    ///     v0.4's EdgeSAM mask review, accepted — supplied instead of asking
    ///     `backgroundRemover` to find one. When present, its alpha is
    ///     preserved end to end: it is written straight through
    ///     `GarmentImageProcessing.pngData`, the same PNG path an ordinary
    ///     Vision cutout already takes, and `backgroundRemover` is never
    ///     consulted — running foreground removal a second time on something
    ///     already segmented would be both wasted work and a chance to
    ///     silently replace what the user approved. `nil` (the default)
    ///     reproduces the exact v0.1–v0.4-Slice-1 behaviour: the manual crop
    ///     goes to `backgroundRemover` exactly as it always did.
    func importImage(
        _ imageData: Data,
        garmentID: UUID = UUID(),
        precomputedCutout: Data? = nil
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

        if let precomputedCutout {
            if let cutoutData = GarmentImageProcessing.pngData(
                from: precomputedCutout,
                maxDimension: GarmentImageProcessing.cutoutMaxDimension
            ) {
                cutoutPath = try store.write(cutoutData, for: garmentID, kind: .cutout)
                isolated = true
            } else {
                failureMessage = BackgroundRemovalError.renderingFailed.errorDescription
            }
        } else {
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
