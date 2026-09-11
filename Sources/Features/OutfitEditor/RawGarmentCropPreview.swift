import SwiftUI
import UIKit

/// No background removal and no persistence until the user confirms this crop.
struct RawGarmentCropPreview: View {
    let image: UIImage
    let onAdjust: () -> Void
    let onUse: () -> Void

    var body: some View {
        VStack(spacing: RIGTheme.Spacing.m) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Original crop preview")
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
