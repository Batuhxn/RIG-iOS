import XCTest
@testable import RIG

final class OutfitSignatureTests: XCTestCase {
    func testOrderDoesNotChangeSignature() {
        let a = Fixture.garment(1, .top)
        let b = Fixture.garment(2, .bottom)
        let c = Fixture.garment(3, .shoes)

        XCTAssertEqual(
            OutfitSignature.signature(for: [a, b, c]),
            OutfitSignature.signature(for: [c, a, b])
        )
    }

    func testDifferentItemSetsProduceDifferentSignatures() {
        let base = [Fixture.garment(1, .top), Fixture.garment(2, .bottom)]
        let extended = base + [Fixture.garment(3, .shoes)]
        XCTAssertNotEqual(
            OutfitSignature.signature(for: base),
            OutfitSignature.signature(for: extended)
        )
    }

    func testSwappingOneGarmentChangesSignature() {
        let first = [Fixture.garment(1, .top), Fixture.garment(2, .bottom)]
        let second = [Fixture.garment(1, .top), Fixture.garment(3, .bottom)]
        XCTAssertNotEqual(
            OutfitSignature.signature(for: first),
            OutfitSignature.signature(for: second)
        )
    }

    func testRepeatedGarmentIsNotCollapsed() {
        let item = Fixture.garment(1, .top)
        XCTAssertNotEqual(
            OutfitSignature.signature(for: [item]),
            OutfitSignature.signature(for: [item, item])
        )
    }

    func testEmptySignatureIsStable() {
        XCTAssertEqual(OutfitSignature.signature(forGarmentIDs: []), "")
    }

    func testCandidateSignatureMatchesItemSignature() {
        let items = [Fixture.garment(3, .shoes), Fixture.garment(1, .top), Fixture.garment(2, .bottom)]
        let candidate = OutfitCandidate(items: items)
        XCTAssertEqual(candidate.signature, OutfitSignature.signature(for: items))
    }

    func testBaseSignatureIgnoresDecoration() {
        let base = [Fixture.garment(1, .top), Fixture.garment(2, .bottom)]
        let withShoes = OutfitCandidate(items: base + [Fixture.garment(3, .shoes)])
        let withBag = OutfitCandidate(items: base + [Fixture.garment(4, .bag)])
        XCTAssertEqual(withShoes.baseSignature, withBag.baseSignature)
        XCTAssertNotEqual(withShoes.signature, withBag.signature)
    }
}
