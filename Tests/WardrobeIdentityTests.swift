import XCTest
@testable import RIG

final class WardrobeIdentityTests: XCTestCase {
    private func identity(_ v: [Float], model: String = "m1") -> GarmentVisualIdentity {
        guard let id = GarmentVisualIdentity(modelID: model, vector: v) else {
            XCTFail("invalid test vector")
            return GarmentVisualIdentity(modelID: "x", vector: [1])!  // unreachable after XCTFail
        }
        return id
    }

    func testIdentityIsUnitLengthAndRoundTripsThroughStoredBytes() throws {
        let original = identity([3, 4, 0])
        XCTAssertEqual(original.vector, [0.6, 0.8, 0])
        let restored = try XCTUnwrap(GarmentVisualIdentity(modelID: "m1", data: original.data))
        XCTAssertEqual(restored, original)
        XCTAssertEqual(original.data.count, 3 * MemoryLayout<Float>.size)
    }

    func testCorruptOrMissingStorageIsNotAnIdentity() {
        XCTAssertNil(GarmentVisualIdentity(modelID: nil, data: Data([0, 0, 128, 63])))
        XCTAssertNil(GarmentVisualIdentity(modelID: "m1", data: Data([1, 2, 3])))
        XCTAssertNil(GarmentVisualIdentity(modelID: "m1", data: Data()))
        XCTAssertNil(GarmentVisualIdentity(modelID: "m1", vector: [0, 0, 0]))
        XCTAssertNil(GarmentVisualIdentity(modelID: "", vector: [1, 0]))
    }

    func testIdentitiesFromDifferentEncodersAreNeverCompared() {
        XCTAssertNil(identity([1, 0], model: "a").similarity(to: identity([1, 0], model: "b")))
        XCTAssertEqual(identity([1, 0]).similarity(to: identity([1, 0])) ?? 0, 1, accuracy: 1e-6)
    }

    func testOnlyTheSingleBestMatchAboveThresholdIsReturned() {
        let candidate = identity([1, 0, 0])
        let near = UUID(), nearer = UUID(), far = UUID()
        let items = [(garmentID: near, identity: identity([0.9, 0.436, 0])),      // cos 0.90
                     (garmentID: nearer, identity: identity([0.95, 0.312, 0])),   // cos 0.95
                     (garmentID: far, identity: identity([0.5, 0.866, 0]))]       // cos 0.50
        let best = WardrobeIdentityMatching.best(candidate: candidate, among: items)
        XCTAssertEqual(best?.garmentID, nearer)
        XCTAssertNil(WardrobeIdentityMatching.best(candidate: candidate, among: [items[2]]))
    }

    func testThresholdIsTheProvisionalProductionValue() {
        XCTAssertEqual(WardrobeIdentityPolicy.threshold, 0.93)
        let candidate = identity([1, 0])
        let justBelow = identity([0.925, (1 - 0.925 * 0.925).squareRoot()])
        let justAbove = identity([0.935, (1 - 0.935 * 0.935).squareRoot()])
        XCTAssertNil(WardrobeIdentityMatching.best(candidate: candidate, among: [(UUID(), justBelow)]))
        XCTAssertNotNil(WardrobeIdentityMatching.best(candidate: candidate, among: [(UUID(), justAbove)]))
    }

    private actor FakeProvider: GarmentIdentityProviding {
        var answers: [Data: GarmentVisualIdentity] = [:]
        var calls: [Data] = []
        init(_ answers: [Data: GarmentVisualIdentity]) { self.answers = answers }
        func identity(for imageData: Data) async -> GarmentVisualIdentity? {
            calls.append(imageData)
            return answers[imageData]
        }
    }

    func testMatcherUsesStoredIdentitiesAndEmbedsOnlyOlderItems() async {
        let candidatePhoto = Data([1]), oldPhoto = Data([2])
        let stored = UUID(), old = UUID()
        let provider = FakeProvider([candidatePhoto: identity([1, 0]), oldPhoto: identity([0.99, 0.141])])
        let matcher = EmbeddingSimilarityMatcher(provider: provider)
        let items = [
            WardrobeSimilarityCandidateItem(garmentID: stored, category: .top, imageData: Data(),
                                            identity: identity([0.2, 0.98])),
            WardrobeSimilarityCandidateItem(garmentID: old, category: .top, imageData: oldPhoto),
        ]
        let matches = await matcher.rankSimilarItems(to: candidatePhoto, among: items)
        XCTAssertEqual(matches.map(\.garmentID), [old])
        let calls = await provider.calls
        XCTAssertEqual(calls, [candidatePhoto, oldPhoto], "stored identities must not trigger inference")
    }

    func testMatcherWithoutAnIdentitySuggestsNothing() async {
        let matcher = EmbeddingSimilarityMatcher(provider: FakeProvider([:]))
        let items = [WardrobeSimilarityCandidateItem(garmentID: UUID(), category: .top, imageData: Data([9]),
                                                     identity: identity([1, 0]))]
        let matches = await matcher.rankSimilarItems(to: Data([1]), among: items)
        XCTAssertTrue(matches.isEmpty)
    }

    func testIdentityStaysOutOfThePersistedSuggestionJSON() throws {
        var result = AutoMetadataResult(semanticStatus: "suggested")
        result.identity = identity([1, 0])
        let json = try XCTUnwrap(String(data: JSONEncoder().encode(result), encoding: .utf8))
        XCTAssertFalse(json.contains("identity"))
        XCTAssertFalse(json.contains("vector"))
    }
}
