import Foundation

/// Owns one outfit source's cached embedding and the "encode once, decode
/// many" reuse built around it.
///
/// `prepare(source:)` encodes a source image once and caches the resulting
/// token; `proposeMask(for:source:)` can then be called any number of times
/// — once per manually drawn region — against that same cached token without
/// paying the encoder's cost again. Even though v0.4 Slice 2 only ever draws
/// one box at a time, this is what lets a later automatic multi-candidate
/// proposer reuse the same embedding without a rewrite here.
///
/// An actor because every call is expected to arrive from SwiftUI's main
/// actor and must never block it — encoding and decoding run on whatever
/// executor the underlying `GarmentSegmenting` implementation uses — and
/// because "the latest prompt wins" (below) needs its bookkeeping to be
/// mutated safely by overlapping calls.
actor OutfitEmbeddingSession {
    private let segmenter: any GarmentSegmenting

    private var cachedSourceHash: Int?
    private var cachedToken: SegmentationSourceToken?
    /// The most recently issued prompt's identifier. A `segment` call whose
    /// answer comes back after a newer prompt has already been issued is
    /// stale and must not be shown — `proposeMask(for:source:)` enforces this
    /// itself, so a caller never has to compare identifiers by hand.
    private var latestPromptID: UUID?

    init(segmenter: any GarmentSegmenting) {
        self.segmenter = segmenter
    }

    var isAvailable: Bool {
        get async { await segmenter.isAvailable }
    }

    /// Ensures `imageData` is the encoded source, computing a fresh embedding
    /// only when the source has actually changed or nothing is cached yet. A
    /// second call with the same bytes is free.
    @discardableResult
    func prepare(source imageData: Data) async throws -> SegmentationSourceToken {
        let hash = imageData.hashValue
        if let cachedToken, cachedSourceHash == hash {
            return cachedToken
        }
        let token = try await segmenter.encodeSource(imageData)
        cachedToken = token
        cachedSourceHash = hash
        return token
    }

    /// Runs one prompt against the cached embedding, encoding first if
    /// nothing is cached yet or `imageData` differs from what is cached.
    ///
    /// `points` carries any positive/negative refinement points to send
    /// alongside the box, in addition to it — empty for a fresh, unrefined
    /// proposal. Passing the same `imageData` across many calls (one per
    /// garment in a sitting, or one per refinement of the same garment) is
    /// exactly the "encode once, decode many" reuse this actor exists for:
    /// `prepare(source:)` above only re-encodes when the bytes actually
    /// change, so a second, third, or Nth garment cut from the same outfit
    /// photo reuses the first garment's embedding rather than paying the
    /// encoder's cost again.
    ///
    /// A prompt becomes "the latest" the instant it is issued, before its
    /// (possibly slow) decode even starts. If a newer prompt is issued before
    /// this one's decode finishes, this call throws `.stalePrompt` instead of
    /// returning a result nobody asked for anymore — a caller awaiting this
    /// method never has to separately check whether its own answer is still
    /// wanted. Cooperative `Task` cancellation is honoured at each await
    /// boundary for the same reason: a view that has gone away should not
    /// pay for, or receive, a result it can no longer show.
    func proposeMask(
        for region: NormalizedCropRect, source imageData: Data, points: [EdgeSAMGeometry.PromptPoint] = []
    ) async throws -> SegmentationMaskResult {
        try Task.checkCancellation()
        let token = try await prepare(source: imageData)
        try Task.checkCancellation()

        let promptID = UUID()
        latestPromptID = promptID

        let result = try await segmenter.segment(region: region, points: points, in: token)
        try Task.checkCancellation()

        guard latestPromptID == promptID else {
            throw SegmentationError.stalePrompt
        }
        return result
    }

    /// Session closes, the source image changes, or a caller otherwise
    /// decides cached AI state must not outlive it: drop the cached token and
    /// the record of the latest prompt, so nothing in flight can be mistaken
    /// for current after this call returns.
    func invalidate() {
        cachedToken = nil
        cachedSourceHash = nil
        latestPromptID = nil
    }
}
