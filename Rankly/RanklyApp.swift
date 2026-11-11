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
        }
    }
}

/// Owns long-lived services so they keep running when the main window is closed (menu bar mode).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let container: ModelContainer = {
        if Demo.isOn { return Demo.container() }
        do { return try ModelContainer(for: TrackedApp.self, Keyword.self, RankSnapshot.self) }
        catch { fatalError("SwiftData store could not be opened: \(error)") }
    }()
    let refresher = RankRefresher()
    let analysis = AnalysisCenter()
    let updater = UpdaterViewModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Demo.isOn else { return }   // demo never talks to Apple
        refresher.startSchedule(context: container.mainContext)
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
