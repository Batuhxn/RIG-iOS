import CoreGraphics
import Foundation
import XCTest
@testable import RIG

/// The rectangle arithmetic behind v0.3 cropping.
///
/// All of it is fractions of the source image, which is what lets the user drag
/// a box over a small on-screen copy and have the cut taken from the full-size
/// photograph. These tests pin the two properties that make that safe: a
/// rectangle never leaves the image, and it never collapses or inverts.
final class GarmentCropGeometryTests: XCTestCase {
    private let side = NormalizedCropRect.minimumSide

    func testTheDefaultRectangleSitsInsideThePhotoAndIsUsable() {
        let region = NormalizedCropRect.centeredDefault
        XCTAssertTrue(region.isUsable)
        XCTAssertEqual(region, region.clamped())
        XCTAssertGreaterThanOrEqual(region.x, 0)
        XCTAssertLessThanOrEqual(region.x + region.width, 1)
    }

    func testTheFullRectangleCoversTheWholePhoto() {
        XCTAssertEqual(NormalizedCropRect.full, NormalizedCropRect.full.clamped())
        XCTAssertTrue(NormalizedCropRect.full.isUsable)
    }

    func testClampingPullsAnOverhangingRectangleBackInside() {
        let clamped = NormalizedCropRect(x: 0.8, y: -0.3, width: 0.5, height: 0.5).clamped()
        XCTAssertEqual(clamped, NormalizedCropRect(x: 0.5, y: 0, width: 0.5, height: 0.5))
    }

    func testClampingEnforcesAMinimumSize() {
        let clamped = NormalizedCropRect(x: 0.5, y: 0.5, width: 0.001, height: 0.001).clamped()
        XCTAssertEqual(clamped.width, side, accuracy: 0.0001)
        XCTAssertEqual(clamped.height, side, accuracy: 0.0001)
        XCTAssertTrue(clamped.isUsable)
    }

    func testATinyRectangleIsNotUsable() {
        XCTAssertFalse(NormalizedCropRect(x: 0, y: 0, width: 0.01, height: 0.5).isUsable)
        XCTAssertFalse(NormalizedCropRect(x: 0, y: 0, width: 0.5, height: 0.01).isUsable)
    }

    func testDraggingMovesTheRectangleWithoutResizingIt() {
        let moved = NormalizedCropRect.centeredDefault.translated(dx: 0.1, dy: -0.1)
        XCTAssertEqual(moved.width, 0.6, accuracy: 0.0001)
        XCTAssertEqual(moved.height, 0.6, accuracy: 0.0001)
        XCTAssertEqual(moved.x, 0.3, accuracy: 0.0001)
        XCTAssertEqual(moved.y, 0.1, accuracy: 0.0001)
    }

    func testDraggingStopsAtTheEdgeOfThePhoto() {
        let moved = NormalizedCropRect.centeredDefault.translated(dx: 5, dy: 5)
        XCTAssertEqual(moved.x, 0.4, accuracy: 0.0001)
        XCTAssertEqual(moved.y, 0.4, accuracy: 0.0001)
        XCTAssertEqual(moved.width, 0.6, accuracy: 0.0001)
    }

    func testResizingKeepsTheOppositeCornerWhereItWas() {
        let start = NormalizedCropRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)
        let resized = start.resized(.topLeading, dx: 0.1, dy: 0.1)

        XCTAssertEqual(resized.x, 0.3, accuracy: 0.0001)
        XCTAssertEqual(resized.y, 0.3, accuracy: 0.0001)
        XCTAssertEqual(resized.x + resized.width, 0.8, accuracy: 0.0001)
        XCTAssertEqual(resized.y + resized.height, 0.8, accuracy: 0.0001)
    }

    func testResizingTheOtherCornersMovesTheExpectedEdges() {
        let start = NormalizedCropRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)

        let trailing = start.resized(.bottomTrailing, dx: 0.1, dy: 0.1)
        XCTAssertEqual(trailing.x, 0.2, accuracy: 0.0001)
        XCTAssertEqual(trailing.x + trailing.width, 0.9, accuracy: 0.0001)

        let bottomLeading = start.resized(.bottomLeading, dx: -0.1, dy: 0.1)
        XCTAssertEqual(bottomLeading.x, 0.1, accuracy: 0.0001)
        XCTAssertEqual(bottomLeading.y, 0.2, accuracy: 0.0001)
    }

    func testAFastDragCannotInvertTheRectangle() {
        let start = NormalizedCropRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)
        for corner in CropCorner.allCases {
            let collapsed = start.resized(corner, dx: -4, dy: -4)
            XCTAssertGreaterThanOrEqual(collapsed.width, side - 0.0001, "\(corner)")
            XCTAssertGreaterThanOrEqual(collapsed.height, side - 0.0001, "\(corner)")
            XCTAssertTrue(collapsed.isUsable, "\(corner)")

            let blownUp = start.resized(corner, dx: 4, dy: 4)
            XCTAssertGreaterThanOrEqual(blownUp.x, 0, "\(corner)")
            XCTAssertLessThanOrEqual(blownUp.x + blownUp.width, 1.0001, "\(corner)")
        }
    }

    func testResizingNeverLeavesThePhoto() {
        var region = NormalizedCropRect.centeredDefault
        for (index, corner) in CropCorner.allCases.enumerated() {
            let delta = index.isMultiple(of: 2) ? 0.4 : -0.4
            region = region.resized(corner, dx: delta, dy: delta)
            XCTAssertGreaterThanOrEqual(region.x, 0)
            XCTAssertGreaterThanOrEqual(region.y, 0)
            XCTAssertLessThanOrEqual(region.x + region.width, 1.0001)
            XCTAssertLessThanOrEqual(region.y + region.height, 1.0001)
        }
    }

    func testFractionsBecomePixelsOnTheSourceImage() {
        let region = NormalizedCropRect(x: 0.25, y: 0.5, width: 0.5, height: 0.25)
        let rect = region.pixelRect(in: CGSize(width: 1600, height: 1200))

        XCTAssertEqual(rect.minX, 400, accuracy: 1)
        XCTAssertEqual(rect.minY, 600, accuracy: 1)
        XCTAssertEqual(rect.width, 800, accuracy: 1)
        XCTAssertEqual(rect.height, 300, accuracy: 1)
    }

    func testAPixelRectangleIsNeverEmpty() {
        let rect = NormalizedCropRect(x: 0, y: 0, width: 0.06, height: 0.06)
            .pixelRect(in: CGSize(width: 10, height: 10))
        XCTAssertGreaterThanOrEqual(rect.width, 1)
        XCTAssertGreaterThanOrEqual(rect.height, 1)
    }

    func testAPortraitPhotoFitsByItsLongerSide() {
        let fitted = GarmentCropView.fittedSize(
            for: CGSize(width: 900, height: 1600),
            in: CGSize(width: 390, height: 600)
        )
        XCTAssertEqual(fitted.height, 600, accuracy: 0.5)
        XCTAssertEqual(fitted.width, 337.5, accuracy: 0.5)
    }

    func testAnEmptyContainerDoesNotProduceANaNLayout() {
        let fitted = GarmentCropView.fittedSize(for: .zero, in: CGSize(width: 100, height: 100))
        XCTAssertEqual(fitted, CGSize(width: 100, height: 100))
    }

    func testCornerPointsSitOnTheRectangle() {
        let rect = CGRect(x: 10, y: 20, width: 100, height: 200)
        XCTAssertEqual(GarmentCropView.cornerPoint(.topLeading, in: rect), CGPoint(x: 10, y: 20))
        XCTAssertEqual(GarmentCropView.cornerPoint(.topTrailing, in: rect), CGPoint(x: 110, y: 20))
        XCTAssertEqual(GarmentCropView.cornerPoint(.bottomLeading, in: rect), CGPoint(x: 10, y: 220))
        XCTAssertEqual(GarmentCropView.cornerPoint(.bottomTrailing, in: rect), CGPoint(x: 110, y: 220))
    }
}
