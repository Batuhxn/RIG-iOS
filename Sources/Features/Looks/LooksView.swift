import SwiftData
import SwiftUI

struct LooksView: View {
    @Query(sort: [SortDescriptor(\SavedOutfit.createdAt, order: .reverse)])
    private var looks: [SavedOutfit]

    @State private var isPresentingBuilder = false

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: RIGTheme.Spacing.m)]

    var body: some View {
        NavigationStack {
            Group {
                if looks.isEmpty {
                    RIGEmptyState(
                        symbol: "square.stack",
                        title: "No looks yet",
                        message: "Save a suggestion, or put one together yourself. Saved looks stay on this device.",
                        actionTitle: "Build a look",
                        action: { isPresentingBuilder = true }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: RIGTheme.Spacing.l) {
                            ForEach(looks) { look in
                                NavigationLink {
                                    LookDetailView(look: look)
                                } label: {
                                    LookCard(look: look)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(RIGTheme.Spacing.m)
                    }
                }
            }
            .background(RIGTheme.pageBackground)
            .navigationTitle("Looks")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isPresentingBuilder = true
                    } label: {
                        Label("Build a look", systemImage: "plus")
                    }
                    .accessibilityLabel("Build a look")
                }
            }
            .sheet(isPresented: $isPresentingBuilder) {
                NavigationStack {
                    OutfitBuilderView(presentedAsSheet: true)
                }
            }
        }
    }
}

struct LookDetailView: View {
    let look: SavedOutfit

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var isConfirmingDelete = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RIGTheme.Spacing.l) {
                LookCompositionView(items: look.itemsInDisplayOrder)
                    .padding(RIGTheme.Spacing.m)
                    .background(RIGTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: RIGTheme.Radius.card, style: .continuous))

                if look.hasMissingGarments {
                    Text("Some garments in this look are no longer in your wardrobe.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let errorMessage {
                    RIGErrorBanner(message: errorMessage) {
                        self.errorMessage = nil
                    }
                }

                VStack(alignment: .leading, spacing: RIGTheme.Spacing.s) {
                    RIGSectionHeader(title: "Garments", subtitle: look.source.displayName)
                    ForEach(look.itemsInDisplayOrder) { item in
                        HStack(spacing: RIGTheme.Spacing.m) {
                            Circle()
                                .fill(RIGTheme.swatch(for: item.primaryColor))
                                .frame(width: 12, height: 12)
                                .overlay(Circle().strokeBorder(RIGTheme.hairline, lineWidth: 0.5))
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(item.displayName)
                                    .font(.subheadline)
                                Text(item.category.displayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(minHeight: 44)
                        .accessibilityElement(children: .combine)
                    }
                }

                Button(role: .destructive) {
                    isConfirmingDelete = true
                } label: {
                    Text("Delete look")
                }
                .buttonStyle(RIGSecondaryButtonStyle())
            }
            .padding(.horizontal, RIGTheme.Spacing.m)
            .padding(.bottom, RIGTheme.Spacing.xl)
        }
        .background(RIGTheme.pageBackground)
        .navigationTitle(look.name)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete this look?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: delete)
            Button("Keep", role: .cancel) {}
        } message: {
            Text("The garments stay in your wardrobe. Only the look is removed.")
        }
    }

    private func delete() {
        modelContext.delete(look)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = "That look could not be deleted."
        }
    }
}

#Preview {
    LooksView()
        .modelContainer(PreviewData.container())
        .environment(\.rigServices, .preview())
}
