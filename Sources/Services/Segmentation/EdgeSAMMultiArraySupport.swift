import CoreML
import Foundation

/// The one place in this adapter that reads a Core ML *output*
/// `MLMultiArray`'s raw memory into plain Swift data.
///
/// `EdgeSAMSegmenter` (caching the encoder's `image_embeddings` output) and
/// `EdgeSAMMaskConversion` (reading the decoder's `masks`/`scores` outputs)
/// both used to do this themselves, each with a flat `dataPointer` +
/// linear-index read that silently assumed the array's memory was
/// contiguous (row-major) for its own shape. Core ML never promises that
/// for an output array — see `EdgeSAMGeometry.reorderToContiguous`'s doc
/// comment, and `docs/EDGESAM_PROVENANCE.md`, "Regression: the deep-copy
/// strides bug", for the real-device failure this caused. Routing every
/// such read through this one function is what makes "always honour
/// `strides`" a fact about the adapter rather than a rule every call site
/// has to remember on its own.
enum EdgeSAMMultiArraySupport {
    /// Returns every element of `array` as a plain, contiguous `[Float]` in
    /// row-major order for `array.shape` — regardless of how `array`'s own
    /// memory is actually laid out. `nil` if `array` is not `.float32`, has
    /// no dimensions, or its `shape`/`strides` disagree in length; the
    /// reordering itself (and its own further validation) is
    /// `EdgeSAMGeometry.reorderToContiguous`.
    static func floatElements(
        of array: MLMultiArray, diagnostics: EdgeSAMDiagnostics = EdgeSAMDiagnostics(), name: String = "embedding"
    ) -> [Float]? {
        guard array.dataType == .float32 else {
            diagnostics.event("tensorReadFailure", ["tensor": name, "guard": "dataType != float32", "actual": "\(array.dataType.rawValue)"])
            return nil
        }
        let shape = array.shape.map(\.intValue)
        let strides = array.strides.map(\.intValue)
        guard !shape.isEmpty, shape.count == strides.count else {
            diagnostics.event("tensorReadFailure", ["tensor": name, "guard": "empty shape or shape/stride rank mismatch"])
            return nil
        }

        // The span `dataPointer` must be bound across is whatever the
        // *declared* strides can reach — not `array.count` (the logical
        // element count), which can be smaller than a padded buffer's real
        // extent. `reorderToContiguous` re-validates this same bound
        // against the buffer it is actually handed, below.
        let maxOffset = zip(shape, strides).reduce(0) { $0 + ($1.0 - 1) * $1.1 }
        guard maxOffset >= 0 else {
            diagnostics.event("tensorReadFailure", ["tensor": name, "guard": "maxOffset < 0", "maxOffset": "\(maxOffset)"])
            return nil
        }
        let span = max(maxOffset + 1, array.count)
        let pointer = array.dataPointer.bindMemory(to: Float32.self, capacity: span)
        let buffer = Array(UnsafeBufferPointer(start: pointer, count: span))

        let result = EdgeSAMGeometry.reorderToContiguous(buffer, shape: shape, strides: strides)
        if result == nil {
            diagnostics.event("tensorReadFailure", ["tensor": name, "guard": "reorder validation", "shape": "\(shape)",
                                                     "strides": "\(strides)", "bufferCount": "\(span)", "maxOffset": "\(maxOffset)"])
        }
        return result
    }
}
