import XCTest
@testable import RIG

final class GarmentEmbeddingDecisionTests: XCTestCase {
    private func entries(_ pairs: [(String, [Double])]) -> [TextEmbedding] {
        pairs.map { TextEmbedding(label: $0.0, vector: $0.1) }
    }

    private func manifest(_ groups: [String: [(String, [Double])]], scale: Double = 100,
                          threshold: Double = 0.7) -> GarmentPromptManifest {
        GarmentPromptManifest(version: 2, modelID: "test", logitScale: scale, threshold: threshold,
                              groups: groups.mapValues(entries))
    }

    func testSoftmaxIsNormalisedAndRanked() throws {
        let ranked = try XCTUnwrap(GarmentEmbeddingDecision.softmax(
            image: [1, 0.2, 0], candidates: entries([("a", [0, 1, 0]), ("b", [1, 0, 0])]), logitScale: 10))
        XCTAssertEqual(ranked.map(\.label), ["b", "a"])
        XCTAssertEqual(ranked.reduce(0) { $0 + $1.probability }, 1, accuracy: 1e-9)
    }

    func testCategorySumsAcrossItsSubtypes() {
        // Three equally likely kinds: no single kind wins, but two of three are tops.
        let m = manifest(["flat": [("top/t-shirt", [1, 0, 0]), ("top/shirt", [1, 0, 0]), ("bottom/skirt", [0, 1, 0])]],
                         scale: 1, threshold: 0.6)
        let result = GarmentEmbeddingDecision.decide(image: [1, 1, 0], manifest: m)
        XCTAssertEqual(result.category?.value, .top)
        XCTAssertNil(result.subtype, "an even split between kinds must not be prefilled")
        XCTAssertEqual(result.subtypeAlternatives, ["shirt", "t-shirt"])
        XCTAssertEqual(result.semanticStatus, "suggested")
    }

    func testUncertainCategoryAbstainsEntirely() {
        let m = manifest(["flat": [("top/t-shirt", [1, 0, 0]), ("bottom/skirt", [0, 1, 0])]], scale: 1)
        let result = GarmentEmbeddingDecision.decide(image: [1, 1, 0], manifest: m)
        XCTAssertNil(result.category)
        XCTAssertNil(result.subtype)
        XCTAssertNil(result.subtypeAlternatives)
        XCTAssertEqual(result.semanticStatus, "abstained")
    }

    func testDressReceivesKindAndLength() {
        let m = manifest(["flat": [("dress/dress", [1, 0, 0]), ("top/t-shirt", [0, 1, 0])],
                          "length.dress": [("mini", [1, 0, 0]), ("maxi", [0, 0, 1])]])
        let result = GarmentEmbeddingDecision.decide(image: [1, 0.05, 0], manifest: m)
        XCTAssertEqual(result.category?.value, .dress)
        XCTAssertEqual(result.subtype?.value, "dress")
        XCTAssertEqual(result.length?.value, .mini)
    }

    func testLengthNeverAttachesToTrousers() {
        let m = manifest(["flat": [("bottom/trousers", [1, 0, 0]), ("bottom/skirt", [0, 1, 0])],
                          "length.bottom": [("mini", [1, 0, 0]), ("maxi", [0, 0, 1])]])
        let result = GarmentEmbeddingDecision.decide(image: [1, 0, 0], manifest: m)
        XCTAssertEqual(result.subtype?.value, "trousers")
        XCTAssertNil(result.length)
    }

    func testBagCategoryHasNoRedundantKind() {
        let m = manifest(["flat": [("bag/bag", [1, 0, 0]), ("shoes/boots", [0, 1, 0])]])
        let result = GarmentEmbeddingDecision.decide(image: [1, 0, 0], manifest: m)
        XCTAssertEqual(result.category?.value, .bag)
        XCTAssertNil(result.subtype)
    }

    func testColourIsSuggestedOnlyWhenConfident() {
        let colours: [(String, [Double])] = [("black", [1, 0, 0]), ("navy", [0, 1, 0])]
        let confident = GarmentEmbeddingDecision.decide(image: [1, 0, 0], manifest: manifest(["color": colours]))
        XCTAssertEqual(confident.primaryColor?.value, .black)
        let torn = GarmentEmbeddingDecision.decide(image: [1, 1, 0], manifest: manifest(["color": colours]))
        XCTAssertNil(torn.primaryColor, "black versus navy at even odds must be left to the user")
    }

    func testAmbiguousColourPairNeedsAStricterBar() {
        // 3-d toy space: black and navy close together, red far away.
        let colours: [(String, [Double])] = [("black", [1, 0, 0]), ("navy", [0.995, 0.0999, 0]), ("red", [0, 0, 1])]
        // Clearly black but navy is the runner-up at ~0.9: prefilled under the plain gate, not here.
        let m = manifest(["color": colours], scale: 100, threshold: 0.7)
        let torn = GarmentEmbeddingDecision.decide(image: [1, -0.12, 0], manifest: m)
        XCTAssertNil(torn.primaryColor, "black/navy below 0.95 is left to the user")
        let sure = GarmentEmbeddingDecision.decide(image: [1, -0.5, 0], manifest: m)
        XCTAssertEqual(sure.primaryColor?.value, .black)
        // A non-ambiguous runner-up keeps the ordinary 0.7 gate.
        let other = manifest(["color": [("black", [1, 0, 0]), ("red", [0.995, 0.0999, 0])]], scale: 100, threshold: 0.7)
        XCTAssertEqual(GarmentEmbeddingDecision.decide(image: [1, -0.12, 0], manifest: other).primaryColor?.value, .black)
    }

    func testMismatchedVectorsAbstainInsteadOfCrashing() {
        let m = manifest(["flat": [("top/t-shirt", [1, 0]), ("bottom/skirt", [0, 1, 0])],
                          "color": [("black", [1])]])
        let result = GarmentEmbeddingDecision.decide(image: [1, 0, 0], manifest: m)
        XCTAssertNil(result.category)
        XCTAssertNil(result.primaryColor)
        XCTAssertNil(GarmentEmbeddingDecision.decide(image: [.nan, 0, 0], manifest: m).category)
    }

    func testUnknownLabelsAreIgnoredRatherThanInvented() {
        let m = manifest(["flat": [("hat-rack/thing", [1, 0, 0]), ("top/t-shirt", [0, 1, 0])],
                          "color": [("ultraviolet", [1, 0, 0]), ("black", [0, 1, 0])]])
        let result = GarmentEmbeddingDecision.decide(image: [1, 0, 0], manifest: m)
        XCTAssertNil(result.category)
        XCTAssertNil(result.primaryColor)
    }

    func testOlderStoredResultsStillDecode() throws {
        let legacy = #"{"semanticStatus":"suggested","elapsedMilliseconds":12,"category":{"value":"top","score":0.9}}"#
        let decoded = try JSONDecoder().decode(AutoMetadataResult.self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded.category?.value, .top)
        XCTAssertNil(decoded.subtypeAlternatives)
    }
}
