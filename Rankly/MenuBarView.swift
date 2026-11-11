import SwiftUI
import SwiftData

/// Compact menu bar window: your apps' keywords, biggest movers, quick actions.
struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var refresher: RankRefresher
    @EnvironmentObject private var updater: UpdaterViewModel
    @Query(sort: \TrackedApp.addedAt) private var apps: [TrackedApp]
    @AppStorage("menuBarAppId") private var selectedAppId = ""
    @State private var palette = AppPalette.system

    private var mine: [TrackedApp] { apps.filter { !$0.isCompetitor } }
    private var app: TrackedApp? { mine.first { $0.appId == selectedAppId } ?? mine.first }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let app {
                content(app)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "sparkle.magnifyingglass").font(.largeTitle).foregroundStyle(.tint)
                    Text("No apps added yet").font(.headline)
                    Button("Open Rankly") { open(nil) }.buttonStyle(.borderedProminent)
                }
                .padding(24)
            }
            Divider()
            footer
        }
        .frame(width: 360)
        .environment(\.appPalette, palette)
        .tint(palette.fromIcon ? palette.primary : nil)
        .task(id: app?.iconURL) { palette = await PaletteCache.shared.palette(for: app?.iconURL) }
    }

    private var header: some View {
        HStack(spacing: 8) {
            RanklyMark(size: 22)
            Text("Rankly").font(.headline)
            Spacer()
            if refresher.isRefreshing {
                ProgressView().controlSize(.small)
                Text("\(refresher.progress.done)/\(refresher.progress.total)")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            } else {
                Text(refresher.lastRun.map { $0.formatted(.relative(presentation: .named)) } ?? String(localized: "not updated"))
                    .font(.caption).foregroundStyle(.secondary)
                Button { Task { await refresher.refreshAll(context: context) } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh all")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(palette.wash(0.22))
    }

    @ViewBuilder
    private func content(_ app: TrackedApp) -> some View {
        let kws = app.keywords
        let byCountry = Dictionary(grouping: kws, by: \.country)
        let country = byCountry.keys.contains(UserDefaults.standard.string(forKey: "country") ?? "us")
            ? (UserDefaults.standard.string(forKey: "country") ?? "us") : (byCountry.keys.sorted().first ?? "us")
        let rows = (byCountry[country] ?? []).sorted { $0.rankSort < $1.rankSort }
        let movers = rows.filter { ($0.change ?? 0) != 0 }.sorted { abs($0.change ?? 0) > abs($1.change ?? 0) }

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                AppIcon(url: app.iconURL, size: 30)
                VStack(alignment: .leading, spacing: 0) {
                    Text(app.name).font(.callout.weight(.semibold)).lineLimit(1)
                    let sf = Storefronts.byCode(country)
                    Text("\(sf.flag) \(sf.name) · \(rows.count) keywords").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if mine.count > 1 {
                    Menu {
                        ForEach(mine) { a in Button(a.name) { selectedAppId = a.appId } }
                    } label: { Image(systemName: "chevron.up.chevron.down") }
                    .menuStyle(.borderlessButton).fixedSize()
                }
            }

            let ranked = rows.compactMap(\.currentRank)
            HStack(spacing: 0) {
                MiniStat(title: "Top 10", value: ranked.filter { $0 <= 10 }.count)
                MiniStat(title: "Top 50", value: ranked.filter { $0 <= 50 }.count)
                MiniStat(title: "Rising", value: rows.filter { ($0.change ?? 0) > 0 }.count, color: .green)
                MiniStat(title: "Falling", value: rows.filter { ($0.change ?? 0) < 0 }.count, color: .red)
            }

            if !movers.isEmpty {
                Text("Top movers").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(movers.prefix(4)) { kw in row(kw) }
            }
            Text("Keywords").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(rows.prefix(25)) { kw in row(kw) }
                }
            }
            .frame(maxHeight: 220)
        }
        .padding(12)
    }

    private func row(_ kw: Keyword) -> some View {
        HStack(spacing: 8) {
            Text(kw.term).lineLimit(1)
            Spacer()
            ChangeBadge(change: kw.change)
            Text(kw.currentRank.map { "#\($0)" } ?? (kw.latest == nil ? "…" : ">250"))
                .font(.callout.weight(.semibold).monospacedDigit())
                .frame(width: 48, alignment: .trailing)
        }
        .padding(.vertical, 3).padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(.primary.opacity(0.04)))
    }

    private var footer: some View {
        HStack {
            Button("Open Rankly") { open(app?.appId) }
            Spacer()
            Button { updater.checkForUpdates() } label: { Image(systemName: "arrow.down.circle") }
                .help("Check for updates").disabled(!updater.canCheckForUpdates)
            Button { NSApp.activate(ignoringOtherApps: true); openSettings() } label: { Image(systemName: "gearshape") }
                .help("Settings")
            Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                .help("Quit Rankly")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private func open(_ appId: String?) {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "main")
        if let appId {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                NotificationCenter.default.post(name: .selectApp, object: appId)
            }
        }
    }
}

private struct MiniStat: View {
    let title: LocalizedStringKey
    let value: Int
    var color: Color = .primary
    var body: some View {
        VStack(spacing: 0) {
            Text("\(value)").font(.title3.bold().monospacedDigit()).foregroundStyle(color)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
