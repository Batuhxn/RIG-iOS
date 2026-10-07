import Foundation

/// Prompt manifest v2, produced next to the encoder by the exporter
/// (AutoMetadataBench/scripts/export_fashionclip.py). Text vectors are prompt-ensemble
/// means, so the app never needs a text encoder.
///
/// Groups:
/// - `flat`: one entry per `category/subtype` label, e.g. `bottom/skirt`.
/// - `length.bottom`, `length.dress`: mini / midi / maxi.
/// - `color`: one entry per `ColorFamily` raw value the model can see (never multicolor).
struct GarmentPromptManifest: Codable, Sendable {
    let version: Int
    let modelID: String
    let logitScale: Double
    let threshold: Double
    let groups: [String: [TextEmbedding]]
}

/// Turns one image embedding into suggestions. Foundation-only so it is unit-testable
/// off-device and can be checked against the offline benchmark on the same embeddings.
///
/// Measured on 294 verified catalogue cutouts + 17 phone photos (FashionCLIP, 8-bit):
/// a flat softmax over all subtypes, with category probability summed over its subtypes,
/// beat per-level raw-cosine margins by a wide margin, which abstained on most garments.
enum GarmentEmbeddingDecision {
    struct Ranked: Hashable, Sendable {
        let label: String
        let probability: Double
    }

    /// Softmax over scaled cosine similarities. Probabilities are a ranking device,
    /// not a calibrated chance of being right.
    static func softmax(image: [Double], candidates: [TextEmbedding], logitScale: Double) -> [Ranked]? {
        guard !candidates.isEmpty, logitScale.isFinite, let image = EmbeddingRanking.unit(image) else { return nil }
        var logits: [(label: String, value: Double)] = []
        for candidate in candidates {
            guard candidate.vector.count == image.count, let text = EmbeddingRanking.unit(candidate.vector) else { return nil }
            logits.append((candidate.label, logitScale * zip(image, text).reduce(0) { $0 + $1.0 * $1.1 }))
        }
        guard let maximum = logits.map(\.value).max() else { return nil }
        let exps = logits.map { ($0.label, exp($0.value - maximum)) }
        let total = exps.reduce(0) { $0 + $1.1 }
        guard total.isFinite, total > 0 else { return nil }
        return exps.map { Ranked(label: $0.0, probability: $0.1 / total) }
            .sorted { $0.probability == $1.probability ? $0.label < $1.label : $0.probability > $1.probability }
    }

    static func decide(image: [Double], manifest: GarmentPromptManifest) -> AutoMetadataResult {
        var result = AutoMetadataResult(modelID: manifest.modelID, semanticStatus: "abstained")
        let threshold = manifest.threshold
        if let colors = softmax(image: image, candidates: manifest.groups["color"] ?? [], logitScale: manifest.logitScale),
           let best = colors.first, best.probability >= threshold, let family = ColorFamily(rawValue: best.label) {
            result.primaryColor = MetadataSuggestion(value: family, score: best.probability)
        }
        guard let flat = softmax(image: image, candidates: manifest.groups["flat"] ?? [], logitScale: manifest.logitScale) else {
            return result
        }
        var categoryProbability: [String: Double] = [:]
        var categoryOrder: [String] = []
        for entry in flat {
            let key = Self.categoryPart(entry.label)
            if categoryProbability[key] == nil { categoryOrder.append(key) }
            categoryProbability[key, default: 0] += entry.probability
        }
        // Ties resolve to the category whose best subtype ranked first.
        guard let categoryKey = categoryOrder.max(by: { categoryProbability[$0, default: 0] < categoryProbability[$1, default: 0] }),
              let pCategory = categoryProbability[categoryKey], pCategory > 0,
              let category = GarmentCategory(rawValue: categoryKey) else { return result }
        let within = flat.filter { Self.categoryPart($0.label) == categoryKey }
            .map { Ranked(label: Self.subtypePart($0.label), probability: $0.probability / pCategory) }
        guard pCategory >= threshold else { return result }
        result.category = MetadataSuggestion(value: category, score: pCategory)
        result.semanticStatus = "suggested"
        // A bag's kind adds nothing the category does not already say.
        guard category != .bag, let top = within.first else { return result }
        if top.probability >= threshold {
            result.subtype = MetadataSuggestion(value: top.label, score: top.probability)
        } else if within.count >= 2 {
            result.subtypeAlternatives = Array(within.prefix(2).map(\.label))
            return result
        }
        if let subtype = result.subtype, GarmentLength.applies(category: category, subtype: subtype.value),
           let lengths = softmax(image: image, candidates: manifest.groups["length.\(category.rawValue)"] ?? [],
                                 logitScale: manifest.logitScale),
           let best = lengths.first, best.probability >= threshold, let length = GarmentLength(rawValue: best.label) {
            result.length = MetadataSuggestion(value: length, score: best.probability)
        }
        return result
    }

    static func categoryPart(_ label: String) -> String {
        String(label.split(separator: "/", maxSplits: 1).first ?? "")
    }

    static func subtypePart(_ label: String) -> String {
        let parts = label.split(separator: "/", maxSplits: 1)
        return parts.count == 2 ? String(parts[1]) : ""
    }
}
