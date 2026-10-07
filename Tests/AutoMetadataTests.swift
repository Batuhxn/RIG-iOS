import XCTest
@testable import RIG

final class AutoMetadataTests: XCTestCase {
    func testTransparentBackgroundCannotBecomePrimaryColor() {
        let pixels = Array(repeating: UInt8(0), count: 400) + Array(repeating: [UInt8(255), 0, 0, 255], count: 100).flatMap { $0 }
        let result = MaskedColorExtractor.extract(rgba: pixels)
        XCTAssertEqual(result?.primary.value, .red)
        XCTAssertNil(result?.secondary)
    }

    func testEmptyAndSoftMasksAbstain() {
        XCTAssertNil(MaskedColorExtractor.extract(rgba: []))
        XCTAssertNil(MaskedColorExtractor.extract(rgba: Array(repeating: [UInt8(50), 0, 0, 100], count: 100).flatMap { $0 }))
    }

    func testSecondaryRequiresSignificantArea() {
        let black = Array(repeating: [UInt8(0), 0, 0, 255], count: 80).flatMap { $0 }
        let white = Array(repeating: [UInt8(255), 255, 255, 255], count: 20).flatMap { $0 }
        let result = MaskedColorExtractor.extract(rgba: black + white)
        XCTAssertEqual(result?.primary.value, .black)
        XCTAssertEqual(result?.secondary?.value, .white)
        XCTAssertEqual(result?.primary.score ?? 0, 0.8, accuracy: 0.001)
    }

    func testTiedEmbeddingsAbstain() {
        XCTAssertNil(EmbeddingRanking.best(image: [1, 0], candidates: [
            TextEmbedding(label: "shirt", vector: [1, 0]),
            TextEmbedding(label: "skirt", vector: [1, 0])
        ]))
    }

    func testInvalidEmbeddingAbstains() {
        XCTAssertNil(EmbeddingRanking.best(image: [0, 0], candidates: [TextEmbedding(label: "shirt", vector: [1, 0])]))
        XCTAssertNil(EmbeddingRanking.best(image: [.nan, 1], candidates: [TextEmbedding(label: "shirt", vector: [1, 0])]))
    }

    func testLengthOnlyAppliesToDressAndSkirt() {
        XCTAssertTrue(GarmentLength.applies(category: .dress, subtype: "dress"))
        XCTAssertTrue(GarmentLength.applies(category: .bottom, subtype: "skirt"))
        XCTAssertFalse(GarmentLength.applies(category: .bottom, subtype: "trousers"))
        XCTAssertFalse(GarmentLength.applies(category: .shoes, subtype: "skirt"))
        XCTAssertFalse(GarmentLength.applies(category: .dress, subtype: "jumpsuit"))
    }

    @MainActor
    func testDeliberatelyClearedFieldStaysEmptyOnRetry() {
        var fields = GarmentMetadataFields()
        fields.editedFields.insert(.category)
        fields.fillEmptyFields(from: AutoMetadataResult(category: .init(value: .bottom, score: 0.9)))
        XCTAssertNil(fields.category)
        XCTAssertNil(fields.autoMetadata?.category)
    }

    func testMissingMaskDoesNotUseOriginalBackgroundAsColour() async {
        let result = await AutoMetadataService().analyze(cutout: nil)
        XCTAssertNil(result.primaryColor)
        XCTAssertNil(result.category)
    }

    @MainActor
    func testAutofillPreservesManualFieldsAndDoesNotInventSeason() {
        var fields = GarmentMetadataFields()
        fields.category = .top
        fields.subtype = "My shirt"
        fields.colorFamily = .blue
        let result = AutoMetadataResult(category: .init(value: .bottom, score: 0.9),
                                        subtype: .init(value: "skirt", score: 0.8),
                                        length: .init(value: .mini, score: 0.8),
                                        primaryColor: .init(value: .black, score: 0.9))
        fields.fillEmptyFields(from: result)
        XCTAssertEqual(fields.category, .top)
        XCTAssertEqual(fields.subtype, "My shirt")
        XCTAssertEqual(fields.colorFamily, .blue)
        XCTAssertNil(fields.length)
        XCTAssertTrue(fields.seasons.isEmpty)
    }

    @MainActor
    func testNewDraftReceivesCompatiblePredictions() {
        var fields = GarmentMetadataFields()
        fields.fillEmptyFields(from: AutoMetadataResult(category: .init(value: .bottom, score: 0.9),
            subtype: .init(value: "skirt", score: 0.8), length: .init(value: .mini, score: 0.8),
            primaryColor: .init(value: .black, score: 0.9)))
        XCTAssertEqual(fields.category, .bottom)
        XCTAssertEqual(fields.subtype, "skirt")
        XCTAssertEqual(fields.length, .mini)
        XCTAssertEqual(fields.colorFamily, .black)
        XCTAssertFalse(fields.isValid)
    }
}
