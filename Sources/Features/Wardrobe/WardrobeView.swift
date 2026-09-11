import SwiftData
import SwiftUI

/// The garment library — "Dolap", the design's home screen.
///
/// A kicker and a count, a row of filter chips, a two-column grid of 3:4
/// photographs, and one floating action. The photograph is the content here;
/// everything else gets out of its way.
struct WardrobeView: View {
    @Query(sort: [SortDescriptor(\ClothingItem.createdAt, order: .reverse)])
    private var items: [ClothingItem]

    @State private var categoryFilter: GarmentCategory?
    @State private var seasonFilter: Season?
    @State private var favoritesOnly = false
    @State private var isPresentingImport = false

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

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
            ZStack(alignment: .bottom) {
                RIGTheme.pageBackground.ignoresSafeArea()

                if items.isEmpty {
                    RIGEmptyState(
                        symbol: "tshirt",
                        title: "Dolabın henüz boş",
                        message: "Bir fotoğraf seç; arka planı biz kaldıralım. Tek fotoğraf tek parça, çoklu seçim toplu aktarım olur.",
                        actionTitle: "İlk parçanı ekle",
                        action: { isPresentingImport = true }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    content
                    floatingAction
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $isPresentingImport) {
                PhotoImportFlow()
            }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                filterBar
                grid
            }
            .padding(.bottom, 120)
        }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            RIGScreenHeading(
                kicker: "Dolabım",
                title: items.count == 1 ? "1 parça" : "\(items.count) parça"
            )

            Button {
                isPresentingImport = true
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(RIGIconButtonStyle())
            .accessibilityLabel("Parça ekle")
        }
        .padding(.horizontal, RIGTheme.Spacing.xl)
        .padding(.top, RIGTheme.Spacing.m)
        .padding(.bottom, RIGTheme.Spacing.m)
    }

    private var filterBar: some View {
        VStack(spacing: RIGTheme.Spacing.s) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    RIGChip(title: "Tümü", isOn: categoryFilter == nil, size: 12) {
                        categoryFilter = nil
                    }
                    ForEach(GarmentCategory.allCases.sorted { $0.displayOrder < $1.displayOrder }) { category in
                        RIGChip(title: category.displayName, isOn: categoryFilter == category, size: 12) {
                            categoryFilter = categoryFilter == category ? nil : category
                        }
                    }
                }
                .padding(.horizontal, RIGTheme.Spacing.xl)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    RIGChip(title: "Tüm sezonlar", isOn: seasonFilter == nil, size: 12) {
                        seasonFilter = nil
                    }
                    ForEach(Season.allCases) { season in
                        RIGChip(title: season.displayName, isOn: seasonFilter == season, size: 12) {
                            seasonFilter = seasonFilter == season ? nil : season
                        }
                    }
                    RIGChip(title: "Favoriler", isOn: favoritesOnly, size: 12) {
                        favoritesOnly.toggle()
                    }
                }
                .padding(.horizontal, RIGTheme.Spacing.xl)
            }
        }
        .padding(.bottom, RIGTheme.Spacing.m)
    }

    @ViewBuilder
    private var grid: some View {
        if filteredItems.isEmpty {
            RIGEmptyState(
                symbol: "line.3.horizontal.decrease",
                title: "Eşleşen parça yok",
                message: "Bu filtrelerle hiçbir parça eşleşmiyor. Birini kaldırıp tekrar dene.",
                actionTitle: "Filtreleri temizle",
                action: clearFilters
            )
            .padding(.top, RIGTheme.Spacing.xl)
        } else {
            LazyVGrid(columns: columns, spacing: RIGTheme.Spacing.l) {
                ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                    NavigationLink {
                        GarmentDetailView(item: item)
                    } label: {
                        GarmentCard(item: item)
                    }
                    .buttonStyle(.plain)
                    .modifier(RisingItem(index: index))
                }
            }
            .padding(.horizontal, RIGTheme.Spacing.xl)
        }
    }

    private var floatingAction: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            ZStack(alignment: .bottom) {
                RIGBottomScrim()
                Button {
                    isPresentingImport = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                        Text("Parça ekle")
                    }
                }
                .buttonStyle(RIGPillButtonStyle())
                .padding(.bottom, RIGTheme.Spacing.xl)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .allowsHitTesting(true)
    }

    private func clearFilters() {
        categoryFilter = nil
        seasonFilter = nil
        favoritesOnly = false
    }
}

/// The design's staggered arrival: each tile fades up 10pt, 45ms after the one
/// before it. Applied by index so the stagger is a property of position in the
/// grid rather than something each card has to know about itself.
struct RisingItem: ViewModifier {
    let index: Int

    @State private var hasAppeared = false

    func body(content: Content) -> some View {
        content
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 0 : 10)
            .onAppear {
                withAnimation(
                    NocturneMotion.rise.delay(Double(min(index, 8)) * NocturneMotion.riseStagger)
                ) {
                    hasAppeared = true
                }
            }
    }
}

#Preview {
    WardrobeView()
        .modelContainer(PreviewData.container())
        .environment(\.rigServices, .preview())
        .nocturneAppearance()
}
