import ImageIO
import SwiftUI
import UIKit
import XCTest
@testable import RIG

final class GarmentCropRasterTests: XCTestCase {
    // Six different cells make flips, rotations and wrong crop origins observable.
    private let colors: [UIColor] = [.red, .green, .blue, .yellow, .magenta, .cyan]

    private func fixture() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: 60, height: 40), format: format).image { ctx in
            for index in 0..<6 {
                colors[index].setFill()
                ctx.fill(CGRect(x: (index % 3) * 20, y: (index / 3) * 20, width: 20, height: 20))
            }
        }
    }

    private func rgb(_ image: CGImage, x: Int, y: Int) throws -> [UInt8] {
        let pixel = try XCTUnwrap(image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)))
        var bytes = [UInt8](repeating: 0, count: 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: 1, height: 1,
                bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return Array(bytes.prefix(3))
    }

    func testAllEXIFOrientationsProduceUprightPixelsAndMatchingCrops() throws {
        let original = try XCTUnwrap(fixture().cgImage)
        // EXIF order 1...8; expected cells in upright, top-to-bottom row order.
        let orders = [[0,1,2,3,4,5], [2,1,0,5,4,3], [5,4,3,2,1,0], [3,4,5,0,1,2],
                      [0,3,1,4,2,5], [3,0,4,1,5,2], [5,2,4,1,3,0], [2,5,1,4,0,3]]
        for orientation in 1...8 {
            let bytes = NSMutableData()
            let destination = try XCTUnwrap(CGImageDestinationCreateWithData(bytes, "public.jpeg" as CFString, 1, nil))
            CGImageDestinationAddImage(destination, original, [
                kCGImagePropertyOrientation: orientation,
                kCGImageDestinationLossyCompressionQuality: 1.0
            ] as CFDictionary)
            XCTAssertTrue(CGImageDestinationFinalize(destination))
            let raw = bytes as Data
            let upright = GarmentImageProcessing.normalizedOrientation(try XCTUnwrap(UIImage(data: raw)))
            XCTAssertEqual(upright.imageOrientation, .up)
            let columns = orientation <= 4 ? 3 : 2
            let rows = orientation <= 4 ? 2 : 3
            XCTAssertEqual(upright.cgImage?.width, columns * 20)
            XCTAssertEqual(upright.cgImage?.height, rows * 20)
            for (index, cell) in orders[orientation - 1].enumerated() {
                let region = NormalizedCropRect(x: Double(index % columns) / Double(columns),
                    y: Double(index / columns) / Double(rows),
                    width: 1 / Double(columns), height: 1 / Double(rows))
                let data = try XCTUnwrap(GarmentImageCropping.croppedData(from: raw, region: region))
                let cropped = try XCTUnwrap(UIImage(data: data)?.cgImage)
                XCTAssertEqual(cropped.width, 20)
                XCTAssertEqual(cropped.height, 20)
                let actual = try rgb(cropped, x: 10, y: 10)
                let expected = try rgb(original, x: (cell % 3) * 20 + 10, y: (cell / 3) * 20 + 10)
                for channel in 0..<3 {
                    XCTAssertEqual(Double(actual[channel]), Double(expected[channel]), accuracy: 12,
                                   "EXIF \(orientation), cell \(index)")
                }
            }
        }
    }

    func testRawCropContainsExactlyTheOutwardRoundedSourcePixels() throws {
        let source = fixture()
        let sourcePixels = try XCTUnwrap(source.cgImage)
        let region = NormalizedCropRect(x: 0.31, y: 0.24, width: 0.36, height: 0.52)
        let data = try XCTUnwrap(GarmentImageCropping.croppedData(from: try XCTUnwrap(source.pngData()), region: region))
        let cropped = try XCTUnwrap(UIImage(data: data)?.cgImage)
        // floor(18.6), floor(9.6), ceil(40.2), ceil(30.4)
        XCTAssertEqual(cropped.width, 23)
        XCTAssertEqual(cropped.height, 22)
        for y in 0..<22 {
            for x in 0..<23 {
                XCTAssertEqual(try rgb(cropped, x: x, y: y), try rgb(sourcePixels, x: x + 18, y: y + 9))
            }
        }
    }

    @MainActor
    func testRenderedSelectionBorderMatchesRawCropInFixedCanvas() throws {
        let image = fixture()
        let region = NormalizedCropRect(x: 0.2, y: 0.25, width: 0.6, height: 0.5)
        let renderer = ImageRenderer(content: GarmentCropView(image: image,
            sourcePixelSize: CGSize(width: 60, height: 40), region: .constant(region))
            .frame(width: 300, height: 400))
        renderer.scale = 1
        let rendered = try XCTUnwrap(renderer.cgImage)
        // Image is (0,100,300,200); selected edges are (60,150)-(240,250).
        let border = try rgb(rendered, x: 150, y: 150)
        XCTAssertTrue(border.allSatisfy { $0 > 230 })
        let exported = try XCTUnwrap(GarmentImageCropping.croppedData(
            from: try XCTUnwrap(image.pngData()), region: region))
        let crop = try XCTUnwrap(UIImage(data: exported)?.cgImage)
        XCTAssertEqual(crop.width, 36)
        XCTAssertEqual(crop.height, 20)
        XCTAssertEqual(try rgb(crop, x: 0, y: 0), try rgb(try XCTUnwrap(image.cgImage), x: 12, y: 10))
    }
}
