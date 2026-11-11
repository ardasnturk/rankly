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
                    Section("Uygulamalarım") { ForEach(mine) { AppRow(app: $0).tag($0.id) } }
                }
                if !rivals.isEmpty {
                    Section("Rakipler") { ForEach(rivals) { AppRow(app: $0).tag($0.id) } }
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 250)
            .overlay {
                if apps.isEmpty {
                    ContentUnavailableView("Uygulama yok", systemImage: "app.dashed",
                                           description: Text("Takip etmek için bir uygulama ekle."))
                }
            }
            .toolbar {
                ToolbarItem {
                    Button { showAddApp = true } label: { Label("Uygulama Ekle", systemImage: "plus") }
                }
            }
            .safeAreaInset(edge: .bottom) { RefreshStatus().padding(10) }
        } detail: {
            if let app = apps.first(where: { $0.id == selection }) {
                KeywordsView(app: app, country: $country)
                    .id(app.id)
            } else {
                ContentUnavailableView("Bir uygulama seç", systemImage: "chart.line.uptrend.xyaxis")
            }
        }
        .sheet(isPresented: $showAddApp) {
            AddAppSheet(country: country) { info, competitor in
                selection = addApp(info, competitor: competitor).id
            }
        }
        .onAppear {
            refresher.startSchedule(context: context)
            if selection == nil { selection = apps.first?.id }
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
                Text("\(app.keywords.count) kelime").font(.caption).foregroundStyle(.secondary)
            }
        }
        .contextMenu {
            Button(app.isCompetitor ? "Uygulamalarıma taşı" : "Rakiplere taşı") { app.isCompetitor.toggle() }
            Divider()
            Button("Sil", role: .destructive) { context.delete(app); try? context.save() }
        }
    }
}

struct AppIcon: View {
    let url: String?
    var size: CGFloat = 32
    var body: some View {
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
                Text(refresher.lastRun.map { "Son güncelleme: \($0.formatted(.relative(presentation: .named)))" } ?? "Henüz güncellenmedi")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { Task { await refresher.refreshAll(context: context) } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Tümünü yenile (⌘R)")
            }
        }
    }
}
