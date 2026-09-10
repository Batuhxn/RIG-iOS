import SwiftData
import SwiftUI

@main
struct RIGApp: App {
    /// Built once at launch. Both the SwiftData stack and the image store can
    /// fail, and if either does the user is told rather than shown an app that
    /// silently forgets everything.
    private let startup: StartupResult

    init() {
        startup = StartupResult.make()
    }

    var body: some Scene {
        WindowGroup {
            switch startup {
            case let .ready(container, services):
                RootView()
                    .environment(\.rigServices, services)
                    .modelContainer(container)
            case let .failed(message):
                StartupFailureView(message: message)
            }
        }
    }
}

enum StartupResult {
    case ready(ModelContainer, RIGServices)
    case failed(String)

    static func make() -> StartupResult {
        do {
            let container = try RIGModelContainer.makePersistentContainer()
            let services = try RIGServices.live()
            return .ready(container, services)
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}

/// Shown when local storage could not be opened. There is nothing to retry
/// automatically and nothing to sync from, so the honest thing is to say so.
struct StartupFailureView: View {
    let message: String

    var body: some View {
        RIGEmptyState(
            symbol: "externaldrive.badge.exclamationmark",
            title: "RIG could not open your wardrobe",
            message: "Local storage is unavailable on this device, so nothing can be loaded or saved right now.\n\n\(message)"
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RIGTheme.pageBackground)
    }
}
