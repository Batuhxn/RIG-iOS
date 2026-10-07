import UIKit
import XCTest
@testable import RIG

final class AutoMetadataServiceTests: XCTestCase {
    func testMissingModelStillReturnsMaskColours() async throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let png = try XCTUnwrap(UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 16, y: 16, width: 32, height: 32))
        }.pngData())
        let result = await AutoMetadataService().analyze(cutout: png)
        XCTAssertEqual(result.primaryColor?.value, .red)
        XCTAssertNil(result.category)
        XCTAssertEqual(result.semanticStatus, "unavailable")
    }

    func testMalformedImageNeverProducesSuggestions() async {
        let result = await AutoMetadataService().analyze(cutout: Data([1, 2, 3]))
        XCTAssertNil(result.category)
        XCTAssertNil(result.primaryColor)
    }
}
