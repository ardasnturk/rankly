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
                        Text("Sürüm \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section("Genel") {
                Toggle("Menü çubuğunda göster", isOn: $showMenuBarExtra)
                Toggle("Girişte başlat", isOn: $launchAtLogin)
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
                Text("Menü çubuğu açıkken ana pencereyi kapatsan da Rankly günlük sıralamaları arka planda günceller.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Güncellemeler") {
                Toggle("Güncellemeleri otomatik denetle", isOn: Binding(
                    get: { updater.automaticallyChecks }, set: { updater.automaticallyChecks = $0 }))
                Toggle("Güncellemeleri otomatik indir ve kur", isOn: Binding(
                    get: { updater.automaticallyDownloads }, set: { updater.automaticallyDownloads = $0 }))
                    .disabled(!updater.automaticallyChecks)
                HStack {
                    Text(updater.lastCheck.map { "Son denetim: \($0.formatted(.relative(presentation: .named)))" } ?? "Henüz denetlenmedi")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Şimdi Denetle") { updater.checkForUpdates() }
                        .disabled(!updater.canCheckForUpdates)
                }
            }
            Section {
                HStack {
                    Link("Web sitesi", destination: URL(string: "https://rankly.ardasnturk.com")!)
                    Text("·").foregroundStyle(.secondary)
                    Link("Kullanım kılavuzu", destination: URL(string: "https://rankly.ardasnturk.com/guide.html")!)
                    Text("·").foregroundStyle(.secondary)
                    Link("Gizlilik", destination: URL(string: "https://rankly.ardasnturk.com/privacy.html")!)
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
