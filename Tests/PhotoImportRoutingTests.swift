import Foundation
import XCTest
@testable import RIG

/// The one decision the unified import flow makes.
///
/// The point of this suite is that the user never chooses between "single" and
/// "bulk": the count decides, and the rule lives in one pure function rather
/// than scattered through a view.
final class PhotoImportRoutingTests: XCTestCase {
    func testAnEmptySelectionMeansNothingToRoute() {
        XCTAssertEqual(PhotoImportRouter.route(selectionCount: 0), .awaitingSelection)
    }

    func testANegativeCountIsTreatedAsNoSelectionRatherThanTrusted() {
        XCTAssertEqual(PhotoImportRouter.route(selectionCount: -1), .awaitingSelection)
    }

    func testOnePhotoUsesTheSingleGarmentFlow() {
        XCTAssertEqual(PhotoImportRouter.route(selectionCount: 1), .singleGarment)
    }

    func testTwoPhotosUseTheBulkQueue() {
        XCTAssertEqual(PhotoImportRouter.route(selectionCount: 2), .bulkReview(count: 2))
    }

    func testAFullSelectionUsesTheBulkQueue() {
        let limit = BulkImportQueue.maximumSelectionCount
        XCTAssertEqual(PhotoImportRouter.route(selectionCount: limit), .bulkReview(count: limit))
    }

    func testAnOverlongSelectionIsCappedRatherThanRefused() {
        let limit = BulkImportQueue.maximumSelectionCount
        XCTAssertEqual(PhotoImportRouter.route(selectionCount: limit + 9), .bulkReview(count: limit))
    }

    func testEveryCountFromTwoUpwardsStaysInTheQueue() {
        for count in 2...BulkImportQueue.maximumSelectionCount {
            XCTAssertEqual(
                PhotoImportRouter.route(selectionCount: count),
                .bulkReview(count: count),
                "count \(count) should stay in the bulk queue"
            )
        }
    }

    /// There is exactly one import path now — no third route can appear
    /// without this stopping compiling.
    func testThePickerLimitIsTheBulkQueueLimit() {
        XCTAssertEqual(PhotoImportRouter.maximumSelectionCount, BulkImportQueue.maximumSelectionCount)
    }

    func testTheRouteSetIsExhaustedByThreeCases() {
        let routes: [PhotoImportRoute] = [.awaitingSelection, .singleGarment, .bulkReview(count: 3)]
        for route in routes {
            switch route {
            case .awaitingSelection, .singleGarment, .bulkReview:
                continue
            }
        }
        XCTAssertEqual(routes.count, 3)
    }
}
