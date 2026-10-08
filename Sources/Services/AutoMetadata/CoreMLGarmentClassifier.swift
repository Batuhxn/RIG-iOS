import CoreML
import Foundation
import UIKit

/// Serializes model loading and inference off the main actor. The bundle must contain
/// a matched RIGGarmentEncoder.mlmodelc / RIGGarmentPrompts.json pair from the exporter.
/// Missing assets are a supported state; no fake classifier replaces them.
actor CoreMLGarmentClassifier: GarmentSemanticClassifying {
    typealias Manifest = GarmentPromptManifest

    private var loaded: (MLModel, Manifest)?
    private let bundle: Bundle

    init(bundle: Bundle = .main) { self.bundle = bundle }

    private func load() throws -> (MLModel, Manifest) {
        if let loaded { return loaded }
        guard let modelURL = bundle.url(forResource: "RIGGarmentEncoder", withExtension: "mlmodelc"),
              let promptURL = bundle.url(forResource: "RIGGarmentPrompts", withExtension: "json") else {
            throw AutoMetadataError.unavailable
        }
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: promptURL))
        guard manifest.version == 2, !(manifest.groups["flat"] ?? []).isEmpty,
              manifest.threshold > 0, manifest.threshold <= 1 else {
            throw AutoMetadataError.invalidContract
        }
        let config = MLModelConfiguration()
        config.computeUnits = .all
        let model = try MLModel(contentsOf: modelURL, configuration: config)
        let metadata = model.modelDescription.metadata[.creatorDefinedKey] as? [String: String]
        guard metadata?["rigModelID"] == manifest.modelID,
              let input = model.modelDescription.inputDescriptionsByName["image"]?.multiArrayConstraint,
              input.shape.map({ $0.intValue }) == [1, 3, 224, 224],
              model.modelDescription.outputDescriptionsByName["embedding"] != nil else {
            throw AutoMetadataError.invalidContract
        }
        loaded = (model, manifest)
        return (model, manifest)
    }

    /// The 89 MB encoder loads once per process; doing it when Add Item opens keeps the cold
    /// load (~1.3 s on the simulator proxy) off the first photo. A failure is retried on classify.
    func prewarm() async {
        _ = try? load()
    }

    func classify(cutout: Data) async throws -> AutoMetadataResult {
        let (vector, manifest) = try await embed(cutout)
        var result = GarmentEmbeddingDecision.decide(image: vector, manifest: manifest)
        result.identity = GarmentVisualIdentity(modelID: manifest.modelID, vector: vector.map(Float.init))
        if let identity = result.identity { remember(cutout, identity) }
        return result
    }

    private func embed(_ data: Data) async throws -> ([Double], Manifest) {
        try Task.checkCancellation()
        let (model, manifest) = try load()
        let input = try Self.tensor(data)
        let features = try MLDictionaryFeatureProvider(dictionary: ["image": MLFeatureValue(multiArray: input)])
        let prediction = try await model.prediction(from: features)
        try Task.checkCancellation()
        guard let output = prediction.featureValue(for: "embedding")?.multiArrayValue else {
            throw AutoMetadataError.invalidContract
        }
        return ((0..<output.count).map { output[$0].doubleValue }, manifest)
    }

    // The duplicate check at Save usually compares the very cutout that import analysis just
    // embedded; a few recent results spare that second inference.
    private var recent: [(data: Data, identity: GarmentVisualIdentity)] = []

    private func remember(_ data: Data, _ identity: GarmentVisualIdentity) {
        recent.removeAll { $0.data == data }
        recent.append((data, identity))
        if recent.count > 4 { recent.removeFirst() }
    }
}

extension CoreMLGarmentClassifier: GarmentIdentityProviding {
    func currentModelID() async -> String? {
        (try? load())?.1.modelID
    }

    func identity(for imageData: Data) async -> GarmentVisualIdentity? {
        if let hit = recent.first(where: { $0.data == imageData }) { return hit.identity }
        guard let embedded = try? await embed(imageData),
              let identity = GarmentVisualIdentity(modelID: embedded.1.modelID, vector: embedded.0.map(Float.init)) else {
            return nil
        }
        remember(imageData, identity)
        return identity
    }
}

extension CoreMLGarmentClassifier {

    /// Explicit export contract: white letterbox, 224 square, RGB CHW, CLIP mean/std.
    /// The same aspect-fit policy must be used by the offline evaluation harness.
    private static func tensor(_ data: Data) throws -> MLMultiArray {
        guard let source = UIImage(data: data) else { throw AutoMetadataError.invalidImage }
        let image = GarmentImageProcessing.normalizedOrientation(source)
        guard image.size.width > 0, image.size.height > 0 else { throw AutoMetadataError.invalidImage }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let square = UIGraphicsImageRenderer(size: CGSize(width: 224, height: 224), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 224, height: 224))
            let scale = min(224 / image.size.width, 224 / image.size.height)
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: CGRect(x: (224 - size.width) / 2, y: (224 - size.height) / 2, width: size.width, height: size.height))
        }
        guard let cg = square.cgImage, let space = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw AutoMetadataError.invalidImage
        }
        var pixels = [UInt8](repeating: 0, count: 224 * 224 * 4)
        let valid = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: 224, height: 224, bitsPerComponent: 8,
                bytesPerRow: 224 * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: 224, height: 224))
            return true
        }
        guard valid else { throw AutoMetadataError.invalidImage }
        let tensor = try MLMultiArray(shape: [1, 3, 224, 224], dataType: .float32)
        let mean = [0.48145466, 0.4578275, 0.40821073]
        let std = [0.26862954, 0.26130258, 0.27577711]
        for channel in 0..<3 {
            for pixel in 0..<(224 * 224) {
                tensor[channel * 224 * 224 + pixel] = NSNumber(value: (Double(pixels[pixel * 4 + channel]) / 255 - mean[channel]) / std[channel])
            }
        }
        return tensor
    }
}
