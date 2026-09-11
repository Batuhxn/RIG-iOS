import UIKit
import XCTest
@testable import RIG

/// The import pipeline, including the contract that matters most:
/// a failed cutout must never stop a garment being imported.
final class GarmentImportServiceTests: XCTestCase {
    private var directory: URL!
    private var store: GarmentImageStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appending(path: "RIGImportTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = GarmentImageStore(baseDirectory: directory)
    }

    override func tearDownWithError() throws {
        if let directory {
            try? FileManager.default.removeItem(at: directory)
        }
        store = nil
        directory = nil
        try super.tearDownWithError()
    }

    /// Scale is pinned to 1 so a point is a pixel and the dimension assertions
    /// below mean what they say on any simulator.
    private func sampleImageData(size: CGFloat = 640) throws -> Data {
        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format)
        let image = renderer.image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: size, height: size))
            UIColor.systemIndigo.setFill()
            context.fill(CGRect(x: 0, y: 0, width: size / 2, height: size / 2))
        }
        return try XCTUnwrap(image.pngData())
    }

    func testFailedBackgroundRemovalStillImportsTheGarment() async throws {
        let service = GarmentImportService(store: store, backgroundRemover: FailingBackgroundRemover())
        let result = try await service.importImage(try sampleImageData(), garmentID: Fixture.id(1))

        XCTAssertFalse(result.isBackgroundRemoved)
        XCTAssertNil(result.cutoutRelativePath)
        XCTAssertNotNil(result.backgroundRemovalMessage)
        XCTAssertTrue(store.exists(atRelativePath: result.originalRelativePath))
        XCTAssertNotNil(result.thumbnailRelativePath)
    }

    func testPassthroughRemoverIsReportedAsNotIsolated() async throws {
        let service = GarmentImportService(store: store, backgroundRemover: PassthroughBackgroundRemover())
        let result = try await service.importImage(try sampleImageData(), garmentID: Fixture.id(2))

        XCTAssertFalse(result.isBackgroundRemoved)
        XCTAssertNil(result.cutoutRelativePath)
        XCTAssertTrue(store.exists(atRelativePath: result.originalRelativePath))
    }

    func testSuccessfulRemovalWritesACutout() async throws {
        struct IsolatingRemover: GarmentBackgroundRemoving {
            let payload: Data
            func removeBackground(from imageData: Data) async throws -> BackgroundRemovalResult {
                BackgroundRemovalResult(imageData: payload, isolated: true)
            }
        }

        let payload = try sampleImageData(size: 300)
        let service = GarmentImportService(store: store, backgroundRemover: IsolatingRemover(payload: payload))
        let result = try await service.importImage(try sampleImageData(), garmentID: Fixture.id(3))

        XCTAssertTrue(result.isBackgroundRemoved)
        XCTAssertNil(result.backgroundRemovalMessage)
        let cutoutPath = try XCTUnwrap(result.cutoutRelativePath)
        XCTAssertTrue(store.exists(atRelativePath: cutoutPath))
    }

    func testUnreadableDataIsRejected() async {
        let service = GarmentImportService(store: store, backgroundRemover: PassthroughBackgroundRemover())
        do {
            _ = try await service.importImage(Data("not an image".utf8), garmentID: Fixture.id(4))
            XCTFail("Expected an unreadable-image error")
        } catch let error as GarmentImportError {
            XCTAssertEqual(error, .unreadableImage)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testImportedFilesAreOwnedByTheGarmentDirectory() async throws {
        let id = Fixture.id(5)
        let service = GarmentImportService(store: store, backgroundRemover: PassthroughBackgroundRemover())
        let result = try await service.importImage(try sampleImageData(), garmentID: id)

        XCTAssertEqual(GarmentImagePaths.garmentID(fromRelativePath: result.originalRelativePath), id)
        try store.removeAll(for: id)
        XCTAssertFalse(store.exists(atRelativePath: result.originalRelativePath))
    }

    func testLargeImagesAreDownscaled() throws {
        let data = try sampleImageData(size: 3000)
        let resized = try XCTUnwrap(
            GarmentImageProcessing.jpegData(from: data, maxDimension: GarmentImageProcessing.originalMaxDimension)
        )
        let image = try XCTUnwrap(UIImage(data: resized))
        XCTAssertLessThanOrEqual(
            max(image.size.width, image.size.height) * image.scale,
            GarmentImageProcessing.originalMaxDimension + 1
        )
    }

    func testSmallImagesAreNotUpscaled() throws {
        let data = try sampleImageData(size: 120)
        let processed = try XCTUnwrap(GarmentImageProcessing.pngData(from: data, maxDimension: 400))
        let image = try XCTUnwrap(UIImage(data: processed))
        XCTAssertEqual(max(image.size.width, image.size.height) * image.scale, 120, accuracy: 1)
    }

    // MARK: - A cutout's alpha must survive into storage

    /// A PNG with a genuinely transparent region — the alpha the JPEG "original"
    /// path would destroy, and the bug an approved mask must never be routed
    /// through.
    private func transparentImageData(size: CGFloat = 300) throws -> Data {
        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format)
        let image = renderer.image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: size, height: size / 2))
            // The bottom half is left untouched — fully transparent.
        }
        return try XCTUnwrap(image.pngData())
    }

    private actor CallCountingRemover: GarmentBackgroundRemoving {
        private(set) var callCount = 0
        func removeBackground(from imageData: Data) async throws -> BackgroundRemovalResult {
            callCount += 1
            return BackgroundRemovalResult(imageData: imageData, isolated: true)
        }
    }

    private actor FixedCutoutRemover: GarmentBackgroundRemoving {
        let cutout: Data
        private(set) var callCount = 0
        init(cutout: Data) { self.cutout = cutout }
        func removeBackground(from imageData: Data) async throws -> BackgroundRemovalResult {
            callCount += 1
            return BackgroundRemovalResult(imageData: cutout, isolated: true)
        }
    }

    func testBackgroundRemovalRunsExactlyOncePerImport() async throws {
        let remover = CallCountingRemover()
        let service = GarmentImportService(store: store, backgroundRemover: remover)

        _ = try await service.importImage(try sampleImageData(), garmentID: Fixture.id(7))

        let callCount = await remover.callCount
        XCTAssertEqual(callCount, 1, "one import asks the background remover once and no more")
    }

    /// The canonical import writes its cutout as PNG precisely so a Vision
    /// cutout's transparency survives into the stored file. Flattening it
    /// through JPEG would put a white box behind every garment.
    func testAnIsolatedCutoutKeepsItsAlphaInStorage() async throws {
        let remover = FixedCutoutRemover(cutout: try transparentImageData())
        let service = GarmentImportService(store: store, backgroundRemover: remover)

        let result = try await service.importImage(try sampleImageData(), garmentID: Fixture.id(6))

        XCTAssertTrue(result.isBackgroundRemoved)
        XCTAssertNil(result.backgroundRemovalMessage)
        let cutoutPath = try XCTUnwrap(result.cutoutRelativePath)
        XCTAssertTrue(store.exists(atRelativePath: cutoutPath))

        let written = try XCTUnwrap(store.data(atRelativePath: cutoutPath))
        let image = try XCTUnwrap(UIImage(data: written))
        let alphaInfo = image.cgImage?.alphaInfo
        XCTAssertNotNil(alphaInfo)
        XCTAssertNotEqual(alphaInfo, .none, "the cutout's alpha must survive, not be flattened through JPEG")
    }
}
