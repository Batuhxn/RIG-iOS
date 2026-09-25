import SwiftUI

/// Shared image comparison for one-photo and queued imports.
struct GarmentImageReview: View {
    let result: GarmentImportResult
    @Binding var choice: GarmentImageChoice
    let symbolName: String
    var imageHeight: CGFloat = 220
    var choiceEnabled = true

    var body: some View {
        GarmentImageView(
            relativePath: choice.relativePath(in: result),
            symbolName: symbolName
        )
        .frame(height: imageHeight)
        .frame(maxWidth: .infinity)
        .listRowBackground(Color.clear)

        if result.isBackgroundRemoved && result.cutoutRelativePath != nil {
            Picker("Image version", selection: $choice) {
                Text("Cutout").tag(GarmentImageChoice.cutout)
                Text("Original").tag(GarmentImageChoice.original)
            }
            .pickerStyle(.segmented)
            .disabled(!choiceEnabled)
            .accessibilityLabel("Image version")
            .accessibilityValue(choice == .cutout ? "Cutout selected" : "Original selected")

            Text("Choose the version that looks better.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else if let message = result.backgroundRemovalMessage {
            Text("\(message) The original photo will be used instead.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
