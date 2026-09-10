import XCTest
@testable import RIG

final class CandidateGeneratorTests: XCTestCase {
    func testEveryCandidateIsStructurallyValid() {
        let candidates = CandidateGenerator().candidates(from: Fixture.smallWardrobe())
        XCTAssertFalse(candidates.isEmpty)
        for candidate in candidates {
            XCTAssertTrue(
                OutfitValidator.isValid(candidate.items),
                "Invalid candidate emitted: \(candidate.items.map(\.displayName))"
            )
        }
    }

    func testNoDuplicateCombinations() {
        let candidates = CandidateGenerator().candidates(from: Fixture.largeWardrobe())
        let signatures = Set(candidates.map(\.signature))
        XCTAssertEqual(signatures.count, candidates.count)
    }

    func testCandidateCapIsRespected() {
        let configuration = OutfitEngineConfiguration.default
        let candidates = CandidateGenerator(configuration: configuration)
            .candidates(from: Fixture.largeWardrobe())
        XCTAssertLessThanOrEqual(candidates.count, configuration.maximumEvaluatedCandidates)
        XCTAssertEqual(candidates.count, configuration.maximumEvaluatedCandidates,
                       "A wardrobe this size should saturate the cap")
    }

    func testLowerCapIsAlsoRespected() {
        var configuration = OutfitEngineConfiguration.default
        configuration.maximumEvaluatedCandidates = 17
        let candidates = CandidateGenerator(configuration: configuration)
            .candidates(from: Fixture.largeWardrobe())
        XCTAssertEqual(candidates.count, 17)
    }

    func testGenerationIsDeterministic() {
        let wardrobe = Fixture.largeWardrobe()
        let generator = CandidateGenerator()
        let first = generator.candidates(from: wardrobe).map(\.signature)
        let second = generator.candidates(from: wardrobe).map(\.signature)
        XCTAssertEqual(first, second)
    }

    func testGenerationIsIndependentOfWardrobeOrder() {
        let wardrobe = Fixture.smallWardrobe()
        let generator = CandidateGenerator()
        let forward = Set(generator.candidates(from: wardrobe).map(\.signature))
        let reversed = Set(generator.candidates(from: wardrobe.reversed()).map(\.signature))
        XCTAssertEqual(forward, reversed)
    }

    func testDressProducesItsOwnBase() {
        let wardrobe = [Fixture.garment(1, .dress), Fixture.garment(2, .shoes)]
        let candidates = CandidateGenerator().candidates(from: wardrobe)
        XCTAssertFalse(candidates.isEmpty)
        XCTAssertTrue(candidates.allSatisfy { $0.contains(.dress) })
        XCTAssertTrue(candidates.allSatisfy { !$0.contains(.top) && !$0.contains(.bottom) })
    }

    func testWardrobeWithoutABaseProducesNothing() {
        let wardrobe = [
            Fixture.garment(1, .accessory),
            Fixture.garment(2, .bag),
            Fixture.garment(3, .shoes)
        ]
        XCTAssertTrue(CandidateGenerator().candidates(from: wardrobe).isEmpty)
    }

    func testTopWithoutBottomProducesNothing() {
        let wardrobe = [Fixture.garment(1, .top), Fixture.garment(2, .shoes)]
        XCTAssertTrue(CandidateGenerator().candidates(from: wardrobe).isEmpty)
    }

    func testBaseCombinationCapLimitsPairings() {
        var configuration = OutfitEngineConfiguration.default
        configuration.maximumBaseCombinations = 5
        configuration.shoeFanout = 0
        configuration.outerwearFanout = 0
        configuration.accessoryFanout = 0
        let candidates = CandidateGenerator(configuration: configuration)
            .candidates(from: Fixture.largeWardrobe())
        XCTAssertEqual(candidates.count, 5)
    }

    func testPlainBasesComeBeforeDecoratedVariants() {
        let candidates = CandidateGenerator().candidates(from: Fixture.smallWardrobe())
        let firstDecoratedIndex = candidates.firstIndex { $0.items.count > 2 } ?? candidates.count
        let plainCount = candidates.prefix(firstDecoratedIndex).count
        XCTAssertGreaterThan(plainCount, 1, "Generation should sweep bases before decorating any of them")
    }
}
