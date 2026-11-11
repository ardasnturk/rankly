import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var refresher: RankRefresher
    @Query(sort: \TrackedApp.addedAt) private var apps: [TrackedApp]
    @State private var selection: PersistentIdentifier?
    @State private var showAddApp = false
    @AppStorage("country") private var country = "us"

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                let mine = apps.filter { !$0.isCompetitor }
                let rivals = apps.filter(\.isCompetitor)
                if !mine.isEmpty {
                    Section("My Apps") { ForEach(mine) { AppRow(app: $0).tag($0.id) } }
                }
                if !rivals.isEmpty {
                    Section("Competitors") { ForEach(rivals) { AppRow(app: $0).tag($0.id) } }
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 250)
            .overlay {
                if apps.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "sparkle.magnifyingglass")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(.tint)
                        Text("No Apps").font(.headline)
                        Text("Add an app to start tracking.")
                            .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Button("Add App") { showAddApp = true }.buttonStyle(.borderedProminent)
                    }
                    .padding()
                }
            }
            .safeAreaInset(edge: .top) {
                HStack(spacing: 8) {
                    RanklyMark(size: 24)
                    Wordmark(font: .title3.weight(.heavy))
                    Spacer()
                }
                .padding(.horizontal, 14).padding(.top, 4).padding(.bottom, 6)
            }
            .toolbar {
                ToolbarItem {
                    Button { showAddApp = true } label: { Label("Add App", systemImage: "plus") }
                }
            }
            .safeAreaInset(edge: .bottom) {
                RefreshStatus().padding(10)
                    .background(.bar)
            }
        } detail: {
            if let app = apps.first(where: { $0.id == selection }) {
                KeywordsView(app: app, country: $country)
                    .id(app.id)
                    .appPalette(from: app.iconURL)
            } else {
                VStack(spacing: 14) {
                    RanklyMark(size: 72).shadow(color: Theme.purple.opacity(0.35), radius: 18, y: 8)
                    Text("Select an App").font(.title2.bold())
                    Text("Select an app on the left or add a new one.").foregroundStyle(.secondary)
                    Button("Add App") { showAddApp = true }.buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $showAddApp) {
            AddAppSheet(country: country) { info, competitor in
                selection = addApp(info, competitor: competitor).id
            }
        }
        .onAppear {
            if selection == nil { selection = apps.first?.id }
        }
        .onReceive(NotificationCenter.default.publisher(for: .selectApp)) { note in
            if let appId = note.object as? String, let app = apps.first(where: { $0.appId == appId }) {
                selection = app.id
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .refreshAll)) { _ in
            Task { await refresher.refreshAll(context: context) }
        }
    }

    @discardableResult
    private func addApp(_ info: AppInfo, competitor: Bool) -> TrackedApp {
        if let existing = apps.first(where: { $0.appId == info.id }) { return existing }
        let app = TrackedApp(appId: info.id, name: info.name, developer: info.developer,
                             iconURL: info.iconURL, isCompetitor: competitor)
        context.insert(app)
        try? context.save()
        return app
    }
}

struct AppRow: View {
    @Environment(\.modelContext) private var context
    let app: TrackedApp
    var body: some View {
        HStack(spacing: 10) {
            AppIcon(url: app.iconURL, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name).lineLimit(1)
                Text("\(app.keywords.count) keywords").font(.caption).foregroundStyle(.secondary)
            }
        }
        .contextMenu {
            Button(app.isCompetitor ? String(localized: "Move to My Apps") : String(localized: "Move to Competitors")) { app.isCompetitor.toggle() }
            Divider()
            Button("Delete", role: .destructive) { context.delete(app); try? context.save() }
        }
    }
}

struct AppIcon: View {
    let url: String?
    var size: CGFloat = 32
    var body: some View {
        if let url, url.hasPrefix("demo:") {
            DemoIcon(spec: url, size: size)
        } else {
            remote
        }
    }

    private var remote: some View {
        AsyncImage(url: url.flatMap(URL.init(string:))) { img in
            img.resizable()
        } placeholder: {
            Color.secondary.opacity(0.15)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
    }
}

struct RefreshStatus: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var refresher: RankRefresher
    var body: some View {
        HStack {
            if refresher.isRefreshing {
                ProgressView(value: Double(refresher.progress.done), total: Double(max(1, refresher.progress.total)))
                Text("\(refresher.progress.done)/\(refresher.progress.total)").font(.caption).monospacedDigit()
            } else {
                Text(refresher.lastRun.map { String(localized: "Last updated: \($0.formatted(.relative(presentation: .named)))") } ?? String(localized: "Not updated yet"))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { Task { await refresher.refreshAll(context: context) } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh all (⌘R)")
            }
        }
    }
}
