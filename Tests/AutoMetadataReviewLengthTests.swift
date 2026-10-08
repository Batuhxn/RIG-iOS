import SwiftUI
import XCTest
@testable import RIG

@MainActor
final class AutoMetadataReviewLengthTests: XCTestCase {
    func testWhitespaceEditKeepsValidDressLength() {
        var fields = GarmentMetadataFields()
        fields.fillEmptyFields(from: AutoMetadataResult(category: .init(value: .dress, score: 0.9),
            subtype: .init(value: "dress", score: 0.9), length: .init(value: .mini, score: 0.9),
            primaryColor: .init(value: .black, score: 0.9), semanticStatus: "suggested"))
        let form = GarmentMetadataForm(fields: Binding(get: { fields }, set: { fields = $0 }))
        form.subtypeBinding.wrappedValue = " dress "
        XCTAssertEqual(fields.length, .mini)
        let item = ClothingItem(displayName: "Dress", category: .dress, primaryColor: .black)
        XCTAssertTrue(fields.apply(to: item))
        XCTAssertEqual(item.subtype, "dress")
        XCTAssertEqual(item.lengthRaw, "mini")
    }
}
