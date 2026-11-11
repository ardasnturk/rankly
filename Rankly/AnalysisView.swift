import SwiftUI
import SwiftData

struct AnalysisView: View {
    @EnvironmentObject private var center: AnalysisCenter
    @Environment(\.appPalette) private var palette
    @Query private var trackedApps: [TrackedApp]
    let app: TrackedApp
    @Binding var country: String
    var onAddKeywords: ([String]) -> Void
    var onTrackCompetitor: (AppInfo) -> Void

    @State private var copied = false
    @State private var showAllOpps = false
    @State private var scope = "country"          // "country" | "overview"
    @State private var showCountryPicker = false

    private var result: AnalysisResult? { center.result(appId: app.appId, country: country) }
    private var state: AnalysisCenter.RunState? { center.state(appId: app.appId, country: country) }
    private var trackedTerms: Set<String> {
        Set(app.keywords.filter { $0.country == country }.map(\.term))
    }

    var body: some View {
        VStack(spacing: 0) {
            if let b = center.batch(appId: app.appId) { batchBar(b); Divider() }
            controlBar
            Divider()
            if scope == "overview" {
                CountriesOverview(results: center.allResults(appId: app.appId)) { code in
                    country = code
                    scope = "country"
                }
            } else if let result {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        summary(result)
                        keywordFieldBox(result)
                        opportunities(result)
                        competitors(result)
                        myKeywords(result)
                        if !result.missedTitleTerms.isEmpty { missed(result) }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if state == nil {
                VStack(spacing: 12) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(palette.fromIcon ? palette.primary : Color.accentColor)
                    Text("No analysis yet").font(.title3.bold())
                    Text("Candidate keywords are extracted from the app's name, subtitle and description and searched on the App Store to find the keywords you rank for, your competitors, and opportunity keywords your competitors rank for but you don't. Takes about 1–2 minutes.")
                        .font(.callout).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).frame(maxWidth: 420)
                    Button("Start Analysis", action: start)
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        .tint(palette.fromIcon ? palette.primary : Color.accentColor)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .sheet(isPresented: $showCountryPicker) {
            CountryBatchSheet(appId: app.appId, existing: center.allResults(appId: app.appId)) { codes in
                center.startBatch(appId: app.appId, countries: codes,
                                  pinnedCompetitors: trackedApps.filter(\.isCompetitor).map(\.appId))
                scope = "overview"
            }
        }
    }

    // MARK: Sections

    private func batchBar(_ b: AnalysisCenter.BatchState) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "globe").foregroundStyle(.tint)
            if b.finished, let until = b.blockedUntil {
                Image(systemName: "hand.raised.fill").foregroundStyle(.orange)
                Text("Apple temporarily blocked search. \(b.countries.count - b.failed.count) countries done, \(b.failed.count) waiting. Continue after \(until.formatted(date: .omitted, time: .shortened)).")
                    .font(.callout).lineLimit(2)
                Spacer()
                Button("Continue with Remaining") {
                    center.dismissBatch(appId: app.appId)
                    center.startBatch(appId: app.appId, countries: b.failed,
                                      pinnedCompetitors: trackedApps.filter(\.isCompetitor).map(\.appId))
                }
                .disabled(until > Date())
                Button("Close") { center.dismissBatch(appId: app.appId) }
            } else if b.finished {
                HStack(spacing: 4) {
                    Text("Multi-country analysis finished: \(b.countries.count - b.failed.count)/\(b.countries.count) countries")
                    if !b.failed.isEmpty {
                        Text("· failed: \(b.failed.map { Storefronts.byCode($0).flag }.joined(separator: " "))")
                    }
                }
                    .font(.callout)
                    .help(b.reasons.map { "\(Storefronts.byCode($0.key).name): \($0.value)" }.joined(separator: "\n"))
                Spacer()
                if !b.failed.isEmpty {
                    Button("Retry Failed") {
                        center.dismissBatch(appId: app.appId)
                        center.startBatch(appId: app.appId, countries: b.failed,
                                          pinnedCompetitors: trackedApps.filter(\.isCompetitor).map(\.appId))
                    }
                }
                Button("Close") { center.dismissBatch(appId: app.appId) }
            } else {
                ProgressView(value: b.fraction).frame(width: 120)
                if let c = b.current {
                    let sf = Storefronts.byCode(c)
                    Text("Country \(b.index + 1)/\(b.countries.count) · \(sf.flag) \(sf.name)")
                        .font(.callout).monospacedDigit()
                    if let st = center.state(appId: app.appId, country: c) {
                        Text("· \(st.phase)").font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
                Button("Stop") { center.cancelBatch(appId: app.appId) }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(Color.blue.opacity(0.08))
    }

    private var controlBar: some View {
        HStack(spacing: 10) {
            Picker("", selection: $scope) {
                Text("\(Storefronts.byCode(country).flag) This Country").tag("country")
                Text("All Countries (\(center.allResults(appId: app.appId).count))").tag("overview")
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            Button { showCountryPicker = true } label: { Label("Multi-country Analysis…", systemImage: "globe") }
                .disabled(center.batch(appId: app.appId).map { !$0.finished } ?? false)
            if scope == "overview" {
                Spacer()
            } else if let s = state {
                if let err = s.error {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(err).lineLimit(1)
                    Spacer()
                    Button("OK") { center.dismissError(appId: app.appId, country: country) }
                    Button("Try Again", action: start)
                } else {
                    ProgressView(value: s.fraction).frame(width: 160)
                    Text(s.phase).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Button("Cancel") { center.cancel(appId: app.appId, country: country) }
                }
            } else {
                if let r = result {
                    Text("Last analysis: \(r.createdAt.formatted(.relative(presentation: .named))) · \(r.searchedTerms) keywords searched")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                if result != nil { Button("Re-analyze", action: start) }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 9)
        .background(.bar)
    }

    private func summary(_ r: AnalysisResult) -> some View {
        HStack(spacing: 28) {
            Stat(title: "Ranked", value: "\(r.myKeywords.count)")
            Stat(title: "Top 10", value: "\(r.myKeywords.filter { ($0.rank ?? 999) <= 10 }.count)")
            Stat(title: "Competitors", value: "\(r.competitors.count)")
            Stat(title: "Opportunities", value: "\(r.opportunities.count)", color: .green)
            Spacer()
            if let sub = r.app.subtitle {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Subtitle").font(.caption2).foregroundStyle(.secondary)
                    Text(sub).font(.callout)
                }
            }
        }
    }

    private func keywordFieldBox(_ r: AnalysisResult) -> some View {
        SectionBox(title: "Suggested keyword field",
                   subtitle: "For the 100-character field in App Store Connect. Words already in the name and subtitle are not repeated.") {
            HStack(alignment: .top) {
                Text(r.keywordField.isEmpty ? String(localized: "No suggestion") : r.keywordField)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 6) {
                    Text("\(r.keywordField.count)/100").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    Button(copied ? String(localized: "Copied") : String(localized: "Copy")) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(r.keywordField, forType: .string)
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                    }
                }
            }
        }
    }

    private func opportunities(_ r: AnalysisResult) -> some View {
        let comps = Dictionary(r.competitors.map { ($0.app.id, $0.app) }, uniquingKeysWith: { a, _ in a })
        return SectionBox(title: "Opportunity keywords",
                          subtitle: "Keywords where competitors rank in the top 30 but you don't. Score = popularity, difficulty and number of competitors.") {
            if r.opportunities.isEmpty {
                Text("No clear opportunities found.").foregroundStyle(.secondary)
            } else {
                RowHeader(["Keyword", "Score", "Popularity", "Difficulty", "You", "Competitors", ""],
                          widths: [nil, 50, 90, 90, 50, 150, 70])
                ForEach(showAllOpps ? r.opportunities : Array(r.opportunities.prefix(15))) { o in
                    HStack(spacing: 8) {
                        Text(o.term).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                        Text(String(format: "%.0f", o.score)).bold().monospacedDigit().frame(width: 50, alignment: .leading)
                        PopularityBar(value: o.popularity).frame(width: 90, alignment: .leading)
                        ScoreBar(value: o.difficulty, tint: difficultyColor(o.difficulty)).frame(width: 90, alignment: .leading)
                        Text(o.myRank.map { "#\($0)" } ?? "—").monospacedDigit().foregroundStyle(.secondary)
                            .frame(width: 50, alignment: .leading)
                        HStack(spacing: 4) {
                            ForEach(o.competitorRanks.sorted { $0.value < $1.value }.prefix(4), id: \.key) { id, rank in
                                HStack(spacing: 2) {
                                    AppIcon(url: comps[id]?.iconURL, size: 16)
                                    Text("\(rank)").font(.caption).monospacedDigit()
                                }
                                .help(comps[id]?.name ?? "")
                            }
                        }
                        .frame(width: 150, alignment: .leading)
                        addButton(o.term).frame(width: 70, alignment: .trailing)
                    }
                    .padding(.vertical, 3)
                    Divider()
                }
                if r.opportunities.count > 15 {
                    Button(showAllOpps ? String(localized: "Show Less") : String(localized: "Show All (\(r.opportunities.count))")) {
                        showAllOpps.toggle()
                    }
                    .buttonStyle(.link)
                }
            }
        }
    }

    private func competitors(_ r: AnalysisResult) -> some View {
        SectionBox(title: "Competitors",
                   subtitle: "Apps in a similar category that most often rank near the top for your keywords.") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12)], spacing: 12) {
                ForEach(r.competitors) { c in
                    let tracked = trackedApps.contains { $0.appId == c.app.id }
                    HStack(alignment: .top, spacing: 10) {
                        AppIcon(url: c.app.iconURL, size: 40)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(c.app.name).bold().lineLimit(1)
                            Text(c.app.subtitle ?? c.app.developer).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            HStack(spacing: 8) {
                                Text("★ \(c.app.rating, specifier: "%.1f") · \(c.app.ratingCount.formatted())")
                                if c.sameGenre { Text("Same category").foregroundStyle(.green) }
                            }
                            .font(.caption2).foregroundStyle(.secondary)
                            Text("\(c.sharedKeywords) shared keywords · top 50 for \(c.rankedKeywords) keywords")
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if tracked {
                            Text("Tracking").font(.caption).foregroundStyle(.secondary)
                        } else {
                            Button("Track") { onTrackCompetitor(c.app) }.controlSize(.small)
                        }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)))
                }
            }
        }
    }

    private func myKeywords(_ r: AnalysisResult) -> some View {
        SectionBox(title: "Keywords you rank for",
                   subtitle: "Searched candidates where the app appears in the top 250.") {
            RowHeader(["Keyword", "Rank", "Popularity", "Difficulty", "Source", ""], widths: [nil, 50, 90, 90, 80, 70])
            ForEach(r.myKeywords) { k in
                HStack(spacing: 8) {
                    Text(k.term).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    Text(k.rank.map { "#\($0)" } ?? "—").bold().monospacedDigit().frame(width: 50, alignment: .leading)
                    PopularityBar(value: k.popularity).frame(width: 90, alignment: .leading)
                    ScoreBar(value: k.difficulty, tint: difficultyColor(k.difficulty)).frame(width: 90, alignment: .leading)
                    Text(KeywordSource.label(k.source)).font(.caption).foregroundStyle(.secondary).frame(width: 80, alignment: .leading)
                    addButton(k.term).frame(width: 70, alignment: .trailing)
                }
                .padding(.vertical, 3)
                Divider()
            }
        }
    }

    private func missed(_ r: AnalysisResult) -> some View {
        SectionBox(title: "Name/subtitle keywords you don't rank for",
                   subtitle: "These words use valuable space but you don't appear in the top 250 for them; consider replacing them.") {
            ForEach(r.missedTitleTerms) { k in
                HStack {
                    Text(k.term).frame(maxWidth: .infinity, alignment: .leading)
                    Text(KeywordSource.label(k.source)).font(.caption).foregroundStyle(.secondary).frame(width: 80, alignment: .leading)
                    PopularityBar(value: k.popularity).frame(width: 90, alignment: .leading)
                    ScoreBar(value: k.difficulty, tint: difficultyColor(k.difficulty)).frame(width: 90, alignment: .leading)
                }
                .padding(.vertical, 3)
            }
        }
    }

    @ViewBuilder
    private func addButton(_ term: String) -> some View {
        if trackedTerms.contains(term) {
            Text("Tracking").font(.caption).foregroundStyle(.secondary)
        } else {
            Button("Track") { onAddKeywords([term]) }.controlSize(.small)
        }
    }

    private func start() {
        let pinned = trackedApps.filter(\.isCompetitor).map(\.appId)
        center.start(appId: app.appId, country: country, pinnedCompetitors: pinned)
    }
}

struct SectionBox<Content: View>: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            }
            content
        }
    }
}

struct RowHeader: View {
    let titles: [LocalizedStringKey]
    let widths: [CGFloat?]
    init(_ titles: [LocalizedStringKey], widths: [CGFloat?]) { self.titles = titles; self.widths = widths }
    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(titles.enumerated()), id: \.offset) { i, t in
                if let w = widths[i] {
                    Text(t).frame(width: w, alignment: i == titles.count - 1 ? .trailing : .leading)
                } else {
                    Text(t).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .font(.caption).foregroundStyle(.secondary)
    }
}
