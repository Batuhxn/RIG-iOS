import SwiftData
import SwiftUI

/// The way in. One clear action, an honest summary of what RIG actually knows,
/// and recent looks. No weather card, no score, no personalisation claim —
/// v0.1 has none of those and will not imply otherwise.
struct HomeView: View {
    @Binding var selectedTab: RIGTab

    @Environment(\.rigServices) private var services
    @Query private var items: [ClothingItem]
    @Query(sort: [SortDescriptor(\SavedOutfit.createdAt, order: .reverse)]) private var looks: [SavedOutfit]

    @State private var hasSweptOrphanedImages = false

    private var readiness: WardrobeReadiness {
        WardrobeReadiness.evaluate(items.map(\.snapshot))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: RIGTheme.Spacing.xl) {
                    header
                    if items.isEmpty {
                        firstRunState
                    } else {
                        suggestAction
                        wardrobeSummary
                        recentLooks
                    }
                }
                .padding(.horizontal, RIGTheme.Spacing.m)
                .padding(.bottom, RIGTheme.Spacing.xl)
            }
            .background(RIGTheme.pageBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .task {
                await sweepOrphanedImagesOnce()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: RIGTheme.Spacing.xs) {
            RIGTheme.wordmark("RIG")
            Text("Your wardrobe, on this device.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, RIGTheme.Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var firstRunState: some View {
        RIGEmptyState(
            symbol: "camera",
            title: "Start with one garment",
            message: "Photograph something you own. RIG keeps it on this device and starts building looks once there is enough to work with.",
            actionTitle: "Open wardrobe",
            action: { selectedTab = .wardrobe }
        )
        .frame(maxWidth: .infinity)
        .padding(.top, RIGTheme.Spacing.xl)
    }

    @ViewBuilder
    private var suggestAction: some View {
        VStack(alignment: .leading, spacing: RIGTheme.Spacing.s) {
            if readiness.canSuggest {
                NavigationLink {
                    SuggestionsView()
                } label: {
                    Text("Suggest a Look")
                }
                .buttonStyle(RIGPrimaryButtonStyle())
            } else {
                Button("Suggest a Look") {
                    selectedTab = .wardrobe
                }
                .buttonStyle(RIGSecondaryButtonStyle())
                .disabled(true)
                Text(readiness.explanation)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            NavigationLink {
                OutfitBuilderView()
            } label: {
                Text("Build a look yourself")
            }
            .buttonStyle(RIGSecondaryButtonStyle())
        }
    }

    private var wardrobeSummary: some View {
        VStack(alignment: .leading, spacing: RIGTheme.Spacing.s) {
            RIGSectionHeader(title: "Wardrobe", subtitle: "\(items.count) \(items.count == 1 ? "garment" : "garments")")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: RIGTheme.Spacing.s)], spacing: RIGTheme.Spacing.s) {
                ForEach(categoriesWithCounts, id: \.category) { entry in
                    HStack(spacing: RIGTheme.Spacing.s) {
                        Image(systemName: entry.category.symbolName)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("\(entry.count)")
                                .font(.headline)
                            Text(entry.category.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(RIGTheme.Spacing.s)
                    .frame(minHeight: 52)
                    .background(RIGTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: RIGTheme.Radius.tile, style: .continuous))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(entry.count) \(entry.category.displayName)")
                }
            }
        }
    }

    private var categoriesWithCounts: [(category: GarmentCategory, count: Int)] {
        GarmentCategory.allCases
            .map { category in
                (category: category, count: items.filter { $0.category == category }.count)
            }
            .filter { $0.count > 0 }
            .sorted { $0.category.displayOrder < $1.category.displayOrder }
    }

    @ViewBuilder
    private var recentLooks: some View {
        VStack(alignment: .leading, spacing: RIGTheme.Spacing.s) {
            RIGSectionHeader(title: "Recent looks")
            if looks.isEmpty {
                Text("Nothing saved yet. Looks you keep will show up here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: RIGTheme.Spacing.m) {
                        ForEach(Array(looks.prefix(6))) { look in
                            NavigationLink {
                                LookDetailView(look: look)
                            } label: {
                                LookCard(look: look)
                                    .frame(width: 168)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    /// Removes image directories with no matching garment. Runs once per launch
    /// and only ever touches directories named after a UUID that no longer
    /// exists in the store.
    @MainActor
    private func sweepOrphanedImagesOnce() async {
        guard !hasSweptOrphanedImages else { return }
        hasSweptOrphanedImages = true
        let knownIDs = Set(items.map(\.id))
        let store = services.imageStore
        _ = await Task.detached(priority: .background) {
            store.removeOrphans(knownGarmentIDs: knownIDs)
        }.value
    }
}

#Preview {
    HomeView(selectedTab: .constant(.home))
        .modelContainer(PreviewData.container())
        .environment(\.rigServices, .preview())
}
