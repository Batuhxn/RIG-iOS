import PhotosUI
import SwiftData
import SwiftUI

/// The one way garments get into RIG.
///
/// Before this, the wardrobe offered "add one garment", "import multiple
/// photos" and a camera button side by side — three names for one intention,
/// and the user had to understand RIG's implementation before they had even
/// opened their photo library. Now there is one button and one question.
///
/// Everything after the question is a consequence, not another decision: the
/// number of photographs chosen picks between the single-garment review and
/// the bulk queue, and the user is never told which one they are in.
struct PhotoImportFlow: View {
    @Environment(\.dismiss) private var dismiss

    @State private var intent: PhotoImportIntent?
    @State private var selection: [PhotosPickerItem] = []
    @State private var isPickerPresented = false
    @State private var isUsingCamera = false

    private var route: PhotoImportRoute {
        PhotoImportRouter.route(for: intent, selectionCount: selection.count)
    }

    var body: some View {
        Group {
            if isUsingCamera {
                AddGarmentFlow(startsWithCamera: true)
            } else {
                routedContent
            }
        }
        // No `photoLibrary:` argument, as everywhere else in RIG: the
        // out-of-process picker hands over the chosen bytes and needs no photo
        // library authorisation at all.
        .photosPicker(
            isPresented: $isPickerPresented,
            selection: $selection,
            maxSelectionCount: intent?.maximumSelectionCount ?? 1,
            selectionBehavior: .ordered,
            matching: .images
        )
        .onChange(of: isPickerPresented) { _, isPresented in
            // Backing out of the picker returns to the question rather than
            // stranding the user on a blank sheet.
            if !isPresented, selection.isEmpty { intent = nil }
        }
    }

    @ViewBuilder
    private var routedContent: some View {
        switch route {
        case .awaitingSelection:
            intentStep
        case .singleGarment:
            AddGarmentFlow(initialSelection: selection.first)
        case .bulkReview:
            BulkImportFlow(items: selection)
        case .outfitSession:
            if let source = selection.first {
                OutfitPhotoSessionView(source: source)
            } else {
                intentStep
            }
        }
    }

    private var intentStep: some View {
        NavigationStack {
            VStack(spacing: RIGTheme.Spacing.m) {
                Spacer(minLength: 0)

                Text("What are you adding?")
                    .font(.title3.weight(.semibold))

                VStack(spacing: RIGTheme.Spacing.s) {
                    ForEach(PhotoImportIntent.allCases) { option in
                        ImportIntentCard(intent: option) { choose(option) }
                    }
                }
                .padding(.horizontal, RIGTheme.Spacing.m)

                if CameraPicker.isAvailable {
                    Button("Take a photo instead") {
                        isUsingCamera = true
                    }
                    .font(.subheadline)
                    .padding(.top, RIGTheme.Spacing.xs)
                }

                Spacer(minLength: 0)

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

    private func choose(_ option: PhotoImportIntent) {
        intent = option
        selection = []
        isPickerPresented = true
    }
}

/// One answer to "what are you adding?".
struct ImportIntentCard: View {
    let intent: PhotoImportIntent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: RIGTheme.Spacing.m) {
                Image(systemName: intent.symbolName)
                    .font(.system(size: 26, weight: .light))
                    .frame(width: 40)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(intent.title)
                        .font(.body.weight(.semibold))
                    Text(intent.subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(RIGTheme.Spacing.m)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .background(RIGTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: RIGTheme.Radius.card, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(intent.title). \(intent.subtitle)")
    }
}

#Preview {
    PhotoImportFlow()
        .modelContainer(PreviewData.container(populated: false))
        .environment(\.rigServices, .preview())
}
