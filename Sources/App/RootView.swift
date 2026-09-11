import SwiftData
import SwiftUI
import UIKit

enum RIGTab: Hashable {
    case wardrobe
    case looks
    case profile
}

/// The three tabs the design specifies: Dolap, Kombin, Profil.
///
/// There is no Home tab. Its two real jobs have moved rather than gone — the
/// wardrobe-readiness check and the ways into outfit building now open the
/// Kombin tab, where they are about the thing the user is looking at, and the
/// once-per-launch orphan sweep runs here, at the root, where it never depended
/// on a tab being visited in the first place.
struct RootView: View {
    @State private var selectedTab: RIGTab = .wardrobe

    @Environment(\.rigServices) private var services
    @Query private var items: [ClothingItem]
    @State private var hasSweptOrphanedImages = false

    init() {
        RootView.configureTabBarAppearance()
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            WardrobeView()
                .tabItem {
                    Label("Dolap", systemImage: "square.grid.2x2")
                }
                .tag(RIGTab.wardrobe)

            LooksView()
                .tabItem {
                    Label("Kombin", systemImage: "sparkles")
                }
                .tag(RIGTab.looks)

            ProfileView()
                .tabItem {
                    Label("Profil", systemImage: "person")
                }
                .tag(RIGTab.profile)
        }
        .tint(RIGTheme.accent)
        .task {
            await sweepOrphanedImagesOnce()
        }
    }

    /// The design's tab bar: a translucent blur over the ground, a hairline
    /// above it, accent for the selected tab and dimmed text for the rest.
    ///
    /// Done through `UITabBarAppearance` rather than by drawing a custom bar so
    /// that the system keeps owning what it is good at — safe-area insets,
    /// VoiceOver, the hide-on-push behaviour the design shows, and whatever
    /// changes in the next iOS.
    private static func configureTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        appearance.backgroundColor = UIColor(RIGTheme.pageBackground).withAlphaComponent(0.82)
        appearance.shadowColor = UIColor(RIGTheme.text(8))

        let accent = UIColor(RIGTheme.accent)
        let dimmed = UIColor(RIGTheme.text(42))
        let label: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10, weight: .regular)
        ]

        for layout in [appearance.stackedLayoutAppearance, appearance.inlineLayoutAppearance, appearance.compactInlineLayoutAppearance] {
            layout.selected.iconColor = accent
            layout.selected.titleTextAttributes = label.merging([.foregroundColor: accent]) { _, new in new }
            layout.normal.iconColor = dimmed
            layout.normal.titleTextAttributes = label.merging([.foregroundColor: dimmed]) { _, new in new }
        }

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    /// Removes image directories with no matching garment. Runs once per launch
    /// and only ever touches directories named after a UUID that no longer
    /// exists in the store.
    ///
    /// This used to live on the home screen, which meant it only ran if that
    /// tab was the one the user landed on. At the root it runs regardless.
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
    RootView()
        .modelContainer(PreviewData.container())
        .environment(\.rigServices, .preview())
        .nocturneAppearance()
}
