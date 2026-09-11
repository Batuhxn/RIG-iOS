import PhotosUI
import SwiftData
import SwiftUI

/// The one way garments get into RIG.
///
/// Before this, the wardrobe offered "add one garment", "import multiple
/// photos" and a camera button side by side — three names for one intention,
/// and the user had to understand RIG's implementation before they had even
/// opened their photo library. Now there is one button.
///
/// Everything after it is a consequence, not another decision: the number of
/// photographs chosen picks between the single-garment review and the bulk
/// queue, and the user is never told which one they are in.
struct PhotoImportFlow: View {
    @Environment(\.dismiss) private var dismiss

    @State private var selection: [PhotosPickerItem] = []
    @State private var isUsingCamera = false

    private var route: PhotoImportRoute {
        PhotoImportRouter.route(selectionCount: selection.count)
    }

    var body: some View {
        Group {
            if isUsingCamera {
                AddGarmentFlow(startsWithCamera: true)
            } else {
                routedContent
            }
        }
    }

    @ViewBuilder
    private var routedContent: some View {
        switch route {
        case .awaitingSelection:
            sourceStep
        case .singleGarment:
            AddGarmentFlow(initialSelection: selection.first)
        case .bulkReview:
            BulkImportFlow(items: selection)
        }
    }

    private var sourceStep: some View {
        NavigationStack {
            VStack(spacing: RIGTheme.Spacing.m) {
                Spacer(minLength: 0)

                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                Text("Add what you own")
                    .font(.title3.weight(.semibold))
                Text("One garment per photo. Pick as many as you like.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, RIGTheme.Spacing.l)

                Spacer(minLength: 0)

                VStack(spacing: RIGTheme.Spacing.s) {
                    // No `photoLibrary:` argument, as everywhere else in RIG:
                    // the out-of-process picker hands over the chosen bytes and
                    // needs no photo library authorisation at all.
                    PhotosPicker(
                        selection: $selection,
                        maxSelectionCount: PhotoImportRouter.maximumSelectionCount,
                        selectionBehavior: .ordered,
                        matching: .images
                    ) {
                        Text("Choose from Photos")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(Color.accentColor)
                            .foregroundStyle(Color(uiColor: .systemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: RIGTheme.Radius.control, style: .continuous))
                    }

                    if CameraPicker.isAvailable {
                        Button("Take a photo") { isUsingCamera = true }
                            .buttonStyle(RIGSecondaryButtonStyle())
                    }
                }
                .padding(.horizontal, RIGTheme.Spacing.m)

                Text("Everything happens on this device — nothing is uploaded.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, RIGTheme.Spacing.l)
                    .padding(.bottom, RIGTheme.Spacing.l)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RIGTheme.pageBackground)
            .navigationTitle("Add photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    PhotoImportFlow()
        .modelContainer(PreviewData.container(populated: false))
        .environment(\.rigServices, .preview())
}
