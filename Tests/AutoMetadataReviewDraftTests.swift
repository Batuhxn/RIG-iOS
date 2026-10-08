import SwiftUI
import XCTest
@testable import RIG

@MainActor
final class AutoMetadataReviewDraftTests: XCTestCase {
    func testBulkRetryCannotPersistAlternativesForARejectedCategory() {
        var fields = GarmentMetadataFields()
        let prediction = AutoMetadataResult(category: .init(value: .bottom, score: 0.9),
            primaryColor: .init(value: .black, score: 0.9), semanticStatus: "suggested", subtypeAlternatives: ["skirt", "shorts"])
        fields.fillEmptyFields(from: prediction)
        let form = GarmentMetadataForm(fields: Binding(get: { fields }, set: { fields = $0 }))
        form.categoryBinding.wrappedValue = .top
        fields.fillEmptyFields(from: prediction)
        let item = ClothingItem(displayName: "Top", category: .top, primaryColor: .black)
        XCTAssertTrue(fields.apply(to: item))
        let reopened = GarmentMetadataFields(item: item)
        XCTAssertEqual(reopened.category, .top)
        XCTAssertNil(reopened.autoMetadata?.subtypeAlternatives)
    }
}
