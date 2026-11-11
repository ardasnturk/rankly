import SwiftUI
import SwiftData
import Charts

struct KeywordDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.appPalette) private var palette
    @EnvironmentObject private var refresher: RankRefresher
    @EnvironmentObject private var integration: IntegrationStore
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
                    Stat(title: "Rank", value: keyword.currentRank.map { "#\($0)" } ?? "—")
                    Stat(title: "Popularity", value: keyword.popularity.map { "~\($0)" } ?? "—", color: palette.primary)
                    Stat(title: "Difficulty", value: keyword.difficulty.map(String.init) ?? "—",
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
            Text("Rank History").font(.headline)
            let snaps = keyword.sortedSnapshots.filter { $0.rank != nil }
            if snaps.count < 2 {
                Text("The chart needs at least 2 days of data.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                let first = snaps.first?.date ?? .distantPast
                let marks = integration.events(for: keyword.app?.appId ?? "")
                    .filter { $0.date >= first && ($0.countries == nil || $0.countries!.contains(keyword.country)) }
                Chart {
                    ForEach(marks) { e in
                        RuleMark(x: .value("Date", e.date, unit: .day))
                            .foregroundStyle(.secondary.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .annotation(position: .top, alignment: .leading) {
                                Text(e.kind == "release" ? String(localized: "Release") : e.note)
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                    }
                    ForEach(snaps, id: \.date) { s in
                    LineMark(x: .value("Date", s.date, unit: .day), y: .value("Rank", s.rank ?? 0))
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .foregroundStyle(palette.gradient)
                    PointMark(x: .value("Date", s.date, unit: .day), y: .value("Rank", s.rank ?? 0))
                        .symbolSize(22)
                        .foregroundStyle(palette.primary)
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false, reversed: true))
                .frame(height: 160)
            }
        }
    }

    private var rankingList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Apps ranking for this keyword").font(.headline)
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
                        Text("★ \(item.info.rating, specifier: "%.1f") · \(item.info.ratingCount.formatted()) ratings")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if tracked != nil {
                        Text("Tracking").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Button("Track") { track(item.info) }.controlSize(.small)
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
                             iconURL: info.iconURL, isCompetitor: true, bundleId: info.bundleId)
        context.insert(app)
        let kw = Keyword(term: keyword.term, country: keyword.country, app: app)
        context.insert(kw)
        try? context.save()
        Task { await refresher.refresh(keywords: [kw], context: context) }
    }
}
