import Foundation
import SwiftData

/// Fetches ranks / difficulty / popularity and stores a daily snapshot per keyword.
@MainActor
final class RankRefresher: ObservableObject {
    @Published var isRefreshing = false
    @Published var progress: (done: Int, total: Int) = (0, 0)
    @Published var lastRun: Date? = UserDefaults.standard.object(forKey: "lastRefresh") as? Date
    @Published var chartsRefreshing = false
    /// Extra chart countries per appId (countries with a saved analysis); set by AppDelegate.
    var extraChartCountries: (String) -> [String] = { _ in [] }

    private let client = AppStoreClient.shared
    private var timer: Timer?

    /// Refresh once per day: on launch if stale, then check hourly.
    func startSchedule(context: ModelContext) {
        Task { await refreshIfStale(context: context) }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshIfStale(context: context) }
        }
    }

    func refreshIfStale(context: ModelContext) async {
        if lastRun.map({ !Calendar.current.isDateInToday($0) }) ?? true {
            await refresh(keywords: (try? context.fetch(FetchDescriptor<Keyword>())) ?? [], context: context)
        }
        await refreshCharts(context: context)   // only countries without a snapshot today
    }

    func refreshAll(context: ModelContext) async {
        await refresh(keywords: (try? context.fetch(FetchDescriptor<Keyword>())) ?? [], context: context)
        await refreshCharts(context: context)
    }

    func refresh(keywords: [Keyword], context: ModelContext) async {
        guard !isRefreshing, !keywords.isEmpty else { return }
        isRefreshing = true
        progress = (0, keywords.count)
        defer {
            isRefreshing = false
            try? context.save()
        }

        // Same (term, country) shares one search request across apps.
        let groups = Dictionary(grouping: keywords) { "\($0.country)|\($0.term.lowercased())" }
        var blocked = false
        for (_, group) in groups {
            guard let first = group.first else { continue }
            let term = first.term, country = first.country
            do {
                let ids = try await client.searchRanking(term: term, country: country)
                let topInfos = (try? await client.lookup(ids: Array(ids.prefix(10)), country: country)) ?? []
                let difficulty = Scoring.difficulty(term: term, topApps: topInfos)

                var popularity = first.popularity
                let popStale = first.popularityUpdatedAt.map { Date().timeIntervalSince($0) > 5 * 86400 } ?? true
                if popStale { popularity = await Scoring.estimatePopularity(term: term, country: country, client: client) }

                for kw in group {
                    let rank = kw.app.flatMap { app in ids.firstIndex(of: app.appId).map { $0 + 1 } }
                    upsertTodaySnapshot(kw, rank: rank, count: ids.count, context: context)
                    kw.difficulty = difficulty
                    if popStale { kw.popularity = popularity; kw.popularityUpdatedAt = .now }
                    kw.lastCheckedAt = .now
                    kw.lastError = nil
                }
            } catch {
                for kw in group { kw.lastError = error.localizedDescription }
                if case AppStoreError.blocked = error { blocked = true; break }   // don't keep hitting a blocked endpoint
            }
            progress.done += group.count
            try? await Task.sleep(nanoseconds: 400_000_000) // be gentle with Apple
        }
        guard !blocked else { return }   // retry later today
        lastRun = .now
        UserDefaults.standard.set(lastRun, forKey: "lastRefresh")
    }

    private func upsertTodaySnapshot(_ kw: Keyword, rank: Int?, count: Int, context: ModelContext) {
        if let today = kw.snapshots.first(where: { Calendar.current.isDateInToday($0.date) }) {
            today.rank = rank
            today.resultCount = count
            today.date = .now
        } else {
            let snap = RankSnapshot(rank: rank, resultCount: count)
            context.insert(snap)
            snap.keyword = kw
        }
    }
}
