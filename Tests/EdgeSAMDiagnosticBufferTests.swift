#if DEBUG
import XCTest
@testable import RIG

final class EdgeSAMDiagnosticBufferTests: XCTestCase {
    func testRecordLimitKeepsNewestAndReportsDroppedRecords() {
        let buffer = EdgeSAMDiagnosticBuffer(byteLimit: 100, recordLimit: 2)
        buffer.append("first")
        buffer.append("second")
        buffer.append("third")
        XCTAssertEqual(buffer.snapshot(), "[RIG-EdgeSAM] buffer records=2 dropped=1\nsecond\nthird")
    }

    func testByteLimitCountsUTF8AndNewlinesWithoutSplittingRecords() {
        let buffer = EdgeSAMDiagnosticBuffer(byteLimit: 7, recordLimit: 10)
        buffer.append("éé") // Five bytes including the newline.
        buffer.append("ab") // Three more bytes, forcing the first record out.
        XCTAssertEqual(buffer.snapshot(), "[RIG-EdgeSAM] buffer records=1 dropped=1\nab")
    }

    func testOversizedRecordDoesNotEvictPriorEvidence() {
        let buffer = EdgeSAMDiagnosticBuffer(byteLimit: 6, recordLimit: 10)
        buffer.append("ok")
        buffer.append("oversized")
        XCTAssertEqual(buffer.snapshot(), "[RIG-EdgeSAM] buffer records=1 dropped=1\nok")
    }

    func testClearResetsRecordsAndDropCountButPreservesExperimentSetting() {
        let buffer = EdgeSAMDiagnosticBuffer(byteLimit: 6, recordLimit: 1)
        XCTAssertFalse(buffer.knownGoodFirstPrompt)
        buffer.knownGoodFirstPrompt = true
        buffer.append("old")
        buffer.append("new")
        buffer.clear()
        XCTAssertEqual(buffer.snapshot(), "[RIG-EdgeSAM] buffer records=0 dropped=0\n")
        XCTAssertTrue(buffer.knownGoodFirstPrompt)
    }

    func testConcurrentAppendRetainsWholeRecordsWithinLimit() {
        let buffer = EdgeSAMDiagnosticBuffer(byteLimit: 10_000, recordLimit: 50)
        DispatchQueue.concurrentPerform(iterations: 100) { index in buffer.append("record-\(index)") }
        let lines = buffer.snapshot().split(separator: "\n")
        XCTAssertEqual(lines.count, 51)
        XCTAssertEqual(lines.first, "[RIG-EdgeSAM] buffer records=50 dropped=50")
        XCTAssertEqual(Set(lines.dropFirst()).count, 50)
        XCTAssertTrue(lines.dropFirst().allSatisfy { $0.hasPrefix("record-") })
    }
}
#endif
