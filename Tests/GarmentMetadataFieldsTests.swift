import XCTest
@testable import RIG

@MainActor
final class GarmentMetadataFieldsTests: XCTestCase {
    func testNewDraftHasNoConfirmedMetadata() {
        var fields = GarmentMetadataFields()
        fields.displayName = "Jacket"

        XCTAssertNil(fields.category)
        XCTAssertNil(fields.colorFamily)
        XCTAssertEqual(fields.seasons, .all, "season defaults to all year, it is never inferred")
        XCTAssertFalse(fields.isValid)
    }

    func testCategoryAloneIsInvalid() {
        var fields = GarmentMetadataFields()
        fields.displayName = "Jacket"
        fields.category = .outerwear

        XCTAssertFalse(fields.isValid)
    }

    func testCategoryAndColorSufficeBecauseSeasonDefaultsToAllYear() {
        var fields = GarmentMetadataFields()
        fields.displayName = "Jacket"
        fields.category = .outerwear
        fields.colorFamily = .navy

        XCTAssertTrue(fields.isValid)
        XCTAssertEqual(fields.effectiveSeasons, .all)
    }

    func testNarrowingToOneSeasonIsKept() {
        var fields = GarmentMetadataFields()
        fields.displayName = "Jacket"
        fields.category = .outerwear
        fields.colorFamily = .navy
        fields.setAllYear(false)
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

    func testClearingEverySeasonSavesAsAllYearWithoutBlocking() {
        var fields = GarmentMetadataFields()
        fields.displayName = "Jacket"
        fields.category = .outerwear
        fields.colorFamily = .navy
        fields.setAllYear(false)
        fields.setSeason(.winter, selected: true)
        fields.setSeason(.winter, selected: false)

        XCTAssertTrue(fields.seasons.isEmpty, "the draft shows what the user chose")
        XCTAssertTrue(fields.isValid)
        let item = ClothingItem(displayName: "Old", category: .top, primaryColor: .white, seasons: [.summer])
        XCTAssertTrue(fields.apply(to: item))
        XCTAssertEqual(item.seasons, .all)
    }

    func testTurningOffAllYearLeavesNoSeasonSelected() {
        var fields = GarmentMetadataFields()
        fields.displayName = "Jacket"
        fields.category = .outerwear
        fields.colorFamily = .navy
        fields.setAllYear(true)
        fields.setAllYear(false)

        XCTAssertTrue(fields.seasons.isEmpty)
        XCTAssertTrue(fields.isValid)
        XCTAssertEqual(fields.effectiveSeasons, .all)
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
