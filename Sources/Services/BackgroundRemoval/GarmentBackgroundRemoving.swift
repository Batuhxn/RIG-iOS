import Foundation

/// What background removal produced.
///
/// `isolated == false` means the garment could not be separated and the caller
/// is looking at the original photograph. The interface says so rather than
/// pretending a cutout happened.
struct BackgroundRemovalResult: Hashable, Sendable {
    /// PNG bytes when isolated, otherwise the bytes handed in.
    let imageData: Data
    let isolated: Bool
}

enum BackgroundRemovalError: LocalizedError, Equatable {
    case unreadableImage
    case noForegroundFound
    case maskGenerationFailed
    case renderingFailed

    var errorDescription: String? {
        switch self {
        case .unreadableImage:
            return "That image could not be read."
        case .noForegroundFound:
            return "RIG could not find a garment in that photo."
        case .maskGenerationFailed, .renderingFailed:
            return "RIG could not separate the garment from its background."
        }
    }
}

/// The seam between garment import and Apple Vision.
///
/// It deals in `Data` on purpose: image bytes are `Sendable`, `UIImage` is not,
/// and keeping the protocol free of UIKit is what lets the import pipeline be
/// exercised without a Vision runtime.
protocol GarmentBackgroundRemoving: Sendable {
    func removeBackground(from imageData: Data) async throws -> BackgroundRemovalResult
}

/// Returns the image untouched. Used in previews, in tests, and as the honest
/// answer on any platform where foreground extraction is unavailable.
struct PassthroughBackgroundRemover: GarmentBackgroundRemoving {
    func removeBackground(from imageData: Data) async throws -> BackgroundRemovalResult {
        BackgroundRemovalResult(imageData: imageData, isolated: false)
    }
}

/// Always fails. Used to exercise the fallback path in tests.
struct FailingBackgroundRemover: GarmentBackgroundRemoving {
    let error: BackgroundRemovalError

    init(error: BackgroundRemovalError = .noForegroundFound) {
        self.error = error
    }

    func removeBackground(from imageData: Data) async throws -> BackgroundRemovalResult {
        throw error
    }
}
