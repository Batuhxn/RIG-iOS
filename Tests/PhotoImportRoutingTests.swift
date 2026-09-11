import Foundation
import XCTest
@testable import RIG

/// The one decision the unified import flow makes.
///
/// The point of this suite is that the user never chooses between "single" and
/// "bulk": the count decides, and the rule lives in one pure function rather
/// than scattered through a view.
final class PhotoImportRoutingTests: XCTestCase {
    func testNoIntentMeansNothingToRoute() {
        XCTAssertEqual(PhotoImportRouter.route(for: nil, selectionCount: 5), .awaitingSelection)
    }

    func testAnEmptySelectionMeansNothingToRoute() {
        for intent in PhotoImportIntent.allCases {
            XCTAssertEqual(PhotoImportRouter.route(for: intent, selectionCount: 0), .awaitingSelection)
            XCTAssertEqual(PhotoImportRouter.route(for: intent, selectionCount: -1), .awaitingSelection)
        }
    }

    func testOneIndividualPhotoUsesTheSingleGarmentFlow() {
        XCTAssertEqual(
            PhotoImportRouter.route(for: .individualItems, selectionCount: 1),
            .singleGarment
        )
    }

    func testTwoIndividualPhotosUseTheBulkQueue() {
        XCTAssertEqual(
            PhotoImportRouter.route(for: .individualItems, selectionCount: 2),
            .bulkReview(count: 2)
        )
    }

    func testAFullSelectionUsesTheBulkQueue() {
        let limit = BulkImportQueue.maximumSelectionCount
        XCTAssertEqual(
            PhotoImportRouter.route(for: .individualItems, selectionCount: limit),
            .bulkReview(count: limit)
        )
    }

    func testAnOverlongSelectionIsCappedRatherThanRefused() {
        let limit = BulkImportQueue.maximumSelectionCount
        XCTAssertEqual(
            PhotoImportRouter.route(for: .individualItems, selectionCount: limit + 9),
            .bulkReview(count: limit)
        )
    }

    func testEveryCountFromTwoUpwardsStaysInTheQueue() {
        for count in 2...BulkImportQueue.maximumSelectionCount {
            XCTAssertEqual(
                PhotoImportRouter.route(for: .individualItems, selectionCount: count),
                .bulkReview(count: count),
                "count \(count) should stay in the bulk queue"
            )
        }
    }

    func testAnOutfitPhotoOpensTheExtractionSession() {
        XCTAssertEqual(
            PhotoImportRouter.route(for: .outfitPhoto, selectionCount: 1),
            .outfitSession
        )
    }

    func testOutfitModeTakesExactlyOneSourcePhoto() {
        XCTAssertEqual(PhotoImportIntent.outfitPhoto.maximumSelectionCount, 1)
    }

    func testIndividualModeSharesTheBulkSelectionLimit() {
        XCTAssertEqual(
            PhotoImportIntent.individualItems.maximumSelectionCount,
            BulkImportQueue.maximumSelectionCount
        )
    }

    func testEveryIntentIsPresentableToSomeoneWhoKnowsNothing() {
        for intent in PhotoImportIntent.allCases {
            XCTAssertFalse(intent.title.isEmpty)
            XCTAssertFalse(intent.subtitle.isEmpty)
            XCTAssertFalse(intent.symbolName.isEmpty)
            XCTAssertEqual(intent.id, intent.rawValue)
        }
        XCTAssertEqual(PhotoImportIntent.allCases.count, 2)
    }
}
