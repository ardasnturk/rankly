import Foundation
import SwiftData

/// One day of an app's App Store top-chart positions in one country (top 200; nil = not in the list).
/// "Main" chart is Top Free for free apps and Top Paid for paid apps.
@Model
final class ChartSnapshot {
    var appId: String
    var country: String
    var date: Date
    var genreId: String
    var genreName: String
    var paid: Bool
    var overall: Int?            // Top Free/Paid, all apps
    var category: Int?           // Top Free/Paid in the app's primary category
    var grossingOverall: Int?
    var grossingCategory: Int?

    init(appId: String, country: String, date: Date = .now, genreId: String, genreName: String, paid: Bool) {
        self.appId = appId
        self.country = country
        self.date = date
        self.genreId = genreId
        self.genreName = genreName
        self.paid = paid
    }
}

/// Which countries an app's charts are checked in: countries with tracked keywords, countries with a saved
/// analysis, plus ones the user added in the Charts view (stored per app in UserDefaults).
enum ChartCountries {
    private static func key(_ appId: String) -> String { "chartCountries.\(appId)" }

    static func added(_ appId: String) -> [String] {
        UserDefaults.standard.stringArray(forKey: key(appId)) ?? []
    }

    static func add(_ country: String, appId: String) {
        var list = added(appId)
        guard !list.contains(country) else { return }
        list.append(country)
        UserDefaults.standard.set(list, forKey: key(appId))
    }

    static func remove(_ country: String, appId: String) {
        UserDefaults.standard.set(added(appId).filter { $0 != country }, forKey: key(appId))
    }

    static func countries(for app: TrackedApp, extra: [String] = []) -> Set<String> {
        Set(app.keywords.map(\.country)).union(added(app.appId)).union(extra)
    }

    /// Removes an app's chart history (called when the app is deleted).
    @MainActor
    static func deleteHistory(appId: String, context: ModelContext) {
        try? context.delete(model: ChartSnapshot.self, where: #Predicate { $0.appId == appId })
    }
}

extension RankRefresher {
    /// Checks top charts for every tracked app in its chart countries, once per day per (app, country).
    /// Competitors are also checked in all of your apps' countries. Chart pages are cached per (country, genre),
    /// so apps in the same category share requests.
    func refreshCharts(context: ModelContext, force: Bool = false, only: [TrackedApp]? = nil) async {
        guard !chartsRefreshing else { return }
        let all = (try? context.fetch(FetchDescriptor<TrackedApp>())) ?? []
        let apps = (only ?? all).filter { !$0.appId.hasPrefix("demo") }
        guard !apps.isEmpty else { return }
        chartsRefreshing = true
        defer { chartsRefreshing = false; try? context.save() }

        let fallback = UserDefaults.standard.string(forKey: "country") ?? "us"
        let mine = all.filter { !$0.isCompetitor }
            .reduce(into: Set<String>()) { $0.formUnion(ChartCountries.countries(for: $1, extra: extraChartCountries($1.appId))) }
        let today = ((try? context.fetch(FetchDescriptor<ChartSnapshot>())) ?? [])
            .filter { Calendar.current.isDateInToday($0.date) }

        for app in apps {
            var countries = ChartCountries.countries(for: app, extra: extraChartCountries(app.appId))
            if app.isCompetitor { countries.formUnion(mine) }
            if countries.isEmpty { countries = [fallback] }
            let todo = countries.sorted().filter { c in
                force || !today.contains { $0.appId == app.appId && $0.country == c }
            }
            guard !todo.isEmpty else { continue }
            guard let info = try? await AppStoreClient.shared.lookup(ids: [app.appId], country: todo[0]).first else { continue }
            let genre = info.primaryGenreId
            let paid = info.isFree == false
            for country in todo {
                do {
                    let overall = try await AppStoreClient.shared.topCharts(genreId: "36", country: country)
                    var cat: TopCharts?
                    if let genre { cat = try await AppStoreClient.shared.topCharts(genreId: genre, country: country) }
                    let snap = today.first { $0.appId == app.appId && $0.country == country } ?? {
                        let s = ChartSnapshot(appId: app.appId, country: country, genreId: genre ?? "36",
                                              genreName: info.genre ?? "", paid: paid)
                        context.insert(s)
                        return s
                    }()
                    snap.date = .now
                    snap.genreId = genre ?? "36"
                    snap.genreName = info.genre ?? ""
                    snap.paid = paid
                    snap.overall = TopCharts.rank(app.appId, in: paid ? overall.paid : overall.free)
                    snap.grossingOverall = TopCharts.rank(app.appId, in: overall.grossing)
                    snap.category = cat.flatMap { TopCharts.rank(app.appId, in: paid ? $0.paid : $0.free) }
                    snap.grossingCategory = cat.flatMap { TopCharts.rank(app.appId, in: $0.grossing) }
                } catch {
                    if case AppStoreError.blocked = error { return }   // try again later
                }
            }
        }
    }
}
