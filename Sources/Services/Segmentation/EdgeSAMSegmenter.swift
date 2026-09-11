import CoreGraphics
import CoreML
import Foundation
import UIKit

/// The on-device EdgeSAM adapter behind `GarmentSegmenting`.
///
/// UNVERIFIED: this has never executed. It was written on a Windows host
/// with no Apple runtime available — the same caveat class as
/// `VisionBackgroundRemover`, but carrying more risk, since it also depends
/// on the exact Core ML artifacts bundled in
/// `Sources/Resources/Models/`. Unlike the rest of this app's ML-adjacent
/// code, though, the *interface* this file was written against — input and
/// output tensor names, shapes, coordinate space, label conventions — was
/// not taken from documentation or guessed: it was read directly out of the
/// bundled `.mlpackage` files' own protobuf specs and cross-checked against
/// EdgeSAM's own export/inference source. See
/// `docs/EDGESAM_PROVENANCE.md` for the full trail. What remains
/// unverified is purely whether *this Swift code* compiles and behaves as
/// intended against that interface, not what the interface itself is.
///
/// An actor for two reasons: model loading and the single-slot embedding
/// cache both need to be mutated safely by overlapping calls, and every
/// `MLModel.prediction(from:)` call — synchronous and potentially slow — is
/// dispatched off the actor's own executor so it never blocks whichever
/// thread this actor happens to be running on, in addition to never
/// blocking the `@MainActor` UI (`prediction(from:)` is documented by Apple
/// as safe to call concurrently, which is what makes that dispatch safe).
actor EdgeSAMSegmenter: GarmentSegmenting {
    private enum LoadState {
        case notLoaded
        case loaded(encoder: MLModel, decoder: MLModel)
        case unavailable
    }

    private let bundle: Bundle
    private let encoderResourceName: String
    private let decoderResourceName: String
    private var loadState: LoadState = .notLoaded

    // The single cached "encoded source": everything `segment(region:in:)`
    // needs to answer a prompt without being handed the source image again,
    // since `GarmentSegmenting.segment` only takes a token. One slot only —
    // this slice's call pattern is exactly one active outfit source at a
    // time (`OutfitEmbeddingSession` never holds more than one), and a
    // single slot is what makes "session closes / source changes" trivially
    // correct: the next `encodeSource` simply overwrites it.
    private var cachedToken: SegmentationSourceToken?
    private var cachedEmbedding: MLMultiArray?
    private var cachedResizeMetadata: EdgeSAMResizeMetadata?
    private var cachedSourceImage: CGImage?

    init(bundle: Bundle = .main, encoderResourceName: String = "edge_sam_3x_encoder", decoderResourceName: String = "edge_sam_3x_decoder") {
        self.bundle = bundle
        self.encoderResourceName = encoderResourceName
        self.decoderResourceName = decoderResourceName
    }

    var isAvailable: Bool {
        get async { (try? await loadedModels()) != nil }
    }

    func encodeSource(_ imageData: Data) async throws -> SegmentationSourceToken {
        try Task.checkCancellation()
        let (encoder, _) = try await loadedModels()

        guard let decoded = UIImage(data: imageData) else { throw SegmentationError.encodingFailed }
        let upright = GarmentImageProcessing.normalizedOrientation(decoded)
        guard let cgImage = upright.cgImage,
              let prepared = EdgeSAMImageTensor.preprocessed(upright) else {
            throw SegmentationError.encodingFailed
        }
        try Task.checkCancellation()

        let input: MLFeatureProvider
        do {
            input = try MLDictionaryFeatureProvider(dictionary: ["image": prepared.tensor])
        } catch {
            throw SegmentationError.encodingFailed
        }

        let output: MLFeatureProvider
        do {
            output = try await Self.runPrediction(encoder, input: input)
        } catch {
            throw SegmentationError.encodingFailed
        }
        try Task.checkCancellation()

        guard let embedding = output.featureValue(for: "image_embeddings")?.multiArrayValue else {
            throw SegmentationError.encodingFailed
        }

        let token = SegmentationSourceToken(id: UUID())
        cachedToken = token
        cachedEmbedding = embedding
        cachedResizeMetadata = prepared.resizeMetadata
        cachedSourceImage = cgImage
        return token
    }

    func segment(region: NormalizedCropRect, in token: SegmentationSourceToken) async throws -> SegmentationMaskResult {
        try Task.checkCancellation()
        guard token == cachedToken,
              let embedding = cachedEmbedding,
              let resizeMetadata = cachedResizeMetadata,
              let sourceImage = cachedSourceImage else {
            // A token from a source that is no longer cached (superseded by
            // a later `encodeSource`, or never encoded by this instance at
            // all) — not a model failure, just nothing to decode against.
            throw SegmentationError.encodingFailed
        }
        let (_, decoder) = try await loadedModels()

        guard let prompt = EdgeSAMPromptTensor.boxPrompt(for: region, resizeMetadata: resizeMetadata) else {
            throw SegmentationError.decodingFailed
        }
        try Task.checkCancellation()

        let input: MLFeatureProvider
        do {
            input = try MLDictionaryFeatureProvider(dictionary: [
                "image_embeddings": embedding,
                "point_coords": prompt.coordinates,
                "point_labels": prompt.labels,
            ])
        } catch {
            throw SegmentationError.decodingFailed
        }

        let output: MLFeatureProvider
        do {
            output = try await Self.runPrediction(decoder, input: input)
        } catch {
            throw SegmentationError.decodingFailed
        }
        try Task.checkCancellation()

        guard let scores = output.featureValue(for: "scores")?.multiArrayValue,
              let masks = output.featureValue(for: "masks")?.multiArrayValue else {
            throw SegmentationError.decodingFailed
        }

        guard let converted = EdgeSAMMaskConversion.convert(
            masks: masks, scores: scores, resizeMetadata: resizeMetadata, sourceImage: sourceImage
        ) else {
            throw SegmentationError.maskConversionFailed
        }

        return SegmentationMaskResult(
            cutoutData: converted.cutoutData,
            boundingRegion: converted.boundingRegion,
            qualityScore: converted.qualityScore
        )
    }

    // MARK: - Model loading

    private func loadedModels() async throws -> (encoder: MLModel, decoder: MLModel) {
        switch loadState {
        case .loaded(let encoder, let decoder):
            return (encoder, decoder)
        case .unavailable:
            throw SegmentationError.modelUnavailable
        case .notLoaded:
            guard let encoderURL = bundle.url(forResource: encoderResourceName, withExtension: "mlmodelc"),
                  let decoderURL = bundle.url(forResource: decoderResourceName, withExtension: "mlmodelc") else {
                loadState = .unavailable
                throw SegmentationError.modelUnavailable
            }
            do {
                let configuration = MLModelConfiguration()
                configuration.computeUnits = .all
                let (encoder, decoder) = try await Self.loadModels(
                    encoderURL: encoderURL, decoderURL: decoderURL, configuration: configuration
                )
                loadState = .loaded(encoder: encoder, decoder: decoder)
                return (encoder, decoder)
            } catch {
                loadState = .unavailable
                throw SegmentationError.modelUnavailable
            }
        }
    }

    /// Off the actor's own executor and off the caller's thread: a cold
    /// `MLModel(contentsOf:configuration:)` load can take a noticeable
    /// fraction of a second, and this must never be the thing that makes
    /// the first AI mask attempt in a session feel like it froze the UI.
    private static func loadModels(
        encoderURL: URL, decoderURL: URL, configuration: MLModelConfiguration
    ) async throws -> (MLModel, MLModel) {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let encoder = try MLModel(contentsOf: encoderURL, configuration: configuration)
                    let decoder = try MLModel(contentsOf: decoderURL, configuration: configuration)
                    continuation.resume(returning: (encoder, decoder))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Runs one synchronous `prediction(from:)` call off the actor's own
    /// executor, for the same reason model loading is dispatched above.
    private static func runPrediction(_ model: MLModel, input: MLFeatureProvider) async throws -> MLFeatureProvider {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try model.prediction(from: input)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
