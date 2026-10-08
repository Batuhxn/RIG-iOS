import Foundation
import XCTest
@testable import RIG

final class GarmentDuplicateCheckTests: XCTestCase {
    private actor RecordingMatcher: GarmentSimilarityMatching {
        let answer: [WardrobeSimilarityMatch]
        let modelID: String?
        let dimension: Int?
        private(set) var candidate: Data?
        private(set) var compared: [WardrobeSimilarityCandidateItem] = []

        init(answer: [WardrobeSimilarityMatch] = [], modelID: String? = nil, dimension: Int? = nil) {
            self.answer = answer
            self.modelID = modelID
            self.dimension = dimension
        }

        func identityModelID() async -> String? { modelID }
        func identityDimension() async -> Int? { dimension }

        func rankSimilarItems(
            to candidateImageData: Data,
            among items: [WardrobeSimilarityCandidateItem],
            thresholds: SimilarityThresholds
        ) async -> [WardrobeSimilarityMatch] {
            candidate = candidateImageData
            compared = items
            return answer
        }

        func observation() -> (Data?, [WardrobeSimilarityCandidateItem]) {
            (candidate, compared)
        }
    }

    private func store() throws -> GarmentImageStore {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "RIGDuplicateCheck-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return GarmentImageStore(baseDirectory: url)
    }

    private func result(_ id: UUID, store: GarmentImageStore, cutout: Bool = true) throws -> GarmentImportResult {
        let original = try store.write(Data([1]), for: id, kind: .original)
        let cutoutPath = cutout ? try store.write(Data([2]), for: id, kind: .cutout) : nil
        return GarmentImportResult(
            garmentID: id,
            originalRelativePath: original,
            cutoutRelativePath: cutoutPath,
            thumbnailRelativePath: original,
            isBackgroundRemoved: cutout,
            backgroundRemovalMessage: cutout ? nil : "Vision failed"
        )
    }

    private func source(_ id: UUID, category: GarmentCategory, store: GarmentImageStore) throws -> GarmentDuplicateSource {
        GarmentDuplicateSource(
            garmentID: id,
            category: category,
            imagePath: try store.write(Data([3]), for: id, kind: .original)
        )
    }

    func testSingleNoMatchProceedsToSave() async throws {
        let store = try store()
        let candidate = try result(UUID(), store: store)
        let existing = try source(UUID(), category: .top, store: store)
        let matcher = RecordingMatcher()
        let outcome = await GarmentDuplicateCheck.evaluate(
            result: candidate, choice: .original, category: .top,
            sources: [existing], store: store, matcher: matcher
        )
        XCTAssertEqual(outcome, .save)
        let observed = await matcher.observation()
        XCTAssertEqual(observed.0, Data([2]), "matching uses the cutout, the identity image")
        XCTAssertEqual(observed.1.map(\.garmentID), [existing.garmentID])
    }

    func testBulkNoMatchProceedsToSaveWithSelectedCutout() async throws {
        let store = try store()
        let candidate = try result(UUID(), store: store)
        let matcher = RecordingMatcher()
        let outcome = await GarmentDuplicateCheck.evaluate(
            result: candidate, choice: .cutout, category: .top,
            sources: [], store: store, matcher: matcher
        )
        XCTAssertEqual(outcome, .save)
        let observed = await matcher.observation()
        XCTAssertEqual(observed.0, Data([2]))
    }

    /// Codex v0.4 review, P2: choosing "Original" used to compare the original's embedding with
    /// stored identities computed from cutouts. The identity image no longer follows the choice.
    func testImageChoiceDoesNotChangeTheIdentityImage() async throws {
        let store = try store()
        let candidate = try result(UUID(), store: store)
        let originalMatcher = RecordingMatcher()
        let cutoutMatcher = RecordingMatcher()
        _ = await GarmentDuplicateCheck.evaluate(
            result: candidate, choice: .original, category: .top,
            sources: [], store: store, matcher: originalMatcher
        )
        _ = await GarmentDuplicateCheck.evaluate(
            result: candidate, choice: .cutout, category: .top,
            sources: [], store: store, matcher: cutoutMatcher
        )
        let original = await originalMatcher.observation()
        let cutout = await cutoutMatcher.observation()
        XCTAssertEqual(original.0, Data([2]))
        XCTAssertEqual(cutout.0, Data([2]))
    }

    /// Codex v0.4 review, P2: a stored identity of the wrong length, tagged with the current
    /// model, used to count as current, so its photo was never read and it never matched again.
    func testTruncatedStoredIdentityIsReembeddedFromItsPhoto() async throws {
        let store = try store()
        let candidate = try result(UUID(), store: store)
        var truncated = try source(UUID(), category: .top, store: store)
        truncated.identity = GarmentVisualIdentity(modelID: "m1", vector: [1])
        var whole = try source(UUID(), category: .top, store: store)
        whole.identity = GarmentVisualIdentity(modelID: "m1", vector: [1, 0])
        let matcher = RecordingMatcher(modelID: "m1", dimension: 2)
        _ = await GarmentDuplicateCheck.evaluateReportingIdentities(
            result: candidate, choice: .cutout, category: .top,
            sources: [truncated, whole], store: store, matcher: matcher
        )
        let observed = await matcher.observation()
        let byID = Dictionary(uniqueKeysWithValues: observed.1.map { ($0.garmentID, $0) })
        XCTAssertEqual(byID[truncated.garmentID]?.imageData, Data([3]), "a truncated identity sends its photo")
        XCTAssertEqual(byID[whole.garmentID]?.imageData, Data(), "a whole identity still needs no photo")
    }

    func testMatchPresentsTheExistingComparison() async throws {
        let store = try store()
        let candidate = try result(UUID(), store: store)
        let existing = try source(UUID(), category: .top, store: store)
        let match = WardrobeSimilarityMatch(
            garmentID: existing.garmentID, band: .verySimilar, distance: 0.1
        )
        let outcome = await GarmentDuplicateCheck.evaluate(
            result: candidate, choice: .original, category: .top,
            sources: [existing], store: store, matcher: RecordingMatcher(answer: [match])
        )
        guard case .review(let data, let review) = outcome else {
            return XCTFail("A meaningful match must open duplicate review")
        }
        XCTAssertEqual(data, Data([1]))
        XCTAssertEqual(review.current?.garmentID, existing.garmentID)
    }

    func testOnlySameCategoryExistingItemsAreCompared() async throws {
        let store = try store()
        let candidate = try result(UUID(), store: store)
        let same = try source(UUID(), category: .top, store: store)
        let other = try source(UUID(), category: .bottom, store: store)
        let selfSource = GarmentDuplicateSource(
            garmentID: candidate.garmentID,
            category: .top,
            imagePath: candidate.originalRelativePath
        )
        let matcher = RecordingMatcher()
        _ = await GarmentDuplicateCheck.evaluate(
            result: candidate, choice: .original, category: .top,
            sources: [same, other, selfSource], store: store, matcher: matcher
        )
        let observed = await matcher.observation()
        XCTAssertEqual(observed.1.map(\.garmentID), [same.garmentID])
    }

    func testVisionFailureFallsBackToOriginalAndRemainsSaveable() async throws {
        let store = try store()
        let candidate = try result(UUID(), store: store, cutout: false)
        // The matcher returning no suggestions is the contract for an
        // internal Vision feature-print failure.
        let matcher = RecordingMatcher()
        let outcome = await GarmentDuplicateCheck.evaluate(
            result: candidate, choice: .cutout, category: .top,
            sources: [], store: store, matcher: matcher
        )
        XCTAssertEqual(outcome, .save)
        let observed = await matcher.observation()
        XCTAssertEqual(observed.0, Data([1]))
    }

    func testMatcherFailureLeavesBothImageChoicesSaveable() async throws {
        let store = try store()
        let candidate = try result(UUID(), store: store)
        let existing = try source(UUID(), category: .top, store: store)
        for choice in [GarmentImageChoice.original, .cutout] {
            // Vision's no-observation/error path returns [] by contract.
            let outcome = await GarmentDuplicateCheck.evaluate(
                result: candidate, choice: choice, category: .top,
                sources: [existing], store: store,
                matcher: PassthroughSimilarityMatcher()
            )
            XCTAssertEqual(outcome, .save)
        }
    }

    func testMissingCandidateImageDoesNotBlockTheSave() async throws {
        let store = try store()
        let candidate = try result(UUID(), store: store)
        try store.removeAll(for: candidate.garmentID)
        let matcher = RecordingMatcher()
        let outcome = await GarmentDuplicateCheck.evaluate(
            result: candidate, choice: .original, category: .top,
            sources: [], store: store, matcher: matcher
        )
        XCTAssertEqual(outcome, .save)
        let observed = await matcher.observation()
        XCTAssertNil(observed.0)
    }

    func testPhotosAreReadOnlyForGarmentsWithoutACurrentIdentity() async throws {
        let store = try store()
        let candidate = try result(UUID(), store: store)
        var current = try source(UUID(), category: .top, store: store)
        current.identity = GarmentVisualIdentity(modelID: "m1", vector: [1, 0])
        var stale = try source(UUID(), category: .top, store: store)
        stale.identity = GarmentVisualIdentity(modelID: "m0", vector: [1, 0])
        let missing = try source(UUID(), category: .top, store: store)
        let matcher = RecordingMatcher(modelID: "m1")
        _ = await GarmentDuplicateCheck.evaluateReportingIdentities(
            result: candidate, choice: .original, category: .top,
            sources: [current, stale, missing], store: store, matcher: matcher
        )
        let compared = await matcher.observation().1
        let photoBytes = Dictionary(uniqueKeysWithValues: compared.map { ($0.garmentID, $0.imageData.count) })
        XCTAssertEqual(photoBytes[current.garmentID], 0)
        XCTAssertEqual(photoBytes[stale.garmentID], 1)
        XCTAssertEqual(photoBytes[missing.garmentID], 1)
    }
}
