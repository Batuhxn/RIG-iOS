import SwiftUI
import UIKit

/// No background removal and no persistence until the user confirms this crop.
struct RawGarmentCropPreview: View {
    let image: UIImage
    /// Set only when EdgeSAM was available and genuinely attempted a mask
    /// for this box, then failed — never for "no segmenter configured" or a
    /// superseded attempt, both of which are silent by design. `nil` gives
    /// byte-identical behaviour to v0.4 Slice 1's plain manual crop preview
    /// (Goal C, v0.4 Slice 2.1: a failure must never just look like the AI
    /// feature silently isn't there).
    var notice: String? = nil
    let onAdjust: () -> Void
    let onUse: () -> Void

    var body: some View {
        VStack(spacing: RIGTheme.Spacing.m) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Original crop preview")
            if let notice {
                RIGErrorBanner(message: notice)
            }
            Text("Original crop")
                .font(.headline)
            Text("Check the edges before the background is removed.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Use this crop", action: onUse)
                .buttonStyle(RIGPrimaryButtonStyle())
            Button("Adjust area", action: onAdjust)
                .buttonStyle(RIGSecondaryButtonStyle())
        }
        .padding(RIGTheme.Spacing.m)
    }
}
