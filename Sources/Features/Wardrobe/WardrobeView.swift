import SwiftData
import SwiftUI

/// The garment library.
struct WardrobeView: View {
    @Query(sort: [SortDescriptor(\ClothingItem.createdAt, order: .reverse)])
    private var items: [ClothingItem]

    @State private var categoryFilter: GarmentCategory?
    @State private var seasonFilter: Season?
    @State private var favoritesOnly = false
    @State private var isPresentingAdd = false
    @State private var isPresentingBulkImport = false

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: RIGTheme.Spacing.m)]

    /// Filtering happens in memory rather than in the query predicate. At the
    /// scale of a personal wardrobe that is measured in hundreds of rows, and it
    /// keeps three independent filters legible.
    private var filteredItems: [ClothingItem] {
        items.filter { item in
            if let categoryFilter, item.category != categoryFilter { return false }
            if let seasonFilter, !item.seasons.contains(seasonFilter.set) { return false }
            if favoritesOnly && !item.isFavorite { return false }
            return true
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    RIGEmptyState(
                        symbol: "square.grid.2x2",
                        title: "Your wardrobe is empty",
                        message: "Add a garment you own. RIG will try to cut it out from its background and keep it here on this device.",
                        actionTitle: "Add a garment",
                        action: { isPresentingAdd = true },
                        secondaryActionTitle: "Import multiple photos",
                        secondaryAction: { isPresentingBulkImport = true }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: RIGTheme.Spacing.m) {
                            WardrobeFilterBar(
                                categoryFilter: $categoryFilter,
                                seasonFilter: $seasonFilter,
                                favoritesOnly: $favoritesOnly
                            )

                            if filteredItems.isEmpty {
                                RIGEmptyState(
                                    symbol: "line.3.horizontal.decrease",
                                    title: "Nothing matches",
                                    message: "No garment matches these filters. Clear one and try again.",
                                    actionTitle: "Clear filters",
                                    action: clearFilters
                                )
                                .padding(.top, RIGTheme.Spacing.l)
                            } else {
                                LazyVGrid(columns: columns, spacing: RIGTheme.Spacing.l) {
                                    ForEach(filteredItems) { item in
                                        NavigationLink {
                                            GarmentDetailView(item: item)
                                        } label: {
                                            GarmentCard(item: item)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, RIGTheme.Spacing.m)
                            }
                        }
                        .padding(.bottom, RIGTheme.Spacing.xl)
                    }
                }
            }
            .background(RIGTheme.pageBackground)
            .navigationTitle("Wardrobe")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    // A menu rather than a second toolbar button: the two ways
                    // in are the same action at different scales, and the
                    // single-garment flow stays exactly where it was.
                    Menu {
                        Button {
                            isPresentingAdd = true
                        } label: {
                            Label("Add one garment", systemImage: "camera")
                        }
                        Button {
                            isPresentingBulkImport = true
                        } label: {
                            Label("Import multiple photos", systemImage: "square.stack")
                        }
                    } label: {
                        Label("Add garments", systemImage: "plus")
                    }
                    .accessibilityLabel("Add garments")
                }
            }
            .sheet(isPresented: $isPresentingAdd) {
                AddGarmentFlow()
            }
            .sheet(isPresented: $isPresentingBulkImport) {
                BulkImportFlow()
            }
        }
    }

    private func clearFilters() {
        categoryFilter = nil
        seasonFilter = nil
        favoritesOnly = false
    }
}

struct WardrobeFilterBar: View {
    @Binding var categoryFilter: GarmentCategory?
    @Binding var seasonFilter: Season?
    @Binding var favoritesOnly: Bool

    var body: some View {
        VStack(spacing: RIGTheme.Spacing.s) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: RIGTheme.Spacing.s) {
                    FilterChip(title: "All", isOn: categoryFilter == nil) {
                        categoryFilter = nil
                    }
                    ForEach(GarmentCategory.allCases.sorted { $0.displayOrder < $1.displayOrder }) { category in
                        FilterChip(title: category.displayName, isOn: categoryFilter == category) {
                            categoryFilter = categoryFilter == category ? nil : category
                        }
                    }
                }
                .padding(.horizontal, RIGTheme.Spacing.m)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: RIGTheme.Spacing.s) {
                    FilterChip(title: "Any season", isOn: seasonFilter == nil) {
                        seasonFilter = nil
                    }
                    ForEach(Season.allCases) { season in
                        FilterChip(title: season.displayName, isOn: seasonFilter == season) {
                            seasonFilter = seasonFilter == season ? nil : season
                        }
                    }
                    FilterChip(title: "Favourites", isOn: favoritesOnly) {
                        favoritesOnly.toggle()
                    }
                }
                .padding(.horizontal, RIGTheme.Spacing.m)
            }
        }
        .padding(.top, RIGTheme.Spacing.s)
    }
}

struct FilterChip: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .padding(.horizontal, RIGTheme.Spacing.m)
                .frame(minHeight: 36)
                .background(isOn ? Color.accentColor.opacity(0.16) : RIGTheme.tileBackground)
                .foregroundStyle(isOn ? Color.accentColor : Color.primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}

#Preview {
    WardrobeView()
        .modelContainer(PreviewData.container())
        .environment(\.rigServices, .preview())
}
