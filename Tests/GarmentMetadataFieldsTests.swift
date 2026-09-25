import XCTest
@testable import RIG

@MainActor
final class GarmentMetadataFieldsTests: XCTestCase {
    func testNewDraftHasNoConfirmedMetadata() {
        var fields = GarmentMetadataFields()
        fields.displayName = "Jacket"

        XCTAssertNil(fields.category)
        XCTAssertNil(fields.colorFamily)
        XCTAssertTrue(fields.seasons.isEmpty)
        XCTAssertFalse(fields.isValid)
    }

    func testCategoryAloneIsInvalid() {
        var fields = GarmentMetadataFields()
        fields.displayName = "Jacket"
        fields.category = .outerwear

        XCTAssertFalse(fields.isValid)
    }

    func testCategoryAndColorStillNeedSeason() {
        var fields = GarmentMetadataFields()
        fields.displayName = "Jacket"
        fields.category = .outerwear
        fields.colorFamily = .navy

        XCTAssertFalse(fields.isValid)
    }

    func testOneExplicitSeasonMakesDraftValid() {
        var fields = GarmentMetadataFields()
        fields.displayName = "Jacket"
        fields.category = .outerwear
        fields.colorFamily = .navy
        fields.setSeason(.winter, selected: true)

        XCTAssertTrue(fields.isValid)
        XCTAssertEqual(fields.seasons, .winter)
    }

    func testAllYearExplicitlySelectsFourSeasons() {
        var fields = GarmentMetadataFields()
        fields.displayName = "Jacket"
        fields.category = .outerwear
        fields.colorFamily = .navy
        fields.setAllYear(true)

        XCTAssertTrue(fields.isValid)
        XCTAssertEqual(fields.seasons, .all)
        XCTAssertEqual(fields.seasons.seasons.count, 4)
    }

    func testClearingLastSeasonDoesNotNormalizeDraft() {
        var fields = GarmentMetadataFields()
        fields.displayName = "Jacket"
        fields.category = .outerwear
        fields.colorFamily = .navy
        fields.setSeason(.winter, selected: true)
        fields.setSeason(.winter, selected: false)

        XCTAssertTrue(fields.seasons.isEmpty)
        XCTAssertFalse(fields.isValid)
    }

    func testTurningOffAllYearLeavesNoSeasonSelected() {
        var fields = GarmentMetadataFields()
        fields.displayName = "Jacket"
        fields.category = .outerwear
        fields.colorFamily = .navy
        fields.setAllYear(true)
        fields.setAllYear(false)

        XCTAssertTrue(fields.seasons.isEmpty)
        XCTAssertFalse(fields.isValid)
    }

    func testExistingGarmentPopulatesValidDraftWithoutReconfirmation() {
        let item = ClothingItem(
            displayName: "Coat",
            category: .outerwear,
            primaryColor: .brown,
            seasons: [.autumn, .winter]
        )
        let fields = GarmentMetadataFields(item: item)

        XCTAssertEqual(fields.category, .outerwear)
        XCTAssertEqual(fields.colorFamily, .brown)
        XCTAssertEqual(fields.seasons, [.autumn, .winter])
        XCTAssertTrue(fields.isValid)
    }

    func testInvalidDraftCannotChangeExistingGarment() {
        let item = ClothingItem(displayName: "Coat", category: .outerwear, primaryColor: .brown)
        var fields = GarmentMetadataFields()
        fields.displayName = "Changed"

        XCTAssertFalse(fields.apply(to: item))
        XCTAssertEqual(item.displayName, "Coat")
        XCTAssertEqual(item.category, .outerwear)
    }
}
