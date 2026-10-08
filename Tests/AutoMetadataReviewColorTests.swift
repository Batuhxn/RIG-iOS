import UIKit
import XCTest
@testable import RIG

final class AutoMetadataReviewColorTests: XCTestCase {
    private struct AbstainingColourClassifier: GarmentSemanticClassifying {
        func classify(cutout: Data) async throws -> AutoMetadataResult {
            AutoMetadataResult(category: .init(value: .top, score: 0.9), semanticStatus: "suggested")
        }
    }

    func testWorkingClassifierColourAbstentionSurvivesPixelMerge() async throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let png = try XCTUnwrap(UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 16, y: 16, width: 32, height: 32))
        }.pngData())
        let result = await AutoMetadataService(classifier: AbstainingColourClassifier()).analyze(cutout: png)
        XCTAssertEqual(result.category?.value, .top)
        XCTAssertNil(result.primaryColor)
        XCTAssertNil(result.secondaryColor)
    }
}
