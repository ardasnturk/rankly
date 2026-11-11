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
                ContentUnavailableView {
                    Label("Henüz analiz yok", systemImage: "wand.and.stars")
                } description: {
                    Text("Uygulamanın adı, alt başlığı ve açıklamasından aday kelimeler çıkarılır, App Store'da aranır; sıralandığın kelimeler, rakiplerin ve rakiplerin sıralanıp senin sıralanmadığın fırsat kelimeler bulunur. Yaklaşık 1–2 dakika sürer.")
                } actions: {
                    Button("Analizi Başlat", action: start).buttonStyle(.borderedProminent)
                        .tint(palette.fromIcon ? palette.primary : nil)
                }
                .frame(maxHeight: .infinity)
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
                Text("Apple aramayı geçici olarak engelledi. \(b.countries.count - b.failed.count) ülke bitti, \(b.failed.count) ülke bekliyor. \(until.formatted(date: .omitted, time: .shortened)) sonrasında devam et.")
                    .font(.callout).lineLimit(2)
                Spacer()
                Button("Kalanlarla devam et") {
                    center.dismissBatch(appId: app.appId)
                    center.startBatch(appId: app.appId, countries: b.failed,
                                      pinnedCompetitors: trackedApps.filter(\.isCompetitor).map(\.appId))
                }
                .disabled(until > Date())
                Button("Kapat") { center.dismissBatch(appId: app.appId) }
            } else if b.finished {
                Text("Çok ülkeli analiz bitti: \(b.countries.count - b.failed.count)/\(b.countries.count) ülke"
                     + (b.failed.isEmpty ? "" : " · başarısız: " + b.failed.map { Storefronts.byCode($0).flag }.joined(separator: " ")))
                    .font(.callout)
                    .help(b.reasons.map { "\(Storefronts.byCode($0.key).name): \($0.value)" }.joined(separator: "\n"))
                Spacer()
                if !b.failed.isEmpty {
                    Button("Başarısızları tekrar dene") {
                        center.dismissBatch(appId: app.appId)
                        center.startBatch(appId: app.appId, countries: b.failed,
                                          pinnedCompetitors: trackedApps.filter(\.isCompetitor).map(\.appId))
                    }
                }
                Button("Kapat") { center.dismissBatch(appId: app.appId) }
            } else {
                ProgressView(value: b.fraction).frame(width: 120)
                if let c = b.current {
                    let sf = Storefronts.byCode(c)
                    Text("Ülke \(b.index + 1)/\(b.countries.count) · \(sf.flag) \(sf.name)")
                        .font(.callout).monospacedDigit()
                    if let st = center.state(appId: app.appId, country: c) {
                        Text("· \(st.phase)").font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
                Button("Durdur") { center.cancelBatch(appId: app.appId) }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(Color.blue.opacity(0.08))
    }

    private var controlBar: some View {
        HStack(spacing: 10) {
            Picker("", selection: $scope) {
                Text("\(Storefronts.byCode(country).flag) Bu ülke").tag("country")
                Text("Tüm ülkeler (\(center.allResults(appId: app.appId).count))").tag("overview")
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            Button { showCountryPicker = true } label: { Label("Çok ülkeli analiz…", systemImage: "globe") }
                .disabled(center.batch(appId: app.appId).map { !$0.finished } ?? false)
            if scope == "overview" {
                Spacer()
            } else if let s = state {
                if let err = s.error {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(err).lineLimit(1)
                    Spacer()
                    Button("Tamam") { center.dismissError(appId: app.appId, country: country) }
                    Button("Tekrar dene", action: start)
                } else {
                    ProgressView(value: s.fraction).frame(width: 160)
                    Text(s.phase).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Button("İptal") { center.cancel(appId: app.appId, country: country) }
                }
            } else {
                if let r = result {
                    Text("Son analiz: \(r.createdAt.formatted(.relative(presentation: .named))) · \(r.searchedTerms) kelime arandı")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                if result != nil { Button("Yeniden Analiz Et", action: start) }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 9)
        .background(.bar)
    }

    private func summary(_ r: AnalysisResult) -> some View {
        HStack(spacing: 28) {
            Stat(title: "Sıralandığın", value: "\(r.myKeywords.count)")
            Stat(title: "Top 10", value: "\(r.myKeywords.filter { ($0.rank ?? 999) <= 10 }.count)")
            Stat(title: "Rakip", value: "\(r.competitors.count)")
            Stat(title: "Fırsat", value: "\(r.opportunities.count)", color: .green)
            Spacer()
            if let sub = r.app.subtitle {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Alt başlık").font(.caption2).foregroundStyle(.secondary)
                    Text(sub).font(.callout)
                }
            }
        }
    }

    private func keywordFieldBox(_ r: AnalysisResult) -> some View {
        SectionBox(title: "Keyword alanı önerisi",
                   subtitle: "App Store Connect'teki 100 karakterlik alan için. Ad ve alt başlıktaki kelimeler tekrar edilmedi.") {
            HStack(alignment: .top) {
                Text(r.keywordField.isEmpty ? "Öneri çıkmadı" : r.keywordField)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 6) {
                    Text("\(r.keywordField.count)/100").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    Button(copied ? "Kopyalandı" : "Kopyala") {
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
        return SectionBox(title: "Fırsat kelimeler",
                          subtitle: "Rakiplerin ilk 30'da olduğu ama senin olmadığın kelimeler. Puan = popülerlik, zorluk ve rakip sayısı.") {
            if r.opportunities.isEmpty {
                Text("Belirgin bir fırsat bulunamadı.").foregroundStyle(.secondary)
            } else {
                RowHeader(["Kelime", "Puan", "Popülerlik", "Zorluk", "Sen", "Rakipler", ""],
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
                    Button(showAllOpps ? "Daha az göster" : "Tümünü göster (\(r.opportunities.count))") {
                        showAllOpps.toggle()
                    }
                    .buttonStyle(.link)
                }
            }
        }
    }

    private func competitors(_ r: AnalysisResult) -> some View {
        SectionBox(title: "Rakipler",
                   subtitle: "Senin kelimelerinde en sık üst sıralarda çıkan, benzer kategorideki uygulamalar.") {
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
                                if c.sameGenre { Text("Aynı kategori").foregroundStyle(.green) }
                            }
                            .font(.caption2).foregroundStyle(.secondary)
                            Text("\(c.sharedKeywords) ortak kelime · \(c.rankedKeywords) kelimede ilk 50")
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if tracked {
                            Text("Takipte").font(.caption).foregroundStyle(.secondary)
                        } else {
                            Button("Takip et") { onTrackCompetitor(c.app) }.controlSize(.small)
                        }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)))
                }
            }
        }
    }

    private func myKeywords(_ r: AnalysisResult) -> some View {
        SectionBox(title: "Sıralandığın kelimeler",
                   subtitle: "Aranan adaylardan uygulamanın ilk 250'de çıktığı kelimeler.") {
            RowHeader(["Kelime", "Sıra", "Popülerlik", "Zorluk", "Kaynak", ""], widths: [nil, 50, 90, 90, 80, 70])
            ForEach(r.myKeywords) { k in
                HStack(spacing: 8) {
                    Text(k.term).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    Text(k.rank.map { "#\($0)" } ?? "—").bold().monospacedDigit().frame(width: 50, alignment: .leading)
                    PopularityBar(value: k.popularity).frame(width: 90, alignment: .leading)
                    ScoreBar(value: k.difficulty, tint: difficultyColor(k.difficulty)).frame(width: 90, alignment: .leading)
                    Text(k.source).font(.caption).foregroundStyle(.secondary).frame(width: 80, alignment: .leading)
                    addButton(k.term).frame(width: 70, alignment: .trailing)
                }
                .padding(.vertical, 3)
                Divider()
            }
        }
    }

    private func missed(_ r: AnalysisResult) -> some View {
        SectionBox(title: "Ad/alt başlıkta olup sıralanmadığın kelimeler",
                   subtitle: "Bu kelimeler değerli alanı kullanıyor ama ilk 250'de çıkmıyorsun; değiştirmeyi düşünebilirsin.") {
            ForEach(r.missedTitleTerms) { k in
                HStack {
                    Text(k.term).frame(maxWidth: .infinity, alignment: .leading)
                    Text(k.source).font(.caption).foregroundStyle(.secondary).frame(width: 80, alignment: .leading)
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
            Text("Takipte").font(.caption).foregroundStyle(.secondary)
        } else {
            Button("Takip et") { onAddKeywords([term]) }.controlSize(.small)
        }
    }

    private func start() {
        let pinned = trackedApps.filter(\.isCompetitor).map(\.appId)
        center.start(appId: app.appId, country: country, pinnedCompetitors: pinned)
    }
}

struct SectionBox<Content: View>: View {
    let title: String
    var subtitle: String?
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
    let titles: [String]
    let widths: [CGFloat?]
    init(_ titles: [String], widths: [CGFloat?]) { self.titles = titles; self.widths = widths }
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
