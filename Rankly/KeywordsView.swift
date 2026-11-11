import SwiftUI
import SwiftData

extension Keyword {
    var rankSort: Int { currentRank ?? RankSnapshot.notRanked }
    var changeSort: Int { change ?? 0 }
    var popSort: Int { popularity ?? -1 }
    var diffSort: Int { difficulty ?? 101 }
}

struct KeywordsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.appPalette) private var palette
    @EnvironmentObject private var refresher: RankRefresher
    @Bindable var app: TrackedApp
    @Binding var country: String

    @State private var newTerms = ""
    @State private var selection = Set<PersistentIdentifier>()
    @State private var sortOrder = [KeyPathComparator(\Keyword.rankSort)]
    @State private var filter = ""
    @State private var showSuggestions = false
    @State private var showInspector = false
    @AppStorage("detailMode") private var mode = "keywords"

    private var rows: [Keyword] {
        app.keywords
            .filter { $0.country == country }
            .filter { filter.isEmpty || $0.term.localizedCaseInsensitiveContains(filter) }
            .sorted(using: sortOrder)
    }

    private var selectedKeyword: Keyword? {
        guard selection.count == 1, let id = selection.first else { return nil }
        return app.keywords.first { $0.id == id }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                header
                Divider()
                if mode == "analysis" {
                    AnalysisView(app: app, country: $country, onAddKeywords: addTerms, onTrackCompetitor: trackCompetitor)
                } else {
                    addBar
                    table
                }
            }
            .frame(minWidth: 440, maxWidth: .infinity, maxHeight: .infinity)
            // Fixed-width side panel (SwiftUI .inspector caused a constraint loop crash in narrow windows).
            if showInspector && mode == "keywords" {
                Divider()
                ZStack(alignment: .topTrailing) {
                    Group {
                        if let kw = selectedKeyword {
                            KeywordDetailView(keyword: kw)
                        } else if showSuggestions {
                            SuggestionsView(app: app, country: country, onAdd: addTerms)
                        }
                    }
                    Button { showInspector = false } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless).foregroundStyle(.secondary).padding(10)
                        .help("Paneli kapat")
                }
                .frame(width: 340)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(.background.secondary)
            }
        }
        .onChange(of: selection) { _, new in
            if new.count == 1 { showSuggestions = false }
            showInspector = new.count == 1 || showSuggestions
        }
        .onChange(of: showInspector) { _, open in
            if !open { showSuggestions = false; selection.removeAll() }
        }
        .toolbar {
            ToolbarItemGroup {
                CountryPicker(country: $country).frame(width: 180)
                Button {
                    selection.removeAll(); showSuggestions.toggle(); showInspector = showSuggestions
                } label: { Label("Kelime Önerileri", systemImage: "lightbulb") }
                Button {
                    Task { await refresher.refresh(keywords: app.keywords.filter { $0.country == country }, context: context) }
                } label: { Label("Yenile", systemImage: "arrow.clockwise") }
                .disabled(refresher.isRefreshing)
            }
        }
        .searchable(text: $filter, placement: .toolbar, prompt: "Kelimelerde ara")
    }

    private var header: some View {
        HStack(spacing: 12) {
            AppIcon(url: app.iconURL, size: 44)
                .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name).font(.title2.bold()).lineLimit(1)
                let sf = Storefronts.byCode(country)
                Text("\(sf.flag) \(sf.name) · \(rows.count) / \(app.keywords.count) kelime · \(app.developer)")
                    .font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Picker("", selection: $mode) {
                Text("Kelimeler").tag("keywords")
                Text("Analiz").tag("analysis")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 180)
            Spacer()
            summary
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(palette.wash(0.16))
    }

    private var summary: some View {
        let ranked = rows.compactMap(\.currentRank)
        return HStack(spacing: 18) {
            Stat(title: "Top 10", value: "\(ranked.filter { $0 <= 10 }.count)")
            Stat(title: "Top 50", value: "\(ranked.filter { $0 <= 50 }.count)")
            Stat(title: "Yükselen", value: "\(rows.filter { ($0.change ?? 0) > 0 }.count)", color: .green)
            Stat(title: "Düşen", value: "\(rows.filter { ($0.change ?? 0) < 0 }.count)", color: .red)
        }
    }

    private var addBar: some View {
        HStack {
            Image(systemName: "plus.magnifyingglass").foregroundStyle(.secondary)
            TextField("Kelime ekle (virgülle birden fazla)", text: $newTerms)
                .textFieldStyle(.plain)
                .onSubmit(submitTerms)
            Button("Ekle", action: submitTerms)
                .disabled(newTerms.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 16).padding(.vertical, 9)
        .background(.bar)
    }

    private var table: some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Kelime", value: \.term) { kw in
                HStack(spacing: 4) {
                    Text(kw.term)
                    if let err = kw.lastError {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).help(err)
                    }
                }
            }
            .width(min: 140, ideal: 220)
            TableColumn("Sıra", value: \.rankSort) { kw in
                if kw.latest == nil { Text("…").foregroundStyle(.secondary) }
                else if let r = kw.currentRank { Text("#\(r)").monospacedDigit().bold() }
                else { Text(">\(RankSnapshot.notRanked - 1)").foregroundStyle(.secondary) }
            }
            .width(60)
            TableColumn("Değişim", value: \.changeSort) { kw in ChangeBadge(change: kw.change) }
                .width(70)
            TableColumn("Popülerlik", value: \.popSort) { kw in
                PopularityBar(value: kw.popularity)
            }
            .width(110)
            TableColumn("Zorluk", value: \.diffSort) { kw in
                ScoreBar(value: kw.difficulty, tint: difficultyColor(kw.difficulty))
            }
            .width(110)
            TableColumn("Trend") { kw in Sparkline(keyword: kw).frame(height: 18) }
                .width(90)
        }
        .contextMenu(forSelectionType: PersistentIdentifier.self) { ids in
            Button("Seçilenleri yenile") {
                let kws = app.keywords.filter { ids.contains($0.id) }
                Task { await refresher.refresh(keywords: kws, context: context) }
            }
            Button("Kopyala") {
                let terms = app.keywords.filter { ids.contains($0.id) }.map(\.term).joined(separator: ", ")
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(terms, forType: .string)
            }
            Divider()
            Button("Sil", role: .destructive) {
                for kw in app.keywords where ids.contains(kw.id) { context.delete(kw) }
                selection.subtract(ids)
                try? context.save()
            }
        }
        .onDeleteCommand {
            for kw in app.keywords where selection.contains(kw.id) { context.delete(kw) }
            selection.removeAll()
            try? context.save()
        }
        .overlay {
            if rows.isEmpty && filter.isEmpty {
                ContentUnavailableView("Bu ülkede kelime yok", systemImage: "text.magnifyingglass",
                                       description: Text("Yukarıdan kelime ekle ya da 💡 önerilere bak."))
            }
        }
    }

    private func trackCompetitor(_ info: AppInfo) {
        let descriptor = FetchDescriptor<TrackedApp>(predicate: #Predicate { $0.appId == info.id })
        guard ((try? context.fetchCount(descriptor)) ?? 0) == 0 else { return }
        context.insert(TrackedApp(appId: info.id, name: info.name, developer: info.developer,
                                  iconURL: info.iconURL, isCompetitor: true))
        try? context.save()
    }

    private func submitTerms() {
        addTerms(newTerms.split(whereSeparator: { $0 == "," || $0 == "\n" }).map(String.init))
        newTerms = ""
    }

    private func addTerms(_ terms: [String]) {
        let existing = Set(app.keywords.filter { $0.country == country }.map { $0.term.lowercased() })
        var added: [Keyword] = []
        for raw in terms {
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !t.isEmpty, !existing.contains(t), !added.contains(where: { $0.term == t }) else { continue }
            let kw = Keyword(term: t, country: country, app: app)
            context.insert(kw)
            added.append(kw)
        }
        try? context.save()
        if !added.isEmpty { Task { await refresher.refresh(keywords: added, context: context) } }
    }
}

func difficultyColor(_ v: Int?) -> Color {
    guard let v else { return .gray }
    return v < 35 ? .green : v < 65 ? .orange : .red
}

struct Stat: View {
    let title: String, value: String
    var color: Color = .primary
    var body: some View {
        VStack(spacing: 0) {
            Text(value).font(.title3.bold()).monospacedDigit().foregroundStyle(color)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

struct ChangeBadge: View {
    let change: Int?
    var body: some View {
        if let c = change, c != 0 {
            Label("\(abs(c))", systemImage: c > 0 ? "arrow.up" : "arrow.down")
                .labelStyle(.titleAndIcon)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(c > 0 ? .green : .red)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill((c > 0 ? Color.green : Color.red).opacity(0.14)))
        } else {
            Text(change == nil ? "" : "–").foregroundStyle(.secondary)
        }
    }
}

struct ScoreBar<S: ShapeStyle>: View {
    let value: Int?
    var prefix = ""
    var tint: S
    var body: some View {
        if let v = value {
            HStack(spacing: 6) {
                Text("\(prefix)\(v)").monospacedDigit().frame(width: 32, alignment: .trailing)
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary).frame(width: 50)
                    Capsule().fill(tint).frame(width: max(2, 50 * CGFloat(v) / 100))
                }
                .frame(width: 50, height: 5)
            }
        } else {
            Text("…").foregroundStyle(.secondary)
        }
    }
}

struct Sparkline: View {
    let keyword: Keyword
    var body: some View {
        let ranks = keyword.sortedSnapshots.suffix(14).map { Double($0.rank ?? RankSnapshot.notRanked) }
        Canvas { ctx, size in
            guard ranks.count > 1, let lo = ranks.min(), let hi = ranks.max() else { return }
            let span = max(hi - lo, 1)
            var path = Path()
            for (i, r) in ranks.enumerated() {
                let x = size.width * CGFloat(i) / CGFloat(ranks.count - 1)
                let y = size.height * CGFloat((r - lo) / span)   // lower rank number = higher on chart
                i == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
            }
            let up = (ranks.last ?? 0) <= (ranks.first ?? 0)
            ctx.stroke(path, with: .color(up ? .green : .red), lineWidth: 1.5)
        }
    }
}
