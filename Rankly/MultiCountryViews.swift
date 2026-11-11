import SwiftUI

/// Lets the user pick which storefronts to analyse; pre-selects the ones matching the app's languages.
struct CountryBatchSheet: View {
    @Environment(\.dismiss) private var dismiss
    let appId: String
    let existing: [AnalysisResult]
    var onStart: ([String]) -> Void

    @State private var languages: [String]? = nil
    @State private var selected = Set<String>()
    @State private var skipRecent = true
    @State private var error: String?
    @State private var spacing: TimeInterval = 1.5

    private var matching: [Storefront] { Storefronts.matching(appLanguages: languages ?? []) }
    private var others: [Storefront] {
        let m = Set(matching.map(\.code))
        return Storefronts.all.filter { !m.contains($0.code) }
    }
    private var recent: Set<String> {
        Set(existing.filter { Date().timeIntervalSince($0.createdAt) < 86400 }.map(\.country))
    }
    private var toRun: [String] {
        Storefronts.all.map(\.code).filter { selected.contains($0) && !(skipRecent && recent.contains($0)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Çok Ülkeli Analiz").font(.title2.bold())
            if let languages {
                HStack(spacing: 6) {
                    Text("Uygulamanın dilleri:").foregroundStyle(.secondary)
                    ForEach(languages, id: \.self) { l in
                        Text(Locale.current.localizedString(forLanguageCode: l.lowercased()) ?? l)
                            .font(.caption).padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(.quaternary))
                    }
                }
            } else if let error {
                Text(error).foregroundStyle(.red)
            } else {
                ProgressView("Uygulamanın dilleri alınıyor…").controlSize(.small)
            }

            List {
                Section {
                    ForEach(matching) { row($0) }
                } header: {
                    HStack {
                        Text("Önerilen: uygulamanın dilinde arama yapılan mağazalar (\(matching.count))")
                        Spacer()
                        Button("Hepsi") { selected.formUnion(matching.map(\.code)) }.buttonStyle(.link)
                        Button("Hiçbiri") { selected.subtract(matching.map(\.code)) }.buttonStyle(.link)
                    }
                }
                Section {
                    ForEach(others) { row($0) }
                } header: {
                    Text("Diğer: bu dillerde yerelleştirme yok; uygulama varsayılan dilinde görünür, sıralama zayıf olur")
                }
            }
            .listStyle(.inset)

            Toggle("Son 24 saatte analiz edilen ülkeleri atla", isOn: $skipRecent)
            HStack {
                // ~90 searches per country in quick mode + autocomplete/lookup calls.
                Text("\(toRun.count) ülke · tahmini ~\(max(1, Int((Double(toRun.count) * (90 * spacing + 40) / 60).rounded()))) dk (sırayla, arka planda; Apple engellememesi için yavaş)")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Vazgeç") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Analizi Başlat") { onStart(toRun); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(toRun.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 620, height: 620)
        .task {
            spacing = await AppStoreClient.shared.currentSearchSpacing()
            do {
                let info = try await AppStoreClient.shared.lookup(ids: [appId], country: "us").first
                languages = info?.languages ?? ["EN"]
                selected = Set(matching.map(\.code))
            } catch {
                self.error = error.localizedDescription
                languages = ["EN"]
                selected = Set(matching.map(\.code))
            }
        }
    }

    private func row(_ sf: Storefront) -> some View {
        Toggle(isOn: Binding(get: { selected.contains(sf.code) },
                             set: { if $0 { selected.insert(sf.code) } else { selected.remove(sf.code) } })) {
            HStack {
                Text("\(sf.flag) \(sf.name)")
                Text(sf.languages.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if let r = existing.first(where: { $0.country == sf.code }) {
                    Text("analiz: \(r.createdAt.formatted(.relative(presentation: .named)))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// One row per analysed country + the best opportunities across all of them.
struct CountriesOverview: View {
    let results: [AnalysisResult]
    var onOpen: (String) -> Void

    private struct CrossOpp: Identifiable {
        var id: String { term }
        let term: String
        var countries: [String]
        var bestScore: Double
        var popularity: Int?
    }

    private var crossOpps: [CrossOpp] {
        var map: [String: CrossOpp] = [:]
        for r in results {
            for o in r.opportunities {
                var c = map[o.term] ?? CrossOpp(term: o.term, countries: [], bestScore: 0, popularity: o.popularity)
                c.countries.append(r.country)
                if o.score > c.bestScore { c.bestScore = o.score; c.popularity = o.popularity }
                map[o.term] = c
            }
        }
        return map.values.sorted {
            ($0.bestScore * (1 + 0.2 * Double($0.countries.count - 1))) > ($1.bestScore * (1 + 0.2 * Double($1.countries.count - 1)))
        }
    }

    var body: some View {
        if results.isEmpty {
            ContentUnavailableView("Henüz ülke analizi yok", systemImage: "globe",
                                   description: Text("“Çok ülkeli analiz…” ile uygulamanın dillerine uygun mağazaları tek seferde analiz et."))
                .frame(maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    SectionBox(title: "Ülkeler", subtitle: "Bir satıra tıklayınca o ülkenin ayrıntılı analizi açılır.") {
                        RowHeader(["Ülke", "Sıralandığın", "Top 10", "Fırsat", "En iyi fırsatlar", "Analiz"],
                                  widths: [180, 80, 60, 60, nil, 110])
                        ForEach(results, id: \.country) { r in
                            let sf = Storefronts.byCode(r.country)
                            Button { onOpen(r.country) } label: {
                                HStack(spacing: 8) {
                                    Text("\(sf.flag) \(sf.name)").lineLimit(1).frame(width: 180, alignment: .leading)
                                    Text("\(r.myKeywords.count)").monospacedDigit().frame(width: 80, alignment: .leading)
                                    Text("\(r.myKeywords.filter { ($0.rank ?? 999) <= 10 }.count)").monospacedDigit()
                                        .frame(width: 60, alignment: .leading)
                                    Text("\(r.opportunities.count)").monospacedDigit().foregroundStyle(.green)
                                        .frame(width: 60, alignment: .leading)
                                    Text(r.opportunities.prefix(3).map(\.term).joined(separator: ", "))
                                        .lineLimit(1).foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text(r.createdAt.formatted(.relative(presentation: .named)))
                                        .font(.caption).foregroundStyle(.secondary)
                                        .frame(width: 110, alignment: .trailing)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, 4)
                            Divider()
                        }
                    }

                    SectionBox(title: "Ülkeler arası en iyi fırsatlar",
                               subtitle: "Birden fazla mağazada öne çıkan fırsat kelimeler üstte.") {
                        RowHeader(["Kelime", "En iyi puan", "Popülerlik", "Ülkeler"], widths: [nil, 80, 90, 260])
                        ForEach(crossOpps.prefix(25)) { o in
                            HStack(spacing: 8) {
                                Text(o.term).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                                Text(String(format: "%.0f", o.bestScore)).bold().monospacedDigit()
                                    .frame(width: 80, alignment: .leading)
                                PopularityBar(value: o.popularity).frame(width: 90, alignment: .leading)
                                Text(o.countries.map { Storefronts.byCode($0).flag }.joined(separator: " "))
                                    .lineLimit(1).frame(width: 260, alignment: .leading)
                            }
                            .padding(.vertical, 3)
                            Divider()
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
