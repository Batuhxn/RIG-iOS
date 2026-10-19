import SwiftData
import SwiftUI

/// CI-ONLY (branch ci/gate-a-weather-ui-claude, never merged): a Debug launch
/// argument that opens Suggestions on preview data with the fixed preview
/// forecast, so Gate A2 can screenshot the weather card. It never touches the
/// user's store or the network: in-memory SwiftData plus PreviewWeatherProvider.
struct RIGWeatherDemo: View {
    static let launchArgument = "-RIGWeatherDemo"

    static var isRequested: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains(launchArgument)
        #else
        return false
        #endif
    }

    /// Pre-select a city so the card shows a forecast instead of "Choose city".
    static func prepare() {
        UserDefaults.standard.set("istanbul", forKey: "rig.weather.selectedCityID")
    }

    @State private var container = PreviewData.container()

    var body: some View {
        NavigationStack {
            SuggestionsView()
        }
        .modelContainer(container)
        .environment(\.rigServices, .preview())
    }
}
