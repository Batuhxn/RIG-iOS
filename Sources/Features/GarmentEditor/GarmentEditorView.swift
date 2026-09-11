import SwiftData
import SwiftUI

/// Editing a garment that is already in the wardrobe.
///
/// Same fields as the import flow's details step, from the same shared view —
/// two forms asking for the same things in different shapes is how they drift
/// apart.
struct GarmentEditorView: View {
    let item: ClothingItem

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var fields: GarmentMetadataFields
    @State private var errorMessage: String?

    init(item: ClothingItem) {
        self.item = item
        _fields = State(initialValue: GarmentMetadataFields(item: item))
    }

    var body: some View {
        VStack(spacing: 0) {
            RIGSheetGrabber()

            RIGSheetHeader(
                title: "Parçayı düzenle",
                leadingTitle: "İptal",
                leadingAction: { dismiss() },
                trailingTitle: "Kaydet",
                trailingAction: save,
                isTrailingEnabled: fields.isValid
            )

            ScrollView {
                VStack(alignment: .leading, spacing: RIGTheme.Spacing.l) {
                    if let errorMessage {
                        RIGErrorBanner(message: errorMessage) {
                            self.errorMessage = nil
                        }
                    }

                    NocturneMetadataFields(fields: $fields, showsNotes: true)
                }
                .padding(.horizontal, RIGTheme.Spacing.xl)
                .padding(.top, RIGTheme.Spacing.l)
                .padding(.bottom, RIGTheme.Spacing.xl)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RIGTheme.pageBackground)
        .presentationBackground(RIGTheme.pageBackground)
        .presentationDragIndicator(.hidden)
    }

    private func save() {
        guard fields.isValid else { return }
        fields.apply(to: item)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = "Bu değişiklik kaydedilemedi. Parçan değişmedi."
        }
    }
}
