import SwiftData
import XCTest
@testable import RIG

@MainActor
final class AutoMetadataPersistenceTests: XCTestCase {
    func testOptionalMetadataRoundTripsWithoutChangingOutfitSnapshot() throws {
        let container = try RIGModelContainer.makeInMemoryContainer()
        let context = ModelContext(container)
        let item = ClothingItem(displayName: "Skirt", subtype: "skirt", category: .bottom, primaryColor: .black)
        context.insert(item)
        let snapshot = item.snapshot
        var fields = GarmentMetadataFields(item: item)
        fields.length = .mini
        fields.secondaryColor = .white
        fields.autoMetadata = AutoMetadataResult(primaryColor: .init(value: .black, score: 0.8))
        XCTAssertTrue(fields.apply(to: item))
        try context.save()
        let reloaded = try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<ClothingItem>()).first)
        let draft = GarmentMetadataFields(item: reloaded)
        XCTAssertEqual(draft.length, .mini)
        XCTAssertEqual(draft.secondaryColor, .white)
        XCTAssertEqual(draft.autoMetadata?.primaryColor?.score, 0.8)
        XCTAssertEqual(reloaded.snapshot.category, snapshot.category)
        XCTAssertEqual(reloaded.snapshot.colorFamily, snapshot.colorFamily)
    }

    func testFailedEditRestoresNewMetadataFields() throws {
        enum SaveFailure: Error { case expected }
        let container = try RIGModelContainer.makeInMemoryContainer()
        let context = ModelContext(container)
        let item = ClothingItem(displayName: "Skirt", subtype: "skirt", category: .bottom, primaryColor: .black)
        item.lengthRaw = "mini"
        item.secondaryColorRaw = "white"
        context.insert(item)
        try context.save()
        var fields = GarmentMetadataFields(item: item)
        fields.length = .maxi
        fields.secondaryColor = .red
        XCTAssertThrowsError(try GarmentMutations.edit(item, fields: fields, in: context) { throw SaveFailure.expected })
        XCTAssertEqual(item.lengthRaw, "mini")
        XCTAssertEqual(item.secondaryColorRaw, "white")
    }

    func testInvalidLengthAndDuplicateSecondaryAreNotSaved() {
        let item = ClothingItem(displayName: "Shoes", category: .shoes, primaryColor: .black)
        var fields = GarmentMetadataFields(item: item)
        fields.length = .mini
        fields.secondaryColor = .black
        fields.applyAutoMetadata(to: item)
        XCTAssertNil(item.lengthRaw)
        XCTAssertNil(item.secondaryColorRaw)
    }
}
