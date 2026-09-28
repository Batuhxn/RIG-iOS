import XCTest
@testable import RIG

final class CandidateGeneratorTests: XCTestCase {
    private func categorySets(_ categories: [GarmentCategory]) -> Set<Set<GarmentCategory>> {
        let wardrobe = categories.enumerated().map { Fixture.garment($0.offset + 1, $0.element) }
        let candidates = CandidateGenerator().candidates(from: wardrobe)
        XCTAssertTrue(candidates.allSatisfy { OutfitValidator.isValid($0.items) })
        XCTAssertEqual(Set(candidates.map(\.signature)).count, candidates.count)
        return Set(candidates.map { Set($0.items.map(\.category)) })
    }

    func testTopAndBottomProduceAValidBareBase() {
        XCTAssertEqual(categorySets([.top, .bottom]), [Set([.top, .bottom])])
    }

    func testOuterwearIsAvailableWithoutShoes() {
        XCTAssertEqual(
            categorySets([.top, .bottom, .outerwear]),
            [Set([.top, .bottom]), Set([.top, .bottom, .outerwear])]
        )
    }

    func testShoesRemainOptional() {
        XCTAssertEqual(
            categorySets([.top, .bottom, .shoes]),
            [Set([.top, .bottom]), Set([.top, .bottom, .shoes])]
        )
    }

    func testSmallWardrobeOffersIndependentAndCombinedOptionalPieces() {
        XCTAssertEqual(
            categorySets([.top, .bottom, .shoes, .outerwear]),
            [
                Set([.top, .bottom]), Set([.top, .bottom, .shoes]),
                Set([.top, .bottom, .outerwear]), Set([.top, .bottom, .shoes, .outerwear]),
            ]
        )
    }

    func testBagAndAccessoryCanEachAppearWithoutShoesOrOuterwear() {
        for extra in [GarmentCategory.bag, .accessory] {
            XCTAssertEqual(
                categorySets([.top, .bottom, extra]),
                [Set([.top, .bottom]), Set([.top, .bottom, extra])]
            )
        }
    }

    func testOuterwearAndExtraCanCombineWithoutShoes() {
        XCTAssertTrue(categorySets([.top, .bottom, .outerwear, .bag])
            .contains(Set([.top, .bottom, .outerwear, .bag])))
    }

    func testDressAloneRemainsValid() {
        XCTAssertEqual(categorySets([.dress]), [Set([.dress])])
    }

    func testDressCanAddShoesIndependently() {
        XCTAssertEqual(categorySets([.dress, .shoes]), [Set([.dress]), Set([.dress, .shoes])])
    }

    func testDressCanAddOuterwearWithoutShoes() {
        XCTAssertEqual(categorySets([.dress, .outerwear]), [Set([.dress]), Set([.dress, .outerwear])])
    }

    func testDressVariantsNeverIncludeTopOrBottom() {
        let wardrobe = [
            Fixture.garment(1, .dress), Fixture.garment(2, .top), Fixture.garment(3, .bottom),
            Fixture.garment(4, .outerwear), Fixture.garment(5, .bag),
        ]
        let dresses = CandidateGenerator().candidates(from: wardrobe).filter { $0.contains(.dress) }
        XCTAssertTrue(dresses.contains { $0.contains(.outerwear) && $0.contains(.bag) })
        XCTAssertTrue(dresses.allSatisfy { !$0.contains(.top) && !$0.contains(.bottom) })
    }

    func testExpandedProfilesKeepFanoutAndCandidateLimits() {
        var configuration = OutfitEngineConfiguration.default
        configuration.maximumEvaluatedCandidates = 23
        configuration.maximumBaseCombinations = 4
        let candidates = CandidateGenerator(configuration: configuration).candidates(from: Fixture.largeWardrobe())
        XCTAssertEqual(candidates.count, 23)
        XCTAssertLessThanOrEqual(Set(candidates.map(\.baseSignature)).count, 4)
        XCTAssertLessThanOrEqual(Set(candidates.flatMap { $0.items(in: .shoes).map(\.id) }).count, 2)
        XCTAssertLessThanOrEqual(Set(candidates.flatMap { $0.items(in: .outerwear).map(\.id) }).count, 1)
        XCTAssertLessThanOrEqual(Set(candidates.flatMap { $0.items(in: .accessory).map(\.id) }).count, 1)
    }

    func testZeroCandidateOrBaseBudgetProducesNothing() {
        var configuration = OutfitEngineConfiguration.default
        configuration.maximumEvaluatedCandidates = 0
        XCTAssertTrue(CandidateGenerator(configuration: configuration).candidates(from: Fixture.smallWardrobe()).isEmpty)
        configuration.maximumEvaluatedCandidates = 300
        configuration.maximumBaseCombinations = 0
        XCTAssertTrue(CandidateGenerator(configuration: configuration).candidates(from: Fixture.smallWardrobe()).isEmpty)
    }

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
