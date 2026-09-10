import XCTest
@testable import RIG

final class OutfitValidatorTests: XCTestCase {
    func testTopAndBottomIsValid() {
        let outfit = [Fixture.garment(1, .top), Fixture.garment(2, .bottom)]
        XCTAssertTrue(OutfitValidator.validate(outfit).isValid)
    }

    func testDressAloneIsValid() {
        XCTAssertTrue(OutfitValidator.validate([Fixture.garment(1, .dress)]).isValid)
    }

    func testFullyDressedOutfitIsValid() {
        let outfit = [
            Fixture.garment(1, .top),
            Fixture.garment(2, .bottom),
            Fixture.garment(3, .shoes),
            Fixture.garment(4, .outerwear),
            Fixture.garment(5, .bag),
            Fixture.garment(6, .accessory)
        ]
        XCTAssertTrue(OutfitValidator.validate(outfit).isValid)
    }

    func testEmptyOutfitIsInvalid() {
        let validation = OutfitValidator.validate([])
        XCTAssertFalse(validation.isValid)
        XCTAssertEqual(validation.issues, [.empty])
    }

    func testDuplicateGarmentIsInvalid() {
        let item = Fixture.garment(1, .top)
        let validation = OutfitValidator.validate([item, item, Fixture.garment(2, .bottom)])
        XCTAssertFalse(validation.isValid)
        XCTAssertTrue(validation.issues.contains(.duplicateGarment))
    }

    func testAccessoriesOnlyIsInvalid() {
        let validation = OutfitValidator.validate([
            Fixture.garment(1, .accessory),
            Fixture.garment(2, .bag)
        ])
        XCTAssertFalse(validation.isValid)
        XCTAssertTrue(validation.issues.contains(.missingBase))
    }

    func testTopWithoutBottomIsInvalid() {
        let validation = OutfitValidator.validate([
            Fixture.garment(1, .top),
            Fixture.garment(2, .shoes)
        ])
        XCTAssertFalse(validation.isValid)
        XCTAssertTrue(validation.issues.contains(.missingBase))
    }

    func testTwoBottomsWithoutTopIsInvalid() {
        let validation = OutfitValidator.validate([
            Fixture.garment(1, .bottom),
            Fixture.garment(2, .bottom)
        ])
        XCTAssertFalse(validation.isValid)
        XCTAssertTrue(validation.issues.contains(.tooMany(.bottom, limit: 1)))
        XCTAssertTrue(validation.issues.contains(.missingBase))
    }

    func testDressWithBottomIsConflicting() {
        let validation = OutfitValidator.validate([
            Fixture.garment(1, .dress),
            Fixture.garment(2, .bottom)
        ])
        XCTAssertFalse(validation.isValid)
        XCTAssertTrue(validation.issues.contains(.conflictingBase))
    }

    func testDressWithTopIsConflicting() {
        let validation = OutfitValidator.validate([
            Fixture.garment(1, .dress),
            Fixture.garment(2, .top)
        ])
        XCTAssertFalse(validation.isValid)
        XCTAssertTrue(validation.issues.contains(.conflictingBase))
    }

    func testTwoDressesIsInvalid() {
        let validation = OutfitValidator.validate([
            Fixture.garment(1, .dress),
            Fixture.garment(2, .dress)
        ])
        XCTAssertFalse(validation.isValid)
        XCTAssertTrue(validation.issues.contains(.tooMany(.dress, limit: 1)))
    }

    func testThreeAccessoriesAreAllowedButFourAreNot() {
        let base = [Fixture.garment(1, .top), Fixture.garment(2, .bottom)]
        let three = base + (10..<13).map { Fixture.garment($0, .accessory) }
        XCTAssertTrue(OutfitValidator.validate(three).isValid)

        let four = base + (10..<14).map { Fixture.garment($0, .accessory) }
        XCTAssertFalse(OutfitValidator.validate(four).isValid)
        XCTAssertTrue(OutfitValidator.validate(four).issues.contains(.tooMany(.accessory, limit: 3)))
    }

    func testIssueOrderIsDeterministic() {
        let outfit = [
            Fixture.garment(1, .bottom),
            Fixture.garment(2, .bottom),
            Fixture.garment(3, .shoes),
            Fixture.garment(4, .shoes)
        ]
        let first = OutfitValidator.validate(outfit).issues
        let second = OutfitValidator.validate(outfit).issues
        XCTAssertEqual(first, second)
    }
}
