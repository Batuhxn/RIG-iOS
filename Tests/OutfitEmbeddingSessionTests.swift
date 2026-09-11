import XCTest
@testable import RIG

/// `NormalizedCropRect` is only `Equatable` in production code — nothing
/// there ever needs to key a collection by one, and it isn't this test
/// target's place to add that retroactively. `GatedSegmenter` below needs to
/// gate two overlapping prompts independently by the region each was issued
/// for, so it keys its bookkeeping by this small test-local wrapper instead.
private struct RegionKey: Hashable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    init(_ region: NormalizedCropRect) {
        x = region.x
        y = region.y
        width = region.width
        height = region.height
    }
}

/// `OutfitEmbeddingSession` is the actor that owns "encode once, decode
/// many", cancellation, and "the latest prompt wins" staleness — the part of
/// the AI mask flow that most needs a deterministic test, since a real
/// EdgeSAM adapter cannot run in this environment at all.
final class OutfitEmbeddingSessionTests: XCTestCase {
    /// Counts calls; every encode/segment succeeds immediately. Enough for
    /// the caching and availability tests, which do not need to control
    /// ordering between overlapping calls.
    private actor FakeSegmenter: GarmentSegmenting {
        private(set) var encodeCallCount = 0
        private(set) var segmentCallCount = 0
        var isAvailable: Bool { get async { true } }

        func encodeSource(_ imageData: Data) async throws -> SegmentationSourceToken {
            encodeCallCount += 1
            return SegmentationSourceToken(id: UUID())
        }

        func segment(
            region: NormalizedCropRect,
            in token: SegmentationSourceToken
        ) async throws -> SegmentationMaskResult {
            segmentCallCount += 1
            return SegmentationMaskResult(cutoutData: Data([0xAA]), boundingRegion: region, qualityScore: 0.9)
        }
    }

    /// A segmenter whose `segment(region:in:)` suspends until the test
    /// explicitly releases it, keyed by region. This is what makes the
    /// staleness test deterministic instead of relying on a sleep-based race:
    /// the test controls the exact order in which two overlapping prompts'
    /// decodes complete.
    private actor GatedSegmenter: GarmentSegmenting {
        private var continuations: [RegionKey: CheckedContinuation<Void, Never>] = [:]
        private var released: Set<RegionKey> = []
        var isAvailable: Bool { get async { true } }

        func encodeSource(_ imageData: Data) async throws -> SegmentationSourceToken {
            SegmentationSourceToken(id: UUID())
        }

        func segment(
            region: NormalizedCropRect,
            in token: SegmentationSourceToken
        ) async throws -> SegmentationMaskResult {
            await waitUntilReleased(region)
            return SegmentationMaskResult(cutoutData: Data([0xBB]), boundingRegion: region, qualityScore: nil)
        }

        private func waitUntilReleased(_ region: NormalizedCropRect) async {
            let key = RegionKey(region)
            if released.contains(key) { return }
            await withCheckedContinuation { continuation in
                continuations[key] = continuation
            }
        }

        /// Lets a gated `segment` call for `region` proceed. Safe to call
        /// before or after that call has actually started waiting.
        func release(_ region: NormalizedCropRect) {
            let key = RegionKey(region)
            released.insert(key)
            if let continuation = continuations.removeValue(forKey: key) {
                continuation.resume()
            }
        }
    }

    private func region(_ seed: Double) -> NormalizedCropRect {
        NormalizedCropRect(x: seed, y: 0.1, width: 0.4, height: 0.4)
    }

    private func sourceData(_ byte: UInt8 = 1) -> Data {
        Data([byte, byte, byte])
    }

    func testPrepareCachesPerSourceSoASecondCallWithTheSameBytesDoesNotReencode() async throws {
        let segmenter = FakeSegmenter()
        let session = OutfitEmbeddingSession(segmenter: segmenter)
        let data = sourceData()

        _ = try await session.prepare(source: data)
        _ = try await session.prepare(source: data)

        let count = await segmenter.encodeCallCount
        XCTAssertEqual(count, 1, "the same source bytes must only be encoded once")
    }

    func testPrepareReencodesWhenTheSourceActuallyChanges() async throws {
        let segmenter = FakeSegmenter()
        let session = OutfitEmbeddingSession(segmenter: segmenter)

        _ = try await session.prepare(source: sourceData(1))
        _ = try await session.prepare(source: sourceData(2))

        let count = await segmenter.encodeCallCount
        XCTAssertEqual(count, 2, "a genuinely different source must be re-encoded")
    }

    func testProposeMaskHappyPathReturnsTheSegmentersResult() async throws {
        let segmenter = FakeSegmenter()
        let session = OutfitEmbeddingSession(segmenter: segmenter)

        let result = try await session.proposeMask(for: region(0.1), source: sourceData())

        XCTAssertEqual(result.cutoutData, Data([0xAA]))
        let encodeCount = await segmenter.encodeCallCount
        let segmentCount = await segmenter.segmentCallCount
        XCTAssertEqual(encodeCount, 1)
        XCTAssertEqual(segmentCount, 1)
    }

    func testDecodingManyPromptsAgainstTheSameSourceOnlyEncodesOnce() async throws {
        let segmenter = FakeSegmenter()
        let session = OutfitEmbeddingSession(segmenter: segmenter)
        let data = sourceData()

        _ = try await session.proposeMask(for: region(0.1), source: data)
        _ = try await session.proposeMask(for: region(0.2), source: data)
        _ = try await session.proposeMask(for: region(0.3), source: data)

        let encodeCount = await segmenter.encodeCallCount
        let segmentCount = await segmenter.segmentCallCount
        XCTAssertEqual(encodeCount, 1, "three prompts against one source must still be one encode")
        XCTAssertEqual(segmentCount, 3)
    }

    /// Two prompts are issued back to back; the first's decode is still
    /// gated when the second is issued, which makes the second "the latest"
    /// before either has answered. Releasing the first only after the second
    /// has already been issued must make the first throw `.stalePrompt`
    /// rather than return a result nobody asked for anymore.
    func testASupersededPromptThrowsStalePromptInsteadOfReturningItsResult() async throws {
        let segmenter = GatedSegmenter()
        let session = OutfitEmbeddingSession(segmenter: segmenter)
        let data = sourceData()
        let firstRegion = region(0.1)
        let secondRegion = region(0.2)

        // Prime the cache so both prompts below only ever call `segment`,
        // never a second `encodeSource` racing against the gate.
        _ = try await session.prepare(source: data)

        let firstTask = Task { try await session.proposeMask(for: firstRegion, source: data) }
        // Give the first call a chance to actually reach the gate before the
        // second prompt supersedes it.
        try await Task.sleep(nanoseconds: 20_000_000)

        let secondTask = Task { try await session.proposeMask(for: secondRegion, source: data) }
        try await Task.sleep(nanoseconds: 20_000_000)

        // Release the newer prompt first, then the superseded one, so the
        // ordering the assertion depends on is fully under the test's
        // control rather than left to scheduling.
        await segmenter.release(secondRegion)
        let secondResult = try await secondTask.value
        XCTAssertEqual(secondResult.boundingRegion, secondRegion)

        await segmenter.release(firstRegion)
        do {
            _ = try await firstTask.value
            XCTFail("a prompt superseded before it answered must throw .stalePrompt")
        } catch let error as SegmentationError {
            XCTAssertEqual(error, .stalePrompt)
        }
    }

    func testInvalidateClearsTheCacheForcingAReencodeOnTheNextPrepare() async throws {
        let segmenter = FakeSegmenter()
        let session = OutfitEmbeddingSession(segmenter: segmenter)
        let data = sourceData()

        _ = try await session.prepare(source: data)
        await session.invalidate()
        _ = try await session.prepare(source: data)

        let count = await segmenter.encodeCallCount
        XCTAssertEqual(count, 2, "invalidate() must discard the cached token, not just the latest prompt id")
    }

    func testIsAvailableReflectsTheUnderlyingSegmenter() async {
        let session = OutfitEmbeddingSession(segmenter: UnavailableSegmenter())
        let available = await session.isAvailable
        XCTAssertFalse(available)
    }

    func testACancelledTaskThrowsCancellationErrorRatherThanReturningAResult() async throws {
        let segmenter = GatedSegmenter()
        let session = OutfitEmbeddingSession(segmenter: segmenter)
        let data = sourceData()
        let target = region(0.1)

        let task = Task { try await session.proposeMask(for: target, source: data) }
        try await Task.sleep(nanoseconds: 20_000_000)
        task.cancel()
        await segmenter.release(target)

        do {
            _ = try await task.value
            XCTFail("a cancelled task must not return a mask result")
        } catch is CancellationError {
            // expected
        } catch let error as SegmentationError {
            XCTFail("expected CancellationError, got SegmentationError.\(error)")
        }
    }
}
