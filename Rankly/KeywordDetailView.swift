import SwiftUI
import SwiftData
import Charts

struct KeywordDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.appPalette) private var palette
    @EnvironmentObject private var refresher: RankRefresher
    @Query private var trackedApps: [TrackedApp]
    let keyword: Keyword

    @State private var ranking: [(rank: Int, info: AppInfo)] = []
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(keyword.term).font(.title2.bold())
                    let sf = Storefronts.byCode(keyword.country)
                    Text("\(sf.flag) \(sf.name)").foregroundStyle(.secondary)
                }
                HStack(spacing: 20) {
                    Stat(title: "Sıra", value: keyword.currentRank.map { "#\($0)" } ?? "—")
                    Stat(title: "Popülerlik", value: keyword.popularity.map { "~\($0)" } ?? "—", color: palette.primary)
                    Stat(title: "Zorluk", value: keyword.difficulty.map(String.init) ?? "—",
                         color: difficultyColor(keyword.difficulty))
                }

                history
                Divider()
                rankingList
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: keyword.id) { await loadRanking() }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sıra Geçmişi").font(.headline)
            let snaps = keyword.sortedSnapshots.filter { $0.rank != nil }
            if snaps.count < 2 {
                Text("Grafik için en az 2 günlük veri gerekiyor.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Chart(snaps, id: \.date) { s in
                    LineMark(x: .value("Tarih", s.date, unit: .day), y: .value("Sıra", s.rank ?? 0))
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .foregroundStyle(palette.gradient)
                    PointMark(x: .value("Tarih", s.date, unit: .day), y: .value("Sıra", s.rank ?? 0))
                        .symbolSize(22)
                        .foregroundStyle(palette.primary)
                }
                .chartYScale(domain: .automatic(includesZero: false, reversed: true))
                .frame(height: 160)
            }
        }
    }

    private var rankingList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Bu kelimede sıralananlar").font(.headline)
                Spacer()
                if loading { ProgressView().controlSize(.small) }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            ForEach(ranking, id: \.info.id) { item in
                let tracked = trackedApps.first { $0.appId == item.info.id }
                HStack(spacing: 8) {
                    Text("\(item.rank)").monospacedDigit().foregroundStyle(.secondary).frame(width: 26, alignment: .trailing)
                    AppIcon(url: item.info.iconURL, size: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.info.name).lineLimit(1).truncationMode(.tail)
                            .fontWeight(item.info.id == keyword.app?.appId ? .bold : .regular)
                        Text("★ \(item.info.rating, specifier: "%.1f") · \(item.info.ratingCount.formatted()) puan")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if tracked != nil {
                        Text("Takipte").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Button("Takip et") { track(item.info) }.controlSize(.small)
                    }
                }
            }
        }
    }

    private func loadRanking() async {
        if Demo.isOn { return }   // demo never talks to Apple
        loading = true; error = nil
        do {
            let ids = try await AppStoreClient.shared.searchRanking(term: keyword.term, country: keyword.country)
            let top = Array(ids.prefix(30))
            let infos = try await AppStoreClient.shared.lookup(ids: top, country: keyword.country)
            let byId = Dictionary(uniqueKeysWithValues: infos.map { ($0.id, $0) })
            ranking = top.enumerated().compactMap { i, id in byId[id].map { (i + 1, $0) } }
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    /// Track a competitor and copy this keyword to it so ranks can be compared.
    private func track(_ info: AppInfo) {
        let app = TrackedApp(appId: info.id, name: info.name, developer: info.developer,
                             iconURL: info.iconURL, isCompetitor: true)
        context.insert(app)
        let kw = Keyword(term: keyword.term, country: keyword.country, app: app)
        context.insert(kw)
        try? context.save()
        Task { await refresher.refresh(keywords: [kw], context: context) }
    }
}
