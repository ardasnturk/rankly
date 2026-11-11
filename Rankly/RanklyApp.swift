import SwiftUI
import SwiftData

@main
struct RanklyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra = true

    var body: some Scene {
        Window("Rankly", id: "main") {
            Group {
                if Demo.showMenuBarPanel {
                    MenuBarView()
                        .environmentObject(appDelegate.updater)
                        .fixedSize()
                } else {
                    ContentView()
                        .frame(minWidth: 1080, minHeight: 560)
                }
            }
            .environmentObject(appDelegate.refresher)
            .environmentObject(appDelegate.analysis)
            .environmentObject(appDelegate.integration)
        }
        .defaultSize(width: 1320, height: 800)
        .modelContainer(appDelegate.container)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesButton(updater: appDelegate.updater)
            }
            CommandGroup(after: .newItem) {
                Button("Refresh All Ranks") {
                    NotificationCenter.default.post(name: .refreshAll, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }

        MenuBarExtra(isInserted: $showMenuBarExtra) {
            MenuBarView()
                .environmentObject(appDelegate.refresher)
                .environmentObject(appDelegate.updater)
                .modelContainer(appDelegate.container)
        } label: {
            Image("MenuBarIcon")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(appDelegate.updater)
                .environmentObject(appDelegate.integration)
                .environmentObject(appDelegate)
        }
    }
}

/// Owns long-lived services so they keep running when the main window is closed (menu bar mode).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let container: ModelContainer = {
        if Demo.isOn { return Demo.container() }
        do { return try ModelContainer(for: TrackedApp.self, Keyword.self, RankSnapshot.self) }
        catch { fatalError("SwiftData store could not be opened: \(error)") }
    }()
    let refresher = RankRefresher()
    let analysis = AnalysisCenter()
    let updater = UpdaterViewModel()
    let integration = IntegrationStore()
    private(set) lazy var api = RanklyAPI(container: container, analysis: analysis, refresher: refresher, store: integration)

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Demo.isOn else { return }   // demo never talks to Apple
        refresher.startSchedule(context: container.mainContext)
        if Self.apiEnabled { api.start() }
    }

    /// Local integration API (Vitrin, MCP). On by default; every client still needs the user's approval to pair.
    static var apiEnabled: Bool {
        (UserDefaults.standard.object(forKey: "integration.apiEnabled") as? Bool) ?? true
    }

    func setAPIEnabled(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: "integration.apiEnabled")
        on ? api.start() : api.stop()
    }

    /// Quit with the last window only when the menu bar extra is turned off.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        (UserDefaults.standard.object(forKey: "showMenuBarExtra") as? Bool) == false
    }
}

extension Notification.Name {
    static let refreshAll = Notification.Name("refreshAll")
    static let selectApp = Notification.Name("selectApp")
}
