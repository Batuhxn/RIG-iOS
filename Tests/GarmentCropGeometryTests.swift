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
    private let side = 0.000001

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

    func testClampingPreservesSmallImageRegions() {
        let clamped = NormalizedCropRect(x: 0.5, y: 0.5, width: 0.001, height: 0.001).clamped()
        XCTAssertEqual(clamped.width, 0.001, accuracy: 0.0000001)
        XCTAssertEqual(clamped.height, 0.001, accuracy: 0.0000001)
        XCTAssertTrue(clamped.isUsable)
    }

    func testSmallPositiveRegionsAreUsableButEmptyAndNonfiniteAreNot() {
        XCTAssertTrue(NormalizedCropRect(x: 0, y: 0, width: 0.01, height: 0.5).isUsable)
        XCTAssertFalse(NormalizedCropRect(x: 0, y: 0, width: 0, height: 0.5).isUsable)
        XCTAssertFalse(NormalizedCropRect(x: .nan, y: 0, width: 0.5, height: 0.5).isUsable)
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
            XCTAssertGreaterThanOrEqual(collapsed.width, side - 1e-12, "\(corner)")
            XCTAssertGreaterThanOrEqual(collapsed.height, side - 1e-12, "\(corner)")
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

    func testPortraitAndLandscapeImageRectsIncludeLetterboxing() {
        XCTAssertEqual(CropGeometry.imageRect(for: CGSize(width: 900, height: 1600),
                                             in: CGSize(width: 390, height: 600)),
                       CGRect(x: 26.25, y: 0, width: 337.5, height: 600))
        XCTAssertEqual(CropGeometry.imageRect(for: CGSize(width: 1600, height: 900),
                                             in: CGSize(width: 400, height: 600)),
                       CGRect(x: 0, y: 187.5, width: 400, height: 225))
    }

    func testViewRoundTripUsesImageOriginAndNotSelectionLayout() {
        let imageRect = CGRect(x: 25, y: 100, width: 300, height: 400)
        let region = NormalizedCropRect(x: 0.2, y: 0.25, width: 0.5, height: 0.5)
        let displayed = CropGeometry.viewRect(for: region, in: imageRect)
        XCTAssertEqual(displayed, CGRect(x: 85, y: 200, width: 150, height: 200))
        XCTAssertEqual(CropGeometry.normalizedRect(from: displayed, in: imageRect), region)
        XCTAssertEqual(CropGeometry.viewRect(for: .full, in: imageRect), imageRect)
    }

    func testPixelExportRoundsEdgesOutward() {
        let region = NormalizedCropRect(x: 0.123, y: 0.234, width: 0.111, height: 0.222)
        XCTAssertEqual(region.pixelRect(in: CGSize(width: 100, height: 100)),
                       CGRect(x: 12, y: 23, width: 12, height: 23))
    }

    func testPixelExportClipsEdgesRatherThanMovingAnOverhangingRegion() {
        let region = NormalizedCropRect(x: -0.1, y: 0.9, width: 0.3, height: 0.3)
        XCTAssertEqual(region.pixelRect(in: CGSize(width: 100, height: 100)),
                       CGRect(x: 0, y: 90, width: 20, height: 10))
        XCTAssertTrue(NormalizedCropRect(x: 2, y: 0, width: 0.2, height: 1)
            .pixelRect(in: CGSize(width: 100, height: 100)).isNull)
        XCTAssertTrue(region.pixelRect(in: .zero).isNull)
    }

    func testQuantizedDisplayUsesExportedEdges() {
        let region = NormalizedCropRect(x: 0.123, y: 0.234, width: 0.111, height: 0.222)
        let pixels = CGSize(width: 100, height: 100)
        let imageRect = CGRect(x: 30, y: 50, width: 200, height: 200)
        let displayed = CropGeometry.selectionRect(for: region, pixels: pixels, in: imageRect)
        XCTAssertEqual(displayed, CGRect(x: 54, y: 96, width: 24, height: 46))
        let roundTrip = CropGeometry.normalizedRect(from: displayed, in: imageRect)
        XCTAssertEqual(roundTrip.pixelRect(in: pixels), CGRect(x: 12, y: 23, width: 12, height: 23))
    }

    func testEveryResizeCornerKeepsItsOppositeCornerFixed() {
        let region = NormalizedCropRect(x: 0.2, y: 0.3, width: 0.5, height: 0.4)
        let cases: [(CropCorner, NormalizedCropRect)] = [
            (.topLeading, .init(x: 0.3, y: 0.4, width: 0.4, height: 0.3)),
            (.topTrailing, .init(x: 0.2, y: 0.4, width: 0.6, height: 0.3)),
            (.bottomLeading, .init(x: 0.3, y: 0.3, width: 0.4, height: 0.5)),
            (.bottomTrailing, .init(x: 0.2, y: 0.3, width: 0.6, height: 0.5))
        ]
        for (corner, expected) in cases {
            let result = region.resized(corner, dx: 0.1, dy: 0.1)
            XCTAssertEqual(result.x, expected.x, accuracy: 1e-12)
            XCTAssertEqual(result.y, expected.y, accuracy: 1e-12)
            XCTAssertEqual(result.width, expected.width, accuracy: 1e-12)
            XCTAssertEqual(result.height, expected.height, accuracy: 1e-12)
        }
    }

    func testTouchMinimumDoesNotExpandAnExistingSmallRegion() {
        let small = NormalizedCropRect(x: 0.4, y: 0.4, width: 0.01, height: 0.02)
        let result = small.resized(.bottomTrailing, dx: -1, dy: -1,
                                   minimumSize: CGSize(width: 0.1, height: 0.1))
        XCTAssertEqual(result.x, 0.4)
        XCTAssertEqual(result.y, 0.4)
        XCTAssertEqual(result.width, 0.01, accuracy: 1e-12)
        XCTAssertEqual(result.height, 0.02, accuracy: 1e-12)
    }

    func testHandleHitTargetsTakePrecedenceOverSelectionMovement() {
        let selection = CGRect(x: 50, y: 50, width: 200, height: 200)
        let handles = CropGeometry.handleRect(for: selection, in: CGSize(width: 300, height: 400))
        // 23 points away is outside the visible dot but inside its touch target.
        XCTAssertEqual(CropGeometry.operation(at: CGPoint(x: 73, y: 73), selection: selection,
                                             handles: handles), .resize(.topLeading))
        XCTAssertEqual(CropGeometry.operation(at: CGPoint(x: 150, y: 150), selection: selection,
                                             handles: handles), .move)
        XCTAssertNil(CropGeometry.operation(at: .zero, selection: selection, handles: handles))
    }

    func testTinySelectionHasSeparateMoveAndResizeTargets() {
        let selection = CGRect(x: 145, y: 195, width: 10, height: 10)
        let handles = CropGeometry.handleRect(for: selection, in: CGSize(width: 300, height: 400))
        XCTAssertEqual(CropGeometry.operation(at: CGPoint(x: 150, y: 200), selection: selection,
                                             handles: handles), .move)
        for corner in CropCorner.allCases {
            XCTAssertEqual(CropGeometry.operation(at: CropGeometry.cornerPoint(corner, in: handles),
                selection: selection, handles: handles), .resize(corner))
        }
    }

    func testHandleTouchAreasRemainInsideCanvasAtImageEdges() {
        let handles = CropGeometry.handleRect(for: CGRect(x: 0, y: 0, width: 300, height: 400),
                                               in: CGSize(width: 300, height: 400))
        XCTAssertEqual(handles, CGRect(x: 24, y: 24, width: 252, height: 352))
    }

    func testSmallCropAtCanvasCornerRetainsAMoveTargetBetweenHandles() {
        let selection = CGRect(x: 0, y: 0, width: 10, height: 10)
        let handles = CropGeometry.handleRect(for: selection, in: CGSize(width: 300, height: 400))
        XCTAssertEqual(CropGeometry.operation(at: CGPoint(x: handles.midX, y: handles.midY),
                                             selection: selection, handles: handles), .move)
    }

    func testCrossingEveryCornerStopsBeforeInversionAndKeepsOppositeFixed() {
        let start = NormalizedCropRect(x: 0.2, y: 0.3, width: 0.5, height: 0.4)
        let cases: [(CropCorner, Double, Double, CropCorner, CGPoint)] = [
            (.topLeading, 2, 2, .bottomTrailing, CGPoint(x: 0.7, y: 0.7)),
            (.topTrailing, -2, 2, .bottomLeading, CGPoint(x: 0.2, y: 0.7)),
            (.bottomLeading, 2, -2, .topTrailing, CGPoint(x: 0.7, y: 0.3)),
            (.bottomTrailing, -2, -2, .topLeading, CGPoint(x: 0.2, y: 0.3))
        ]
        for (corner, dx, dy, opposite, expected) in cases {
            let result = start.resized(corner, dx: dx, dy: dy,
                                       minimumSize: CGSize(width: 0.1, height: 0.1))
            XCTAssertEqual(result.width, 0.1, accuracy: 1e-12)
            XCTAssertEqual(result.height, 0.1, accuracy: 1e-12)
            let point = CropGeometry.cornerPoint(opposite, in: CropGeometry.viewRect(
                for: result, in: CGRect(x: 0, y: 0, width: 1, height: 1)))
            XCTAssertEqual(point.x, expected.x, accuracy: 1e-12)
            XCTAssertEqual(point.y, expected.y, accuracy: 1e-12)
        }
    }

    func testGestureTranslationsUseFrozenStartAndImageSize() {
        var gesture = CropInteraction(start: .centeredDefault, operation: .move)
        let imageRect = CGRect(x: 25, y: 100, width: 300, height: 400)
        gesture.translation = CGSize(width: 30, height: 40)
        let first = gesture.region(in: imageRect)
        gesture.translation = CGSize(width: 60, height: 80)
        let second = gesture.region(in: imageRect)
        XCTAssertEqual(first.x, 0.3, accuracy: 1e-12)
        XCTAssertEqual(second.x, 0.4, accuracy: 1e-12)
        XCTAssertEqual(second.y, 0.4, accuracy: 1e-12)
        XCTAssertEqual(second.width, 0.6)
        XCTAssertEqual(second.height, 0.6)
    }

    func testResizeUsesVisualMinimumAndDoesNotMoveOppositeCorner() {
        var gesture = CropInteraction(start: .centeredDefault, operation: .resize(.topLeading))
        gesture.translation = CGSize(width: 999, height: 999)
        let result = gesture.region(in: CGRect(x: 25, y: 100, width: 300, height: 400))
        XCTAssertEqual(result.width, 48 / 300, accuracy: 1e-12)
        XCTAssertEqual(result.height, 48 / 400, accuracy: 1e-12)
        XCTAssertEqual(result.x + result.width, 0.8, accuracy: 1e-12)
        XCTAssertEqual(result.y + result.height, 0.8, accuracy: 1e-12)
    }

    func testDragStartingOutsideTargetsCannotAcquireSelectionMidGesture() {
        var gesture = CropInteraction(start: .centeredDefault, operation: nil)
        gesture.translation = CGSize(width: 100, height: 100)
        XCTAssertEqual(gesture.region(in: CGRect(x: 0, y: 0, width: 300, height: 400)), .centeredDefault)
    }
}
