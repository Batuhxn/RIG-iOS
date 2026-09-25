import SwiftData
import SwiftUI

/// Editing an existing garment. Changes are applied to a scratch copy of the
/// fields and only written on Save, so cancelling really cancels.
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
        NavigationStack {
            Form {
                if let errorMessage {
                    Section {
                        RIGErrorBanner(message: errorMessage) {
                            self.errorMessage = nil
                        }
                    }
                }
                GarmentMetadataForm(fields: $fields)
            }
            .navigationTitle("Edit garment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!fields.isValid)
                }
            }
        }
    }

    private func save() {
        guard fields.apply(to: item) else { return }
        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = "That change could not be saved. Your garment is unchanged."
        }
    }
}
