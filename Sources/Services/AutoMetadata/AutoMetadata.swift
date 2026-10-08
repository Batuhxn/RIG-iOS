import Foundation

enum GarmentLength: String, CaseIterable, Codable, Sendable {
    case mini, midi, maxi

    static func applies(category: GarmentCategory?, subtype: String) -> Bool {
        let kind = subtype.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return (category == .dress && kind == "dress") || (category == .bottom && kind == "skirt")
    }
}

struct MetadataSuggestion<Value: Codable & Hashable & Sendable>: Codable, Hashable, Sendable {
    let value: Value
    /// Softmax share for embedding suggestions; fraction of accepted mask pixels for
    /// pixel colours. Neither is a calibrated probability of correctness.
    let score: Double
}

struct AutoMetadataResult: Codable, Hashable, Sendable {
    var category: MetadataSuggestion<GarmentCategory>?
    var subtype: MetadataSuggestion<String>?
    var length: MetadataSuggestion<GarmentLength>?
    var primaryColor: MetadataSuggestion<ColorFamily>?
    var secondaryColor: MetadataSuggestion<ColorFamily>?
    var modelID: String?
    var semanticStatus: String = "unavailable"
    var elapsedMilliseconds: Double = 0
    /// The two likeliest kinds when none was confident enough to prefill.
    var subtypeAlternatives: [String]? = nil
    /// The garment's visual identity from the same inference. Kept in memory so it can be
    /// stored on the garment; deliberately not part of the persisted suggestion JSON.
    var identity: GarmentVisualIdentity? = nil

    private enum CodingKeys: String, CodingKey {
        case category, subtype, length, primaryColor, secondaryColor, modelID, semanticStatus
        case elapsedMilliseconds, subtypeAlternatives
    }
}

/// What makes a garment recognisable as itself: the encoder's unit-length image embedding,
/// tagged with the encoder that produced it. Embeddings from different encoders are never
/// compared; a model change makes stored identities stale and they are recomputed lazily.
struct GarmentVisualIdentity: Codable, Hashable, Sendable {
    let modelID: String
    let vector: [Float]

    init?(modelID: String, vector: [Float]) {
        let norm = vector.reduce(Float(0)) { $0 + $1 * $1 }.squareRoot()
        guard !modelID.isEmpty, !vector.isEmpty, norm.isFinite, norm > 1e-6 else { return nil }
        self.modelID = modelID
        self.vector = vector.map { $0 / norm }
    }

    /// Restores a stored identity; nil for missing, foreign or corrupt bytes.
    init?(modelID: String?, data: Data?) {
        guard let modelID, let data, !data.isEmpty, data.count % MemoryLayout<Float>.size == 0 else { return nil }
        let count = data.count / MemoryLayout<Float>.size
        // Stored bytes carry no alignment guarantee.
        let floats = data.withUnsafeBytes { raw in
            (0..<count).map { raw.loadUnaligned(fromByteOffset: $0 * MemoryLayout<Float>.size, as: Float.self) }
        }
        self.init(modelID: modelID, vector: floats)
    }

    /// Little-endian Float32, as every Apple platform stores it natively (~2 KB for 512-d).
    var data: Data { vector.withUnsafeBufferPointer { Data(buffer: $0) } }

    /// Cosine similarity; nil when the identities come from different encoders.
    func similarity(to other: GarmentVisualIdentity) -> Float? {
        guard modelID == other.modelID, vector.count == other.vector.count else { return nil }
        return zip(vector, other.vector).reduce(Float(0)) { $0 + $1.0 * $1.1 }
    }
}

/// Produces the visual identity of a garment image. Implementations must not throw:
/// nil means "no identity available" and must never block saving a garment.
protocol GarmentIdentityProviding: Sendable {
    func identity(for imageData: Data) async -> GarmentVisualIdentity?
    /// The model ID new identities carry, or nil when no encoder is available.
    func currentModelID() async -> String?
    /// The length of the vectors new identities carry, or nil when unknown.
    func currentDimension() async -> Int?
}

extension GarmentIdentityProviding {
    func currentDimension() async -> Int? { nil }
}

protocol GarmentMetadataAnalyzing: Sendable {
    func analyze(cutout: Data?) async -> AutoMetadataResult
    /// Loads model assets ahead of the first photo. Never throws; failure surfaces on analyze.
    func prewarm() async
}

protocol GarmentSemanticClassifying: Sendable {
    func classify(cutout: Data) async throws -> AutoMetadataResult
    func prewarm() async
}

extension GarmentMetadataAnalyzing {
    func prewarm() async {}
}

extension GarmentSemanticClassifying {
    func prewarm() async {}
}

enum AutoMetadataError: Error {
    case unavailable, invalidContract, invalidImage
}

struct UnavailableGarmentClassifier: GarmentSemanticClassifying {
    func classify(cutout: Data) async throws -> AutoMetadataResult {
        throw AutoMetadataError.unavailable
    }
}

/// Non-main-actor work; failure leaves all manual controls usable.
struct AutoMetadataService: GarmentMetadataAnalyzing {
    let classifier: any GarmentSemanticClassifying

    init(classifier: any GarmentSemanticClassifying = UnavailableGarmentClassifier()) {
        self.classifier = classifier
    }

    func prewarm() async {
        await classifier.prewarm()
    }

    func analyze(cutout: Data?) async -> AutoMetadataResult {
        let start = ProcessInfo.processInfo.systemUptime
        guard let cutout, !Task.isCancelled else { return AutoMetadataResult() }
        var result = AutoMetadataResult()
        if let colors = MaskedColorExtractor.extract(png: cutout) {
            result.primaryColor = colors.primary
            result.secondaryColor = colors.secondary
        }
        do {
            let semantic = try await classifier.classify(cutout: cutout)
            result.category = semantic.category
            result.subtype = semantic.subtype
            result.length = semantic.length
            result.subtypeAlternatives = semantic.subtypeAlternatives
            result.identity = semantic.identity
            result.modelID = semantic.modelID
            result.semanticStatus = semantic.semanticStatus
            // The embedding names colour under indoor light where pixel thresholds read
            // white as grey. The pixel secondary describes the pixel primary, so it is
            // kept only when both agree.
            if let semanticColor = semantic.primaryColor {
                if result.primaryColor?.value != semanticColor.value { result.secondaryColor = nil }
                result.primaryColor = semanticColor
            } else {
                // A working classifier explicitly abstained on colour. Do not
                // bypass its gate with the lower-precision pixel primary.
                result.primaryColor = nil
                result.secondaryColor = nil
            }
        } catch {
            result.semanticStatus = "unavailable"
        }
        result.elapsedMilliseconds = (ProcessInfo.processInfo.systemUptime - start) * 1000
        return result
    }
}

struct TextEmbedding: Codable, Hashable, Sendable {
    let label: String
    let vector: [Double]
}

enum EmbeddingRanking {
    static func unit(_ vector: [Double]) -> [Double]? {
        guard !vector.isEmpty, vector.allSatisfy({ $0.isFinite }) else { return nil }
        let norm = sqrt(vector.reduce(0) { $0 + $1 * $1 })
        guard norm.isFinite, norm > 1e-12 else { return nil }
        return vector.map { $0 / norm }
    }

    /// Provisional thresholds, to be tuned on validation data, never the held-out test set.
    static func best(image: [Double], candidates: [TextEmbedding], minimum: Double = 0.2,
                     margin: Double = 0.025) -> MetadataSuggestion<String>? {
        guard candidates.count >= 2, let image = unit(image) else { return nil }
        var scores: [(String, Double)] = []
        for candidate in candidates {
            guard candidate.vector.count == image.count, let text = unit(candidate.vector) else { return nil }
            scores.append((candidate.label, zip(image, text).reduce(0) { $0 + $1.0 * $1.1 }))
        }
        scores.sort { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 > $1.1 }
        guard let first = scores.first, first.1 >= minimum, first.1 - scores[1].1 >= margin else { return nil }
        return MetadataSuggestion(value: first.0, score: first.1)
    }
}
