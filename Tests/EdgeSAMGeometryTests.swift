import XCTest
@testable import RIG

/// `EdgeSAMGeometry` carries every piece of the EdgeSAM adapter's math that
/// does not actually require Core ML — the resize-to-1024 scale factor, the
/// RIG-space-to-model-space box prompt mapping, the mask's bilinear
/// resample, and the threshold/bounding-box step. `EdgeSAMSegmenter` and its
/// `MLModel`/`MLMultiArray`-touching neighbours cannot be exercised without
/// a real Apple toolchain and the bundled model assets — this file is what
/// keeps that limitation from meaning the adapter's actual logic goes
/// untested.
final class EdgeSAMGeometryTests: XCTestCase {
    // MARK: - resizeMetadata

    func testResizeMetadataScalesTheLongestSideToTheModelInputSize() throws {
        let metadata = try XCTUnwrap(EdgeSAMGeometry.resizeMetadata(sourceWidth: 800, sourceHeight: 1600))
        XCTAssertEqual(metadata.resizedHeight, 1024, "the longer side must land exactly on the model's input size")
        XCTAssertEqual(metadata.resizedWidth, 512, "aspect ratio must be preserved: 800/1600 * 1024 = 512")
        XCTAssertEqual(metadata.scale, 1024.0 / 1600.0, accuracy: 0.0001)
    }

    func testResizeMetadataOfAnAlreadySquareSourceFillsTheFrame() {
        let metadata = EdgeSAMGeometry.resizeMetadata(sourceWidth: 1200, sourceHeight: 1200)
        XCTAssertEqual(metadata?.resizedWidth, 1024)
        XCTAssertEqual(metadata?.resizedHeight, 1024)
    }

    func testResizeMetadataOfANonPositiveSourceIsNil() {
        XCTAssertNil(EdgeSAMGeometry.resizeMetadata(sourceWidth: 0, sourceHeight: 100))
        XCTAssertNil(EdgeSAMGeometry.resizeMetadata(sourceWidth: 100, sourceHeight: 0))
        XCTAssertNil(EdgeSAMGeometry.resizeMetadata(sourceWidth: -5, sourceHeight: 100))
    }

    // MARK: - boxPromptCoordinates (RIG-space -> model-space)

    func testBoxPromptCoordinatesOfTheFullImageCoverTheEntireResizedFrame() throws {
        let metadata = EdgeSAMGeometry.resizeMetadata(sourceWidth: 1600, sourceHeight: 800)!
        let coords = try XCTUnwrap(EdgeSAMGeometry.boxPromptCoordinates(for: .full, resizeMetadata: metadata))

        XCTAssertEqual(coords.x0, 0, accuracy: 0.001)
        XCTAssertEqual(coords.y0, 0, accuracy: 0.001)
        // 1600 wide source -> resizedWidth 1024 exactly (the longer side).
        XCTAssertEqual(coords.x1, 1024, accuracy: 0.5)
        // 800 tall -> half of 1024 = 512.
        XCTAssertEqual(coords.y1, 512, accuracy: 0.5)
    }

    func testBoxPromptCoordinatesOfACenteredRegionScaleProportionally() throws {
        // A perfectly square source: scale is exactly 1024/1000 for every axis.
        let metadata = EdgeSAMGeometry.resizeMetadata(sourceWidth: 1000, sourceHeight: 1000)!
        let region = NormalizedCropRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)

        let coords = try XCTUnwrap(EdgeSAMGeometry.boxPromptCoordinates(for: region, resizeMetadata: metadata))

        let scale = metadata.scale
        XCTAssertEqual(coords.x0, 250 * scale, accuracy: 0.01)
        XCTAssertEqual(coords.y0, 250 * scale, accuracy: 0.01)
        XCTAssertEqual(coords.x1, 750 * scale, accuracy: 0.01)
        XCTAssertEqual(coords.y1, 750 * scale, accuracy: 0.01)
    }

    func testBoxPromptCoordinatesOfAnUnusableRegionIsNil() {
        let metadata = EdgeSAMGeometry.resizeMetadata(sourceWidth: 1000, sourceHeight: 1000)!
        let degenerate = NormalizedCropRect(x: 0.2, y: 0.2, width: 0, height: 0.4)
        XCTAssertNil(EdgeSAMGeometry.boxPromptCoordinates(for: degenerate, resizeMetadata: metadata))
    }

    func testBoxPromptCoordinatesClampsAnOutOfBoundsRegionRatherThanExtrapolating() {
        let metadata = EdgeSAMGeometry.resizeMetadata(sourceWidth: 1000, sourceHeight: 1000)!
        // Drawn past the right/bottom edge -- `clamped()` pulls this back
        // inside [0,1] before it ever reaches model space.
        let overshooting = NormalizedCropRect(x: 0.8, y: 0.8, width: 0.5, height: 0.5)

        let coords = EdgeSAMGeometry.boxPromptCoordinates(for: overshooting, resizeMetadata: metadata)

        XCTAssertNotNil(coords)
        XCTAssertLessThanOrEqual(coords!.x1, metadata.scale * 1000 + 0.01)
        XCTAssertLessThanOrEqual(coords!.y1, metadata.scale * 1000 + 0.01)
    }

    // MARK: - bilinearResize (mask-space -> source-space)

    func testBilinearResizeOfAUniformBufferStaysUniform() {
        let source = [Float](repeating: 5, count: 4 * 4)
        let resized = EdgeSAMGeometry.bilinearResize(source, width: 4, height: 4, toWidth: 16, toHeight: 16)

        XCTAssertEqual(resized.count, 16 * 16)
        XCTAssertTrue(resized.allSatisfy { abs($0 - 5) < 0.0001 }, "resampling a constant field must not introduce noise")
    }

    func testBilinearResizeToTheSameSizeIsIdentity() {
        let source: [Float] = [1, 2, 3, 4]
        let resized = EdgeSAMGeometry.bilinearResize(source, width: 2, height: 2, toWidth: 2, toHeight: 2)
        XCTAssertEqual(resized, source)
    }

    func testBilinearResizeUpscalesASimpleGradientMonotonically() {
        // A 2x2 field increasing left-to-right; every row of the upscaled
        // result should also increase left-to-right.
        let source: [Float] = [0, 10, 0, 10]
        let resized = EdgeSAMGeometry.bilinearResize(source, width: 2, height: 2, toWidth: 8, toHeight: 2)

        for row in 0..<2 {
            let rowValues = (0..<8).map { resized[row * 8 + $0] }
            for i in 1..<rowValues.count {
                XCTAssertGreaterThanOrEqual(rowValues[i], rowValues[i - 1] - 0.001)
            }
        }
    }

    func testBilinearResizeOfDegenerateDimensionsIsEmpty() {
        XCTAssertTrue(EdgeSAMGeometry.bilinearResize([], width: 0, height: 4, toWidth: 8, toHeight: 8).isEmpty)
        XCTAssertTrue(EdgeSAMGeometry.bilinearResize([1, 2], width: 2, height: 1, toWidth: 0, toHeight: 4).isEmpty)
    }

    // MARK: - thresholdAndBoundingBox

    func testThresholdAndBoundingBoxOfAnAllNegativeFieldIsNil() {
        let values = [Float](repeating: -1, count: 4 * 4)
        XCTAssertNil(EdgeSAMGeometry.thresholdAndBoundingBox(values, width: 4, height: 4))
    }

    func testThresholdAndBoundingBoxFindsATightBoxAroundForegroundPixels() throws {
        // 4x4 field, all background except a 2x2 foreground block at (1,1)-(2,2).
        var values = [Float](repeating: -1, count: 16)
        for y in 1...2 {
            for x in 1...2 {
                values[y * 4 + x] = 1
            }
        }

        let result = try XCTUnwrap(EdgeSAMGeometry.thresholdAndBoundingBox(values, width: 4, height: 4))

        XCTAssertEqual(result.minX, 1)
        XCTAssertEqual(result.maxX, 2)
        XCTAssertEqual(result.minY, 1)
        XCTAssertEqual(result.maxY, 2)
        XCTAssertEqual(result.boundingRegion.x, 0.25, accuracy: 0.0001)
        XCTAssertEqual(result.boundingRegion.y, 0.25, accuracy: 0.0001)
        XCTAssertEqual(result.boundingRegion.width, 0.5, accuracy: 0.0001)
        XCTAssertEqual(result.boundingRegion.height, 0.5, accuracy: 0.0001)
    }

    func testThresholdAndBoundingBoxOfAFullyForegroundFieldCoversTheWholeFrame() {
        let values = [Float](repeating: 1, count: 4 * 4)
        let result = EdgeSAMGeometry.thresholdAndBoundingBox(values, width: 4, height: 4)

        XCTAssertEqual(result?.boundingRegion, NormalizedCropRect.full)
    }

    func testThresholdAndBoundingBoxHonoursACustomThreshold() {
        let values: [Float] = [0, 0, 0, 6, 0, 0, 0, 0, 0]
        let default0 = EdgeSAMGeometry.thresholdAndBoundingBox(values, width: 3, height: 3)
        let strict = EdgeSAMGeometry.thresholdAndBoundingBox(values, width: 3, height: 3, threshold: 10)

        XCTAssertNotNil(default0, "a single value of 6 clears the default threshold of 0")
        XCTAssertNil(strict, "nothing clears a threshold of 10")
    }

    func testThresholdAndBoundingBoxRejectsAMismatchedBufferSize() {
        XCTAssertNil(EdgeSAMGeometry.thresholdAndBoundingBox([1, 2, 3], width: 4, height: 4))
    }

    // MARK: - promptPointCoordinates / centerPoint (v0.4 Slice 2.1)

    func testPromptPointCoordinatesMapsTheSameWayAsABoxCorner() throws {
        // A point sitting exactly on a region's top-left corner must land at
        // the same model-space pixel `boxPromptCoordinates` would give that
        // corner — both are the same RIG-space-to-model-space scale, with no
        // offset.
        let metadata = EdgeSAMGeometry.resizeMetadata(sourceWidth: 1000, sourceHeight: 1000)!
        let region = NormalizedCropRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        let box = try XCTUnwrap(EdgeSAMGeometry.boxPromptCoordinates(for: region, resizeMetadata: metadata))

        let point = EdgeSAMGeometry.PromptPoint(x: 0.25, y: 0.25, isPositive: true)
        let coords = try XCTUnwrap(EdgeSAMGeometry.promptPointCoordinates(for: point, resizeMetadata: metadata))

        XCTAssertEqual(coords.x, box.x0, accuracy: 0.001)
        XCTAssertEqual(coords.y, box.y0, accuracy: 0.001)
    }

    func testPromptPointCoordinatesClampsAnOutOfRangePointRatherThanExtrapolating() throws {
        let metadata = EdgeSAMGeometry.resizeMetadata(sourceWidth: 1000, sourceHeight: 1000)!
        let point = EdgeSAMGeometry.PromptPoint(x: 1.5, y: -0.5, isPositive: false)

        let coords = try XCTUnwrap(EdgeSAMGeometry.promptPointCoordinates(for: point, resizeMetadata: metadata))

        XCTAssertEqual(coords.x, metadata.scale * 1000, accuracy: 0.001, "clamped to 1.0, not extrapolated past it")
        XCTAssertEqual(coords.y, 0, accuracy: 0.001, "clamped to 0.0, not extrapolated below it")
    }

    func testPromptPointCoordinatesOfANonFinitePointIsNil() {
        let metadata = EdgeSAMGeometry.resizeMetadata(sourceWidth: 1000, sourceHeight: 1000)!
        let point = EdgeSAMGeometry.PromptPoint(x: .nan, y: 0.5, isPositive: true)
        XCTAssertNil(EdgeSAMGeometry.promptPointCoordinates(for: point, resizeMetadata: metadata))
    }

    func testCenterPointOfARegionIsItsMidpointAndPositive() throws {
        let region = NormalizedCropRect(x: 0.2, y: 0.4, width: 0.4, height: 0.2)
        let center = try XCTUnwrap(EdgeSAMGeometry.centerPoint(of: region))

        XCTAssertEqual(center.x, 0.4, accuracy: 0.0001)
        XCTAssertEqual(center.y, 0.5, accuracy: 0.0001)
        XCTAssertTrue(center.isPositive, "the automatic box anchor is always an include point")
    }

    func testCenterPointOfAnUnusableRegionIsNil() {
        let degenerate = NormalizedCropRect(x: 0.2, y: 0.2, width: 0, height: 0.4)
        XCTAssertNil(EdgeSAMGeometry.centerPoint(of: degenerate))
    }

    // MARK: - promptEntries (v0.4 Slice 2.1)

    func testPromptEntriesPlacesTheBoxCornersFirstThenPointsInGivenOrder() throws {
        let metadata = EdgeSAMGeometry.resizeMetadata(sourceWidth: 1000, sourceHeight: 1000)!
        let region = NormalizedCropRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4)
        let points = [
            EdgeSAMGeometry.PromptPoint(x: 0.3, y: 0.3, isPositive: true),
            EdgeSAMGeometry.PromptPoint(x: 0.5, y: 0.5, isPositive: false),
        ]

        let entries = try XCTUnwrap(EdgeSAMGeometry.promptEntries(for: region, points: points, resizeMetadata: metadata))

        XCTAssertEqual(entries.count, 4)
        XCTAssertEqual(entries[0].label, EdgeSAMGeometry.boxTopLeftLabel)
        XCTAssertEqual(entries[1].label, EdgeSAMGeometry.boxBottomRightLabel)
        XCTAssertEqual(entries[2].label, EdgeSAMGeometry.positivePointLabel)
        XCTAssertEqual(entries[3].label, EdgeSAMGeometry.negativePointLabel)
    }

    func testPromptEntriesWithNoPointsIsJustTheBoxsTwoCorners() throws {
        let metadata = EdgeSAMGeometry.resizeMetadata(sourceWidth: 1000, sourceHeight: 1000)!
        let entries = try XCTUnwrap(
            EdgeSAMGeometry.promptEntries(for: .full, points: [], resizeMetadata: metadata)
        )
        XCTAssertEqual(entries.count, 2, "byte-identical to the box-only prompt v0.4 Slice 2 already shipped")
        XCTAssertEqual(entries.map(\.label), [EdgeSAMGeometry.boxTopLeftLabel, EdgeSAMGeometry.boxBottomRightLabel])
    }

    func testPromptEntriesIsNilWhenTheBoxItselfIsUnusable() {
        let metadata = EdgeSAMGeometry.resizeMetadata(sourceWidth: 1000, sourceHeight: 1000)!
        let degenerate = NormalizedCropRect(x: 0.2, y: 0.2, width: 0, height: 0.4)
        XCTAssertNil(EdgeSAMGeometry.promptEntries(for: degenerate, points: [], resizeMetadata: metadata))
    }

    func testPromptEntriesRejectsMoreEntriesThanTheDecoderDeclares() {
        let metadata = EdgeSAMGeometry.resizeMetadata(sourceWidth: 1000, sourceHeight: 1000)!
        // 2 box corners + 15 points = 17, one past the decoder's 16-entry cap.
        let tooManyPoints = (0..<15).map {
            EdgeSAMGeometry.PromptPoint(x: Double($0) / 20, y: 0.5, isPositive: true)
        }
        XCTAssertNil(EdgeSAMGeometry.promptEntries(for: .full, points: tooManyPoints, resizeMetadata: metadata))

        // 2 box corners + 14 points = 16 is exactly at the cap and must succeed.
        let atCapacity = Array(tooManyPoints.dropLast())
        XCTAssertEqual(
            EdgeSAMGeometry.promptEntries(for: .full, points: atCapacity, resizeMetadata: metadata)?.count, 16
        )
    }
}
