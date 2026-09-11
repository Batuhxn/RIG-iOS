import CoreML
import Foundation

/// Turns one manually drawn RIG-space box into the two-point prompt
/// EdgeSAM's decoder actually accepts.
///
/// The exported decoder has no separate "box" input — a box is exactly two
/// points carrying reserved label values. See
/// `docs/EDGESAM_PROVENANCE.md`, "Box prompt → point_coords / point_labels",
/// for the upstream source (`PromptEncoder.__init__`'s own
/// `# pos/neg point + 2 box corners` comment) this was verified against.
enum EdgeSAMPromptTensor {
    /// `PromptEncoder.point_embeddings` index 2: the box's top-left corner.
    private static let topLeftLabel: Float = 2
    /// `PromptEncoder.point_embeddings` index 3: the box's bottom-right corner.
    private static let bottomRightLabel: Float = 3

    struct BoxPrompt {
        /// `Float32[1, 2, 2]`: `[[x0, y0], [x1, y1]]`, in the same
        /// 1024x1024 padded pixel space the encoder consumed — see
        /// `EdgeSAMResizeMetadata`.
        let coordinates: MLMultiArray
        /// `Float32[1, 2]`: `[2, 3]`, always — this slice of the app only
        /// ever sends a box, never a loose point.
        let labels: MLMultiArray
    }

    /// `region` is RIG-space (normalized, top-left origin) relative to the
    /// *same* bounded source image `resizeMetadata` was computed from —
    /// mixing a region from a different image would silently mis-place the
    /// prompt, so callers must always pass the pair `EdgeSAMSegmenter`
    /// cached together at `encodeSource` time.
    static func boxPrompt(for region: NormalizedCropRect, resizeMetadata: EdgeSAMResizeMetadata) -> BoxPrompt? {
        guard let coords = EdgeSAMGeometry.boxPromptCoordinates(for: region, resizeMetadata: resizeMetadata) else {
            return nil
        }

        guard let coordinates = try? MLMultiArray(shape: [1, 2, 2], dataType: .float32),
              let labels = try? MLMultiArray(shape: [1, 2], dataType: .float32) else { return nil }

        let coordPointer = coordinates.dataPointer.bindMemory(to: Float32.self, capacity: coordinates.count)
        coordPointer[0] = Float(coords.x0)
        coordPointer[1] = Float(coords.y0)
        coordPointer[2] = Float(coords.x1)
        coordPointer[3] = Float(coords.y1)

        let labelPointer = labels.dataPointer.bindMemory(to: Float32.self, capacity: labels.count)
        labelPointer[0] = topLeftLabel
        labelPointer[1] = bottomRightLabel

        return BoxPrompt(coordinates: coordinates, labels: labels)
    }
}
