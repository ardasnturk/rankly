import SwiftUI
import Sparkle

/// Sparkle wrapper. Feed URL and public EdDSA key live in Info.plist (SUFeedURL / SUPublicEDKey).
@MainActor
final class UpdaterViewModel: ObservableObject {
    private let controller: SPUStandardUpdaterController
    @Published var canCheckForUpdates = false

    init() {
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheckForUpdates)
    }

    var updater: SPUUpdater { controller.updater }

    func checkForUpdates() { controller.checkForUpdates(nil) }

    var automaticallyChecks: Bool {
        get { updater.automaticallyChecksForUpdates }
        set { objectWillChange.send(); updater.automaticallyChecksForUpdates = newValue }
    }

    var automaticallyDownloads: Bool {
        get { updater.automaticallyDownloadsUpdates }
        set { objectWillChange.send(); updater.automaticallyDownloadsUpdates = newValue }
    }

    var lastCheck: Date? { updater.lastUpdateCheckDate }
}

struct CheckForUpdatesButton: View {
    @ObservedObject var updater: UpdaterViewModel
    var body: some View {
        Button("Güncellemeleri Denetle…") { updater.checkForUpdates() }
            .disabled(!updater.canCheckForUpdates)
    }
}
