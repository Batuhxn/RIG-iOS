import XCTest
@testable import RIG

final class AutoMetadataPrewarmTests: XCTestCase {
    private actor CountingClassifier: GarmentSemanticClassifying {
        var warmed = 0
        func classify(cutout: Data) async throws -> AutoMetadataResult { AutoMetadataResult() }
        func prewarm() async { warmed += 1 }
    }

    func testPrewarmReachesTheClassifier() async {
        let classifier = CountingClassifier()
        await AutoMetadataService(classifier: classifier).prewarm()
        let warmed = await classifier.warmed
        XCTAssertEqual(warmed, 1)
    }

    func testPrewarmWithoutAModelIsHarmless() async {
        await AutoMetadataService().prewarm()
        await CoreMLGarmentClassifier(bundle: Bundle(for: Self.self)).prewarm()
        let result = await AutoMetadataService(classifier: CoreMLGarmentClassifier(bundle: Bundle(for: Self.self)))
            .analyze(cutout: Data([1, 2, 3]))
        XCTAssertNil(result.category)
    }
}
