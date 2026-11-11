import SwiftUI
import SwiftData

@main
struct RanklyApp: App {
    @StateObject private var refresher = RankRefresher()
    @StateObject private var analysis = AnalysisCenter()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(refresher)
                .environmentObject(analysis)
                .frame(minWidth: 1080, minHeight: 560)
        }
        .defaultSize(width: 1320, height: 800)
        .modelContainer(for: [TrackedApp.self, Keyword.self, RankSnapshot.self])
        .commands {
            CommandGroup(after: .newItem) {
                Button("Tüm Sıraları Yenile") {
                    NotificationCenter.default.post(name: .refreshAll, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }
    }
}

extension Notification.Name {
    static let refreshAll = Notification.Name("refreshAll")
}
