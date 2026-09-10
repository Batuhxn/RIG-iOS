import SwiftData
import SwiftUI

struct GarmentDetailView: View {
    let item: ClothingItem

    @Environment(\.modelContext) private var modelContext
    @Environment(\.rigServices) private var services
    @Environment(\.dismiss) private var dismiss

    @State private var isPresentingEditor = false
    @State private var isConfirmingDelete = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RIGTheme.Spacing.l) {
                GarmentImageView(
                    relativePath: item.preferredImageRelativePath,
                    symbolName: item.category.symbolName
                )
                .padding(RIGTheme.Spacing.m)
                .frame(height: 320)
                .frame(maxWidth: .infinity)
                .background(RIGTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: RIGTheme.Radius.card, style: .continuous))

                if !item.isBackgroundRemoved {
                    Text("RIG could not isolate this garment, so the original photo is being used.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let errorMessage {
                    RIGErrorBanner(message: errorMessage) {
                        self.errorMessage = nil
                    }
                }

                VStack(alignment: .leading, spacing: RIGTheme.Spacing.s) {
                    Text(item.displayName)
                        .font(.title2.weight(.medium))
                    if !item.subtype.isEmpty {
                        Text(item.subtype)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(spacing: 0) {
                    DetailRow(label: "Category", value: item.category.displayName)
                    Divider()
                    DetailRow(label: "Colour", value: item.primaryColor.displayName, swatch: item.primaryColor)
                    Divider()
                    DetailRow(label: "Seasons", value: item.seasons.displayName)
                }
                .background(RIGTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: RIGTheme.Radius.tile, style: .continuous))

                if !item.notes.isEmpty {
                    VStack(alignment: .leading, spacing: RIGTheme.Spacing.xs) {
                        RIGSectionHeader(title: "Notes")
                        Text(item.notes)
                            .font(.body)
                    }
                }

                Button(role: .destructive) {
                    isConfirmingDelete = true
                } label: {
                    Text("Delete garment")
                }
                .buttonStyle(RIGSecondaryButtonStyle())
                .padding(.top, RIGTheme.Spacing.s)
            }
            .padding(.horizontal, RIGTheme.Spacing.m)
            .padding(.bottom, RIGTheme.Spacing.xl)
        }
        .background(RIGTheme.pageBackground)
        .navigationTitle(item.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isPresentingEditor = true
                } label: {
                    Text("Edit")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    toggleFavorite()
                } label: {
                    Image(systemName: item.isFavorite ? "heart.fill" : "heart")
                }
                .accessibilityLabel(item.isFavorite ? "Remove from favourites" : "Add to favourites")
            }
        }
        .sheet(isPresented: $isPresentingEditor) {
            GarmentEditorView(item: item)
        }
        .confirmationDialog(
            "Delete this garment?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive, action: delete)
            Button("Keep", role: .cancel) {}
        } message: {
            Text("Its photos are removed from this device. Saved looks that used it will say a garment is missing.")
        }
    }

    private func toggleFavorite() {
        item.isFavorite.toggle()
        item.touch()
        save()
    }

    /// Row first, then files. If the file sweep fails the orphan pass on next
    /// launch collects it; the reverse order could leave a garment pointing at
    /// images that no longer exist.
    private func delete() {
        let id = item.id
        modelContext.delete(item)
        do {
            try modelContext.save()
        } catch {
            errorMessage = "That garment could not be deleted. Nothing was changed."
            return
        }
        try? services.imageStore.removeAll(for: id)
        dismiss()
    }

    private func save() {
        do {
            try modelContext.save()
        } catch {
            errorMessage = "That change could not be saved."
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    var swatch: ColorFamily? = nil

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            if let swatch {
                Circle()
                    .fill(RIGTheme.swatch(for: swatch))
                    .frame(width: 14, height: 14)
                    .overlay(Circle().strokeBorder(RIGTheme.hairline, lineWidth: 0.5))
                    .accessibilityHidden(true)
            }
            Text(value)
        }
        .font(.subheadline)
        .padding(.horizontal, RIGTheme.Spacing.m)
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }
}
