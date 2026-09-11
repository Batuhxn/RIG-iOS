import SwiftData
import SwiftUI

/// Compose a look by slot.
///
/// A slot interface rather than a drag-and-drop canvas: it is robust, it is
/// accessible, and it makes the structural rules visible while you build. The
/// same `OutfitValidator` that gates generated suggestions gates this, so the
/// two paths can never disagree about what an outfit is.
struct OutfitBuilderView: View {
    var presentedAsSheet: Bool = false

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: [SortDescriptor(\ClothingItem.displayName)])
    private var items: [ClothingItem]

    @State private var selectedIDs: [UUID] = []
    @State private var pickerCategory: GarmentCategory?
    @State private var name: String = ""
    @State private var errorMessage: String?

    private var itemsByID: [UUID: ClothingItem] {
        items.reduce(into: [:]) { result, item in result[item.id] = item }
    }

    private var selectedItems: [ClothingItem] {
        selectedIDs.compactMap { itemsByID[$0] }
    }

    private var validation: OutfitValidation {
        OutfitValidator.validate(selectedItems.map(\.snapshot))
    }

    var body: some View {
        Group {
            if items.isEmpty {
                RIGEmptyState(
                    symbol: "square.grid.2x2",
                    title: "Kuracak bir şey yok",
                    message: "Önce dolabına birkaç parça ekle."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Form {
                    Section {
                        ForEach(GarmentCategory.allCases.sorted { $0.displayOrder < $1.displayOrder }) { category in
                            slotRow(for: category)
                        }
                    } header: {
                        Text("Parçalar")
                    } footer: {
                        Text("A look needs a top and a bottom, or a dress. Everything else is optional.")
                    }

                    Section("Ad") {
                        TextField("Bu kombine bir ad ver", text: $name)
                            .textInputAutocapitalization(.sentences)
                    }

                    if !selectedIDs.isEmpty {
                        Section("Doğrulama") {
                            if validation.isValid {
                                Label("This is a valid look.", systemImage: "checkmark.circle")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(Array(validation.issues.enumerated()), id: \.offset) { _, issue in
                                    Label(issue.message, systemImage: "exclamationmark.circle")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    if let errorMessage {
                        Section {
                            RIGErrorBanner(message: errorMessage) {
                                self.errorMessage = nil
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Kombin oluştur")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if presentedAsSheet {
                ToolbarItem(placement: .cancellationAction) {
                    Button("İptal") { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Kaydet", action: save)
                    .disabled(!validation.isValid || items.isEmpty)
            }
        }
        .sheet(item: $pickerCategory) { category in
            GarmentPickerSheet(
                category: category,
                candidates: items.filter { $0.category == category && !selectedIDs.contains($0.id) },
                onSelect: { item in
                    add(item, in: category)
                    pickerCategory = nil
                },
                onCancel: { pickerCategory = nil }
            )
        }
    }

    @ViewBuilder
    private func slotRow(for category: GarmentCategory) -> some View {
        let chosen = selectedItems.filter { $0.category == category }
        VStack(alignment: .leading, spacing: RIGTheme.Spacing.xs) {
            HStack {
                Label(category.displayName, systemImage: category.symbolName)
                    .font(.subheadline)
                Spacer()
                if chosen.count < category.maximumPerOutfit {
                    Button("Seç") {
                        pickerCategory = category
                    }
                    .font(.subheadline)
                    .accessibilityLabel("\(category.displayName) seç")
                }
            }
            .frame(minHeight: 44)

            ForEach(chosen) { item in
                HStack(spacing: RIGTheme.Spacing.s) {
                    GarmentImageView(
                        relativePath: item.displayImageRelativePath,
                        symbolName: category.symbolName
                    )
                    .frame(width: 44, height: 44)
                    Text(item.displayName)
                        .font(.footnote)
                    Spacer(minLength: 0)
                    Button {
                        remove(item)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("\(item.displayName) parçasını çıkar")
                }
                .frame(minHeight: 44)
            }
        }
    }

    private func add(_ item: ClothingItem, in category: GarmentCategory) {
        // Duplicate use is impossible by construction: the picker never offers a
        // garment that is already in the look, and this guard keeps it that way.
        guard !selectedIDs.contains(item.id) else { return }
        let chosenCount = selectedItems.filter { $0.category == category }.count
        guard chosenCount < category.maximumPerOutfit else { return }
        selectedIDs.append(item.id)
    }

    private func remove(_ item: ClothingItem) {
        selectedIDs.removeAll { $0 == item.id }
    }

    private func save() {
        let garments = selectedItems
        guard OutfitValidator.validate(garments.map(\.snapshot)).isValid else {
            errorMessage = "Bu birleşim henüz tamamlanmış bir kombin değil."
            return
        }

        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let outfit = SavedOutfit(
            name: trimmed.isEmpty ? SavedOutfit.defaultName(for: Date()) : trimmed,
            source: .manual,
            items: garments
        )
        modelContext.insert(outfit)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.delete(outfit)
            errorMessage = "Bu kombin cihaza kaydedilemedi."
        }
    }
}

/// Category picker. Only garments that are not already in the look appear here.
struct GarmentPickerSheet: View {
    let category: GarmentCategory
    let candidates: [ClothingItem]
    let onSelect: (ClothingItem) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                if candidates.isEmpty {
                    RIGEmptyState(
                        symbol: category.symbolName,
                        title: "Uygun \(category.displayName) yok",
                        message: "Bu kategorideki her parça zaten kombinde ya da dolabında hiç yok."
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(candidates) { item in
                        Button {
                            onSelect(item)
                        } label: {
                            HStack(spacing: RIGTheme.Spacing.m) {
                                GarmentImageView(
                                    relativePath: item.displayImageRelativePath,
                                    symbolName: category.symbolName
                                )
                                .frame(width: 48, height: 48)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.displayName)
                                        .font(.subheadline)
                                    Text(item.primaryColor.displayName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(minHeight: 56)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle(category.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("İptal", action: onCancel)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        OutfitBuilderView()
    }
    .modelContainer(PreviewData.container())
    .environment(\.rigServices, .preview())
}
