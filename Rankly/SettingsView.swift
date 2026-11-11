import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject private var updater: UpdaterViewModel
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    RanklyMark(size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Wordmark(font: .title2.weight(.heavy))
                        Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section("General") {
                Toggle("Show in menu bar", isOn: $showMenuBarExtra)
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
                Text("With the menu bar item on, Rankly keeps updating daily ranks in the background even after you close the main window.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Updates") {
                Toggle("Automatically check for updates", isOn: Binding(
                    get: { updater.automaticallyChecks }, set: { updater.automaticallyChecks = $0 }))
                Toggle("Automatically download and install updates", isOn: Binding(
                    get: { updater.automaticallyDownloads }, set: { updater.automaticallyDownloads = $0 }))
                    .disabled(!updater.automaticallyChecks)
                HStack {
                    Text(updater.lastCheck.map { String(localized: "Last checked: \($0.formatted(.relative(presentation: .named)))") } ?? String(localized: "Not checked yet"))
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Check Now") { updater.checkForUpdates() }
                        .disabled(!updater.canCheckForUpdates)
                }
            }
            Section {
                HStack {
                    Link("Website", destination: URL(string: "https://rankly.ardasnturk.com")!)
                    Text("·").foregroundStyle(.secondary)
                    Link("User guide", destination: URL(string: "https://rankly.ardasnturk.com/guide.html")!)
                    Text("·").foregroundStyle(.secondary)
                    Link("Privacy", destination: URL(string: "https://rankly.ardasnturk.com/privacy.html")!)
                    Text("·").foregroundStyle(.secondary)
                    Link("GitHub", destination: URL(string: "https://github.com/ardasnturk/rankly")!)
                }
                .font(.callout)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}
