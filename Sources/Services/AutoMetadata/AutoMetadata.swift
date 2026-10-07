import Foundation

enum GarmentLength: String, CaseIterable, Codable, Sendable {
    case mini, midi, maxi

    static func applies(category: GarmentCategory?, subtype: String) -> Bool {
        (category == .dress && subtype.lowercased() == "dress") || (category == .bottom && subtype.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "skirt")
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
}

protocol GarmentMetadataAnalyzing: Sendable {
    func analyze(cutout: Data?) async -> AutoMetadataResult
}

protocol GarmentSemanticClassifying: Sendable {
    func classify(cutout: Data) async throws -> AutoMetadataResult
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
            result.modelID = semantic.modelID
            result.semanticStatus = semantic.semanticStatus
            // The embedding names colour under indoor light where pixel thresholds read
            // white as grey. The pixel secondary describes the pixel primary, so it is
            // kept only when both agree.
            if let semanticColor = semantic.primaryColor {
                if result.primaryColor?.value != semanticColor.value { result.secondaryColor = nil }
                result.primaryColor = semanticColor
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
