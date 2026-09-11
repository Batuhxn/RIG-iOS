import PhotosUI
import UIKit
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
///
/// The design draws its own library grid here. RIG does not, and will not: the
/// out-of-process `PhotosPicker` hands over the chosen bytes without photo
/// library authorisation, and an in-app grid would require full library access
/// for a screen the system already draws. What is reproduced instead is the
/// sheet around it — the grabber, the header row, the hint, the selection
/// preview and the CTA whose wording follows the count.
struct PhotoImportFlow: View {
    @Environment(\.dismiss) private var dismiss

    @State private var selection: [PhotosPickerItem] = []
    @State private var previews: [UIImage] = []
    @State private var isLoadingPreviews = false
    @State private var hasConfirmed = false
    @State private var isUsingCamera = false

    private var route: PhotoImportRoute {
        PhotoImportRouter.route(selectionCount: selection.count)
    }

    var body: some View {
        Group {
            if isUsingCamera {
                AddGarmentFlow(startsWithCamera: true)
            } else if hasConfirmed {
                routedContent
            } else {
                sourceStep
            }
        }
        .background(RIGTheme.pageBackground)
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

    // MARK: - Source

    private var sourceStep: some View {
        VStack(spacing: 0) {
            RIGSheetGrabber()

            RIGSheetHeader(
                title: "Fotoğraf seç",
                leadingTitle: "İptal",
                leadingAction: { dismiss() },
                trailingTitle: selection.isEmpty ? nil : "Temizle",
                trailingAction: clearSelection
            )

            Text("Tek fotoğraf tek parça, birden fazla fotoğraf toplu aktarım olarak açılır.")
                .font(.system(size: 11))
                .foregroundStyle(RIGTheme.text(50))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, RIGTheme.Spacing.xl)
                .padding(.bottom, 6)

            selectionArea

            Spacer(minLength: 0)

            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RIGTheme.pageBackground)
        .onChange(of: selection) { _, _ in
            Task { await loadPreviews() }
        }
    }

    @ViewBuilder
    private var selectionArea: some View {
        if selection.isEmpty {
            VStack(spacing: RIGTheme.Spacing.l) {
                Spacer(minLength: 0)
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(RIGTheme.text(40))
                    .accessibilityHidden(true)
                Text("Sahip olduklarını ekle")
                    .font(.system(size: 20, weight: .medium))
                Text("Her fotoğrafta bir parça. İstediğin kadar seç.")
                    .font(.system(size: 13))
                    .foregroundStyle(RIGTheme.text(55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, RIGTheme.Spacing.xl)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        } else {
            ScrollView {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3),
                    spacing: 6
                ) {
                    ForEach(Array(previews.enumerated()), id: \.offset) { index, image in
                        SelectionTile(image: image, number: index + 1)
                    }
                    if isLoadingPreviews {
                        ForEach(0..<placeholderCount, id: \.self) { _ in
                            RIGSkeleton(cornerRadius: 6)
                                .aspectRatio(1, contentMode: .fit)
                        }
                    }
                }
                .padding(.horizontal, RIGTheme.Spacing.xl)
                .padding(.top, 10)
            }
        }
    }

    private var placeholderCount: Int {
        max(0, min(selection.count, PhotoImportFlow.previewLimit) - previews.count)
    }

    private var footer: some View {
        VStack(spacing: RIGTheme.Spacing.s) {
            if selection.count > PhotoImportFlow.previewLimit {
                Text("+\(selection.count - PhotoImportFlow.previewLimit) fotoğraf daha")
                    .font(.system(size: 11))
                    .foregroundStyle(RIGTheme.text(50))
            }

            // No `photoLibrary:` argument, as everywhere else in RIG: the
            // out-of-process picker hands over the chosen bytes and needs no
            // photo library authorisation at all.
            PhotosPicker(
                selection: $selection,
                maxSelectionCount: PhotoImportRouter.maximumSelectionCount,
                selectionBehavior: .ordered,
                matching: .images
            ) {
                Text(selection.isEmpty ? "Fotoğraflardan seç" : "Seçimi değiştir")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(RIGTheme.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .overlay(
                        RoundedRectangle(cornerRadius: RIGTheme.Radius.large, style: .continuous)
                            .strokeBorder(RIGTheme.hairline, lineWidth: 1)
                    )
            }

            if selection.isEmpty, CameraPicker.isAvailable {
                Button("Fotoğraf çek") { isUsingCamera = true }
                    .buttonStyle(RIGQuietButtonStyle())
            }

            if !selection.isEmpty {
                Button(continueTitle) { hasConfirmed = true }
                    .buttonStyle(RIGPrimaryButtonStyle())
            }

            Text("Her şey bu cihazda olur — hiçbir şey yüklenmez.")
                .font(.system(size: 11))
                .foregroundStyle(RIGTheme.text(50))
                .multilineTextAlignment(.center)
                .padding(.top, RIGTheme.Spacing.xs)
        }
        .padding(.horizontal, RIGTheme.Spacing.xl)
        .padding(.top, 14)
        .padding(.bottom, RIGTheme.Spacing.l)
    }

    private var continueTitle: String {
        selection.count > 1 ? "\(selection.count) fotoğrafı toplu aktar" : "Devam et"
    }

    // MARK: - Actions

    private func clearSelection() {
        selection = []
        previews = []
    }

    /// Loads a small preview for each chosen photograph, one at a time.
    ///
    /// Sequential on purpose, and capped: the bulk queue holds exactly one
    /// photograph in memory at a time for the same reason, and a selection of
    /// twenty 12-megapixel images decoded at once would undo that discipline
    /// before the queue ever starts.
    @MainActor
    private func loadPreviews() async {
        let items = Array(selection.prefix(PhotoImportFlow.previewLimit))
        previews = []
        guard !items.isEmpty else {
            isLoadingPreviews = false
            return
        }

        isLoadingPreviews = true
        defer { isLoadingPreviews = false }

        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let small = GarmentImageProcessing.pngData(
                      from: data,
                      maxDimension: GarmentImageProcessing.thumbnailMaxDimension
                  ),
                  let image = UIImage(data: small) else { continue }
            // The user may have changed the selection while this ran.
            guard selection.prefix(PhotoImportFlow.previewLimit).count == items.count else { return }
            previews.append(image)
        }
    }

    /// The design shows nine cells. More than that is a count, not a picture.
    static let previewLimit = 9
}

/// One chosen photograph, with its position in the selection.
private struct SelectionTile: View {
    let image: UIImage
    let number: Int

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(RIGTheme.accent, lineWidth: 2)
            )
            .overlay(alignment: .topTrailing) {
                Text("\(number)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(RIGTheme.pageBackground)
                    .frame(width: 19, height: 19)
                    .background(RIGTheme.accent, in: Circle())
                    .padding(5)
            }
            .scaleEffect(0.92)
            .accessibilityLabel("Seçim \(number)")
    }
}

#Preview {
    PhotoImportFlow()
        .modelContainer(PreviewData.container(populated: false))
        .environment(\.rigServices, .preview())
}
