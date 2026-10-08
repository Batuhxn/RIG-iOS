import SwiftUI

enum RIGTab: Hashable {
    case home
    case wardrobe
    case looks
    case avatar
}

struct RootView: View {
    @State private var selectedTab: RIGTab = .home

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house")
                }
                .tag(RIGTab.home)

            WardrobeView()
                .tabItem {
                    Label("Wardrobe", systemImage: "square.grid.2x2")
                }
                .tag(RIGTab.wardrobe)

            LooksView()
                .tabItem {
                    Label("Looks", systemImage: "square.stack")
                }
                .tag(RIGTab.looks)

            AvatarLabView()
                .tabItem {
                    Label("Avatar", systemImage: "figure.stand")
                }
                .tag(RIGTab.avatar)
        }
    }
}

#Preview {
    RootView()
        .modelContainer(PreviewData.container())
        .environment(\.rigServices, .preview())
}
