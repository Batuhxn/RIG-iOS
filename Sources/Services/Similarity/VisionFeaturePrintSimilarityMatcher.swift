import Foundation
import UIKit
import Vision

/// On-device visual similarity via Vision's image feature prints.
///
/// `VNGenerateImageFeaturePrintRequest` is the smallest Apple-native
/// mechanism available on the iOS 17 floor for "how visually alike are these
/// two images" — no bundled model, no third-party dependency, entirely
/// on-device, under the same constraint `VisionBackgroundRemover` already
/// ships behind. It answers visual similarity, not semantic identity: two
/// different grey crewnecks can score as similar as two photos of the same
/// shirt. That is the whole reason a result is ever presented as "possible
/// match" and never as "duplicate" — see `SimilarityBand`.
///
/// UNVERIFIED: like `VisionBackgroundRemover`, this has never executed. It
/// was written on a Windows host with no Apple runtime available. The API
/// shape is exactly as Apple documents `VNGenerateImageFeaturePrintRequest`
/// and `VNFeaturePrintObservation.computeDistance(_:to:)`; behaviour on real
/// garment photographs, and whether `SimilarityThresholds.conservativeDefault`
/// bands them usefully, still needs a device run.
struct VisionFeaturePrintSimilarityMatcher: GarmentSimilarityMatching {
    func rankSimilarItems(
        to candidateImageData: Data,
        among items: [WardrobeSimilarityCandidateItem],
        thresholds: SimilarityThresholds
    ) async -> [WardrobeSimilarityMatch] {
        // Non-fatal by contract at every exit: a missing observation, a
        // distance Vision refuses to compute, or an empty wardrobe all end
        // the same way — nothing surfaced, nothing thrown.
        guard let candidateObservation = Self.featurePrint(for: candidateImageData) else {
            return []
        }

        var distances: [(garmentID: UUID, distance: Float)] = []
        for item in items {
            guard let itemObservation = Self.featurePrint(for: item.imageData) else { continue }
            var distance: Float = .greatestFiniteMagnitude
            do {
                try candidateObservation.computeDistance(&distance, to: itemObservation)
            } catch {
                continue
            }
            distances.append((garmentID: item.garmentID, distance: distance))
        }

        return WardrobeSimilarityRanking.rank(distances: distances, thresholds: thresholds)
    }

    private static func featurePrint(for imageData: Data) -> VNFeaturePrintObservation? {
        guard let cgImage = UIImage(data: imageData)?.cgImage else { return nil }
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let request = VNGenerateImageFeaturePrintRequest()
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        return request.results?.first as? VNFeaturePrintObservation
    }
}
