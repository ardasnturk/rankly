import SwiftUI
import SwiftData
import Charts

/// App Store top-chart positions of one app, one row per country, with history.
struct ChartsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.appPalette) private var palette
    @EnvironmentObject private var refresher: RankRefresher
    @EnvironmentObject private var center: AnalysisCenter
    let app: TrackedApp
    @Query private var snapshots: [ChartSnapshot]
    @State private var selection: String?
    @State private var addedTick = 0

    init(app: TrackedApp) {
        self.app = app
        let id = app.appId
        _snapshots = Query(filter: #Predicate<ChartSnapshot> { $0.appId == id }, sort: \.date)
    }

    struct Row: Identifiable {
        let country: String
        let history: [ChartSnapshot]      // oldest → newest, one per day
        var id: String { country }
        var latest: ChartSnapshot? { history.last }
        var previous: ChartSnapshot? { history.count > 1 ? history[history.count - 2] : nil }
        var sortKey: Int { latest?.category ?? latest?.overall.map { $0 + 1000 } ?? 9999 }

        func change(_ kp: KeyPath<ChartSnapshot, Int?>) -> Int? {
            guard let p = previous?[keyPath: kp], let c = latest?[keyPath: kp] else { return nil }
            return p - c
        }
    }

    private var rows: [Row] {
        _ = addedTick
        let byCountry = Dictionary(grouping: snapshots, by: \.country)
        var countries = ChartCountries.countries(for: app, extra: center.allResults(appId: app.appId).map(\.country))
        countries.formUnion(byCountry.keys)
        return countries.map { Row(country: $0, history: byCountry[$0] ?? []) }
            .sorted { ($0.sortKey, Storefronts.byCode($0.country).name) < ($1.sortKey, Storefronts.byCode($1.country).name) }
    }

    var body: some View {
        let rows = rows
        VStack(spacing: 0) {
            bar(rows)
            Divider()
            table(rows)
            if let sel = selection, let row = rows.first(where: { $0.country == sel }) {
                Divider()
                detail(row).frame(height: 230)
            }
        }
    }

    private func bar(_ rows: [Row]) -> some View {
        let latest = snapshots.last
        return HStack(spacing: 10) {
            Image(systemName: "chart.bar.xaxis").foregroundStyle(.secondary)
            if let latest {
                Text(latest.paid ? "Top Paid" : "Top Free").bold()
                if !latest.genreName.isEmpty { Text("· \(latest.genreName)").foregroundStyle(.secondary) }
            }
            Text("· top 200 iPhone charts, checked daily").foregroundStyle(.secondary)
            Spacer()
            Menu {
                let have = Set(rows.map(\.country))
                ForEach(Storefronts.all.filter { !have.contains($0.code) }.sorted { $0.name < $1.name }) { sf in
                    Button("\(sf.flag) \(sf.name)") {
                        ChartCountries.add(sf.code, appId: app.appId)
                        addedTick += 1
                        Task { await refresher.refreshCharts(context: context, only: [app]) }
                    }
                }
            } label: { Label("Add Country", systemImage: "plus") }
            .fixedSize()
            Button {
                Task { await refresher.refreshCharts(context: context, force: true, only: [app]) }
            } label: {
                if refresher.chartsRefreshing { ProgressView().controlSize(.small) } else { Label("Refresh Charts", systemImage: "arrow.clockwise") }
            }
            .disabled(refresher.chartsRefreshing)
        }
        .font(.callout)
        .padding(.horizontal, 16).padding(.vertical, 9)
        .background(.bar)
    }

    private func table(_ rows: [Row]) -> some View {
        Table(rows, selection: $selection) {
            TableColumn("Country") { r in
                let sf = Storefronts.byCode(r.country)
                Text("\(sf.flag) \(sf.name)")
            }
            .width(min: 140, ideal: 170)
            TableColumn("All Apps") { r in ChartRankCell(row: r, kp: \.overall) }.width(min: 90, ideal: 100)
            TableColumn("Category") { r in ChartRankCell(row: r, kp: \.category) }.width(min: 90, ideal: 100)
            TableColumn("Grossing") { r in ChartRankCell(row: r, kp: \.grossingOverall) }.width(min: 90, ideal: 100)
            TableColumn("Grossing (Category)") { r in ChartRankCell(row: r, kp: \.grossingCategory) }.width(min: 110, ideal: 130)
            TableColumn("Trend") { r in
                RankSparkline(values: r.history.suffix(14).map { $0.category ?? $0.overall }).frame(height: 18)
            }
            .width(90)
            TableColumn("Checked") { r in
                Text(r.latest.map { $0.date.formatted(.relative(presentation: .named)) } ?? "–")
                    .foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 110)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            let manual = Set(ChartCountries.added(app.appId))
            Button("Remove Country", role: .destructive) {
                for c in ids { ChartCountries.remove(c, appId: app.appId) }
                let list = Array(ids), appId = app.appId
                try? context.delete(model: ChartSnapshot.self, where: #Predicate { list.contains($0.country) && $0.appId == appId })
                addedTick += 1
            }
            .disabled(ids.isEmpty || !ids.allSatisfy(manual.contains))
        }
        .overlay {
            if snapshots.isEmpty && !refresher.chartsRefreshing {
                VStack(spacing: 8) {
                    Image(systemName: "chart.bar.xaxis").font(.system(size: 30)).foregroundStyle(.tint)
                    Text("No chart data yet").font(.headline)
                    Text("Rankly checks where the app sits in the App Store's top charts once a day.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Check Now") {
                        Task { await refresher.refreshCharts(context: context, force: true, only: [app]) }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: 340)
            }
        }
    }

    private func detail(_ row: Row) -> some View {
        let sf = Storefronts.byCode(row.country)
        let series: [(String, KeyPath<ChartSnapshot, Int?>)] = [
            (String(localized: "All Apps"), \.overall), (String(localized: "Category"), \.category),
            (String(localized: "Grossing"), \.grossingOverall),
        ]
        let points = series.flatMap { name, kp in
            row.history.compactMap { s in s[keyPath: kp].map { (name: name, date: s.date, rank: $0) } }
        }
        return VStack(alignment: .leading, spacing: 6) {
            Text("\(sf.flag) \(sf.name) · Chart History").font(.headline)
            if Set(points.map { Calendar.current.startOfDay(for: $0.date) }).count < 2 {
                Text("Not in the top 200 yet, or the chart needs at least 2 days of data.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            } else {
                Chart(Array(points.enumerated()), id: \.offset) { _, p in
                    LineMark(x: .value("Date", p.date, unit: .day), y: .value("Rank", p.rank))
                        .foregroundStyle(by: .value("Chart", p.name))
                        .interpolationMethod(.monotone)
                    PointMark(x: .value("Date", p.date, unit: .day), y: .value("Rank", p.rank))
                        .foregroundStyle(by: .value("Chart", p.name))
                        .symbolSize(18)
                }
                .chartYScale(domain: .automatic(includesZero: false, reversed: true))
            }
        }
        .padding(14)
    }
}

struct ChartRankCell: View {
    let row: ChartsView.Row
    let kp: KeyPath<ChartSnapshot, Int?>
    var body: some View {
        HStack(spacing: 6) {
            if let latest = row.latest {
                if let r = latest[keyPath: kp] {
                    Text("#\(r)").monospacedDigit().bold()
                    ChangeBadge(change: row.change(kp)).fixedSize()
                } else {
                    Text("—").foregroundStyle(.secondary).help("Not in the top 200")
                }
            } else {
                Text("…").foregroundStyle(.secondary)
            }
        }
    }
}

/// Small rank trend line; nil values (not ranked) are skipped.
struct RankSparkline: View {
    let values: [Int?]
    var body: some View {
        let ranks = values.compactMap { $0 }.map(Double.init)
        Canvas { ctx, size in
            guard ranks.count > 1, let lo = ranks.min(), let hi = ranks.max() else { return }
            let span = max(hi - lo, 1)
            var path = Path()
            for (i, r) in ranks.enumerated() {
                let pt = CGPoint(x: size.width * CGFloat(i) / CGFloat(ranks.count - 1), y: size.height * CGFloat((r - lo) / span))
                i == 0 ? path.move(to: pt) : path.addLine(to: pt)
            }
            ctx.stroke(path, with: .color((ranks.last ?? 0) <= (ranks.first ?? 0) ? .green : .red), lineWidth: 1.5)
        }
    }
}
