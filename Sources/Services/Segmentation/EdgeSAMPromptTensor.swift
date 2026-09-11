import CoreML
import Foundation

/// Packs `EdgeSAMGeometry.promptEntries` — a box's two corners plus any
/// number of refinement points — into the `point_coords`/`point_labels`
/// tensors EdgeSAM's decoder actually accepts.
///
/// The exported decoder has no separate "box" input, and no separate
/// "point" input either: every entry, box corner or refinement point alike,
/// is one row of the same flat `point_coords`/`point_labels` arrays,
/// distinguished only by its label value. See
/// `docs/EDGESAM_PROVENANCE.md`, "Box and point prompts share one array",
/// for the upstream source (`SamCoreMLModel._embed_points` in
/// `edge_sam/utils/coreml.py`) this was verified against — including why
/// the order of entries within the array does not change the decoder's
/// output.
enum EdgeSAMPromptTensor {
    struct Prompt {
        /// `Float32[1, N, 2]`, `N` = 2 (box only) up to 16 (box + up to 14
        /// refinement points) — see `EdgeSAMGeometry.promptEntries`.
        let coordinates: MLMultiArray
        /// `Float32[1, N]`, one label per row of `coordinates`, in the same
        /// order.
        let labels: MLMultiArray
    }

    /// `region` and `points` are RIG-space (normalized, top-left origin)
    /// relative to the *same* bounded source image `resizeMetadata` was
    /// computed from — mixing either from a different image would silently
    /// mis-place the prompt, so callers must always pass the pair
    /// `EdgeSAMSegmenter` cached together at `encodeSource` time.
    static func prompt(
        for region: NormalizedCropRect,
        points: [EdgeSAMGeometry.PromptPoint],
        resizeMetadata: EdgeSAMResizeMetadata
    ) -> Prompt? {
        guard let entries = EdgeSAMGeometry.promptEntries(for: region, points: points, resizeMetadata: resizeMetadata)
        else { return nil }

        guard let coordinates = try? MLMultiArray(shape: [1, NSNumber(value: entries.count), 2], dataType: .float32),
              let labels = try? MLMultiArray(shape: [1, NSNumber(value: entries.count)], dataType: .float32)
        else { return nil }

        let coordPointer = coordinates.dataPointer.bindMemory(to: Float32.self, capacity: coordinates.count)
        let labelPointer = labels.dataPointer.bindMemory(to: Float32.self, capacity: labels.count)
        for (i, entry) in entries.enumerated() {
            coordPointer[i * 2] = Float(entry.x)
            coordPointer[i * 2 + 1] = Float(entry.y)
            labelPointer[i] = entry.label
        }

        return Prompt(coordinates: coordinates, labels: labels)
    }
}
