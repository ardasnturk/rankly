import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject private var updater: UpdaterViewModel
    @EnvironmentObject private var integration: IntegrationStore
    @EnvironmentObject private var appDelegate: AppDelegate
    @State private var apiEnabled = AppDelegate.apiEnabled
    @State private var mcpCommand: String?
    @State private var copiedMCP = false
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
                Toggle("Local API for Vitrin and MCP clients", isOn: $apiEnabled)
                    .onChange(of: apiEnabled) { _, on in appDelegate.setAPIEnabled(on) }
                if apiEnabled {
                    if let port = integration.apiPort {
                        LabeledContent("Address") { Text(verbatim: "http://127.0.0.1:\(port)").font(.callout.monospaced()).textSelection(.enabled) }
                    } else if let err = integration.apiError {
                        Text("Couldn't start the local API: \(err)").font(.caption).foregroundStyle(.red)
                    }
                    if integration.clients.isEmpty {
                        Text("No connected apps. When Vitrin connects, Rankly asks for your approval.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(integration.clients) { c in
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(c.name)
                                Text(c.lastUsed.map { String(localized: "Last used \($0.formatted(.relative(presentation: .named)))") } ?? String(localized: "Never used"))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Revoke", role: .destructive) { integration.revoke(c.id) }
                        }
                    }
                    if let cmd = mcpCommand {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Run this once in Terminal. The token is shown only now.").font(.caption).foregroundStyle(.secondary)
                            Text(verbatim: cmd).font(.caption.monospaced()).textSelection(.enabled)
                                .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.5)))
                            Button(copiedMCP ? String(localized: "Copied") : String(localized: "Copy")) {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(cmd, forType: .string)
                                copiedMCP = true
                            }
                        }
                    } else if let port = integration.apiPort {
                        Button("Connect Claude Code (MCP)…") {
                            let token = integration.addClient(name: "MCP")
                            mcpCommand = "claude mcp add --transport http rankly http://127.0.0.1:\(port)/mcp --header \"Authorization: Bearer \(token)\""
                        }
                    }
                }
            } header: {
                Text("Integrations")
            } footer: {
                Text("Vitrin and MCP clients such as Claude Code can read your ranks and analyses, add keywords and start analyses. The API only listens on this Mac.")
                    .font(.caption).foregroundStyle(.secondary)
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
