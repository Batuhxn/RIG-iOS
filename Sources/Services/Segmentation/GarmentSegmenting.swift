import Foundation

/// What one segmentation attempt produced, already converted into RIG's own
/// coordinate system.
///
/// Everything here is RIG-space: an upright source raster, normalized
/// top-left coordinates, x right, y down — the same convention
/// `NormalizedCropRect` uses everywhere else. Nothing about a model's resize,
/// padding or tensor layout is visible past this boundary; the adapter that
/// produces one of these owns all of that privately.
struct SegmentationMaskResult: Sendable, Equatable {
    /// PNG bytes with an alpha channel: the proposed cutout, already mapped
    /// back into RIG source-space and cropped to the mask's own bounds.
    let cutoutData: Data
    /// The mask's bounding rectangle in RIG's normalized image-space, so a
    /// review screen can overlay it against the original crop or source
    /// without knowing anything about how it was produced.
    let boundingRegion: NormalizedCropRect
    /// Segmentation/model quality only, when the model reports one (EdgeSAM's
    /// IoU/stability estimate). This is **not** a semantic confidence that the
    /// object is a jacket, a jumper or anything else — nothing here may be
    /// presented to the user as "garment confidence". See
    /// `OutfitCandidate.maskQuality`.
    let qualityScore: Double?
}

/// Why a segmentation attempt did not produce a result.
///
/// Every case here is recoverable: the session stays alive and the manual
/// rectangular crop remains available regardless of which of these fires.
enum SegmentationError: LocalizedError, Equatable {
    /// No segmenter is wired up, or the bundled model failed to load.
    case modelUnavailable
    case cancelled
    /// A prompt was answered after a newer one superseded it.
    case stalePrompt
    case encodingFailed
    case decodingFailed
    case maskConversionFailed

    var errorDescription: String? {
        switch self {
        case .modelUnavailable:
            return "On-device garment detection is not available right now."
        case .cancelled:
            return "That request was cancelled."
        case .stalePrompt:
            return "A newer selection replaced this one."
        case .encodingFailed:
            return "RIG could not prepare this photo for garment detection."
        case .decodingFailed:
            return "RIG could not propose a garment mask for that area."
        case .maskConversionFailed:
            return "RIG could not convert that mask back onto the photo."
        }
    }
}

/// An opaque handle to one cached encoder embedding.
///
/// Deliberately just an identifier: this file, and everything above it, never
/// sees a model tensor, an `MLMultiArray`, or any Core ML type at all. The
/// concrete adapter that implements `GarmentSegmenting` is the only place in
/// the app permitted to import Core ML — see `scripts/static_audit.py` and
/// `docs/DECISIONS.md`, "EdgeSAM and the Core ML exception (v0.4)".
struct SegmentationSourceToken: Sendable, Equatable {
    let id: UUID
}

/// The seam between garment mask proposals and whatever produces them.
///
/// One embedding is computed per outfit source image and reused across every
/// prompt drawn against it. This protocol only describes one encode and any
/// number of decodes against the token it returns; `OutfitEmbeddingSession`
/// is what actually owns the "encode once, decode many times" reuse and the
/// cancellation/staleness bookkeeping around it.
///
/// The protocol deals in `Data`, `NormalizedCropRect` and plain Sendable
/// value types on purpose — exactly the same reason `GarmentBackgroundRemoving`
/// deals in `Data` rather than `UIImage`: it keeps the seam free of both
/// UIKit and Core ML, so the rest of the app — including every test in this
/// file's test target — never needs either framework to reason about it.
protocol GarmentSegmenting: Sendable {
    /// True when a segmenter is actually able to run right now (model present
    /// and loaded). Checked before the interface ever offers AI mask review;
    /// when false, RIG behaves exactly as it did before this model existed.
    var isAvailable: Bool { get async }

    /// Encodes one bounded outfit source image. Callers are expected to call
    /// this once per source and reuse the token; calling it again for the
    /// same bytes is correct but wasteful, not incorrect.
    func encodeSource(_ imageData: Data) async throws -> SegmentationSourceToken

    /// Proposes a mask for one manually drawn region against an
    /// already-encoded source.
    ///
    /// `region` is expressed in RIG's normalized image-space — this method
    /// owns translating that into whatever prompt format the underlying
    /// model expects, and translating its output mask back, so nothing about
    /// model coordinates ever needs to leave the adapter that implements
    /// this protocol.
    func segment(
        region: NormalizedCropRect,
        in token: SegmentationSourceToken
    ) async throws -> SegmentationMaskResult
}

/// Always unavailable. The honest answer wherever EdgeSAM is not wired up:
/// SwiftUI previews, unit tests, and the live app on any device or
/// configuration where the bundled model failed to load. Mirrors
/// `PassthroughBackgroundRemover` in spirit — RIG must behave exactly as
/// though the capability did not exist, never crash or dead-end because it
/// is momentarily missing.
struct UnavailableSegmenter: GarmentSegmenting {
    var isAvailable: Bool {
        get async { false }
    }

    func encodeSource(_ imageData: Data) async throws -> SegmentationSourceToken {
        throw SegmentationError.modelUnavailable
    }

    func segment(
        region: NormalizedCropRect,
        in token: SegmentationSourceToken
    ) async throws -> SegmentationMaskResult {
        throw SegmentationError.modelUnavailable
    }
}
