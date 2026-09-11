import XCTest
@testable import RIG

/// Converting a mask's source-space bounds into a crop's local space — pure
/// arithmetic, independent of `CropGeometry`'s touch handling.
final class MaskOverlayGeometryTests: XCTestCase {
    private func assertRect(
        _ actual: NormalizedCropRect?,
        x: Double, y: Double, width: Double, height: Double,
        accuracy: Double = 0.0001,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        guard let actual else {
            XCTFail("expected a rect, got nil", file: file, line: line)
            return
        }
        XCTAssertEqual(actual.x, x, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.y, y, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.width, width, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.height, height, accuracy: accuracy, file: file, line: line)
    }

    func testAMaskCoveringExactlyTheCropRegionMapsToTheFullLocalRect() {
        let crop = NormalizedCropRect(x: 0.2, y: 0.3, width: 0.4, height: 0.4)
        let result = MaskOverlayGeometry.localRegion(for: crop, within: crop)
        assertRect(result, x: 0, y: 0, width: 1, height: 1)
    }

    func testASmallerOffsetMaskSubRegionMapsToProportionalLocalCoordinates() {
        // The crop covers [0.2, 0.6] x [0.2, 0.6] of the source (a 0.4x0.4
        // square). A mask sitting in the crop's own upper-left quarter —
        // [0.2, 0.4] x [0.2, 0.4] in source-space — should land exactly at
        // (0, 0, 0.5, 0.5) in the crop's local space.
        let crop = NormalizedCropRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4)
        let mask = NormalizedCropRect(x: 0.2, y: 0.2, width: 0.2, height: 0.2)

        let result = MaskOverlayGeometry.localRegion(for: mask, within: crop)

        assertRect(result, x: 0, y: 0, width: 0.5, height: 0.5)
    }

    func testAMaskCenteredInsideTheCropMapsToProportionalOffsetCoordinates() {
        // Crop is [0.0, 0.5] x [0.0, 0.5] (a 0.5x0.5 square). A mask at
        // [0.25, 0.375] x [0.25, 0.375] (0.125 wide/tall, centered) should
        // land at local x/y = 0.25 / 0.5 = 0.5, width/height = 0.125/0.5 = 0.25.
        let crop = NormalizedCropRect(x: 0, y: 0, width: 0.5, height: 0.5)
        let mask = NormalizedCropRect(x: 0.25, y: 0.25, width: 0.125, height: 0.125)

        let result = MaskOverlayGeometry.localRegion(for: mask, within: crop)

        assertRect(result, x: 0.5, y: 0.5, width: 0.25, height: 0.25)
    }

    func testADegenerateZeroWidthCropRegionReturnsNil() {
        let crop = NormalizedCropRect(x: 0.2, y: 0.2, width: 0, height: 0.4)
        let mask = NormalizedCropRect(x: 0.2, y: 0.2, width: 0.1, height: 0.1)

        XCTAssertNil(MaskOverlayGeometry.localRegion(for: mask, within: crop))
    }

    func testADegenerateZeroHeightCropRegionReturnsNil() {
        let crop = NormalizedCropRect(x: 0.2, y: 0.2, width: 0.4, height: 0)
        let mask = NormalizedCropRect(x: 0.2, y: 0.2, width: 0.1, height: 0.1)

        XCTAssertNil(MaskOverlayGeometry.localRegion(for: mask, within: crop))
    }

    func testANonFiniteCropRegionReturnsNil() {
        let crop = NormalizedCropRect(x: .nan, y: 0.2, width: 0.4, height: 0.4)
        let mask = NormalizedCropRect(x: 0.2, y: 0.2, width: 0.1, height: 0.1)

        XCTAssertNil(MaskOverlayGeometry.localRegion(for: mask, within: crop))
    }

    // MARK: - sourcePoint / localPoint (v0.4 Slice 2.1 refinement taps)

    func testSourcePointMapsACropLocalTapBackIntoSourceSpace() throws {
        // Same crop as the sub-region test above: [0.2, 0.6] x [0.2, 0.6].
        // A tap dead-center of the crop (0.5, 0.5 local) must land at the
        // crop's own center in source-space.
        let crop = NormalizedCropRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4)
        let source = try XCTUnwrap(MaskOverlayGeometry.sourcePoint(forLocalX: 0.5, localY: 0.5, within: crop))

        XCTAssertEqual(source.x, 0.4, accuracy: 0.0001)
        XCTAssertEqual(source.y, 0.4, accuracy: 0.0001)
    }

    func testLocalPointIsTheExactInverseOfSourcePoint() throws {
        let crop = NormalizedCropRect(x: 0.1, y: 0.3, width: 0.5, height: 0.2)
        let source = try XCTUnwrap(MaskOverlayGeometry.sourcePoint(forLocalX: 0.3, localY: 0.7, within: crop))
        let roundTripped = try XCTUnwrap(
            MaskOverlayGeometry.localPoint(forSourceX: source.x, sourceY: source.y, within: crop)
        )

        XCTAssertEqual(roundTripped.x, 0.3, accuracy: 0.0001)
        XCTAssertEqual(roundTripped.y, 0.7, accuracy: 0.0001)
    }

    func testSourcePointOfADegenerateCropRegionReturnsNil() {
        let crop = NormalizedCropRect(x: 0.2, y: 0.2, width: 0, height: 0.4)
        XCTAssertNil(MaskOverlayGeometry.sourcePoint(forLocalX: 0.5, localY: 0.5, within: crop))
    }

    func testLocalPointOfADegenerateCropRegionReturnsNil() {
        let crop = NormalizedCropRect(x: 0.2, y: 0.2, width: 0.4, height: 0)
        XCTAssertNil(MaskOverlayGeometry.localPoint(forSourceX: 0.3, sourceY: 0.3, within: crop))
    }

    func testLocalPointOfASourcePointOutsideThisCropFallsOutsideZeroToOne() throws {
        // Not nil — `MaskReviewSheet` itself filters markers to [0,1]; the
        // geometry function's job is only the arithmetic, not the clipping.
        let crop = NormalizedCropRect(x: 0.5, y: 0.5, width: 0.2, height: 0.2)
        let outside = try XCTUnwrap(MaskOverlayGeometry.localPoint(forSourceX: 0.1, sourceY: 0.1, within: crop))
        XCTAssertFalse((0...1).contains(outside.x))
    }
}
