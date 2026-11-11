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
            Text("Multi-country Analysis").font(.title2.bold())
            if let languages {
                HStack(spacing: 6) {
                    Text("App languages:").foregroundStyle(.secondary)
                    ForEach(languages, id: \.self) { l in
                        Text(Locale.current.localizedString(forLanguageCode: l.lowercased()) ?? l)
                            .font(.caption).padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(.quaternary))
                    }
                }
            } else if let error {
                Text(error).foregroundStyle(.red)
            } else {
                ProgressView("Fetching the app's languages…").controlSize(.small)
            }

            List {
                Section {
                    ForEach(matching) { row($0) }
                } header: {
                    HStack {
                        Text("Recommended: stores that search in the app's languages (\(matching.count))")
                        Spacer()
                        Button("All") { selected.formUnion(matching.map(\.code)) }.buttonStyle(.link)
                        Button("None") { selected.subtract(matching.map(\.code)) }.buttonStyle(.link)
                    }
                }
                Section {
                    ForEach(others) { row($0) }
                } header: {
                    Text("Other: no localization in these languages; the app appears in its default language and ranks poorly")
                }
            }
            .listStyle(.inset)

            Toggle("Skip countries analyzed in the last 24 hours", isOn: $skipRecent)
            HStack {
                // ~90 searches per country in quick mode + autocomplete/lookup calls.
                Text("\(toRun.count) countries · about \(max(1, Int((Double(toRun.count) * (90 * spacing + 40) / 60).rounded()))) min (one by one in the background; slow so Apple doesn't block it)")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Start Analysis") { onStart(toRun); dismiss() }
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
                    Text("analyzed \(r.createdAt.formatted(.relative(presentation: .named)))")
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
            ContentUnavailableView("No country analyses yet", systemImage: "globe",
                                   description: Text("Use “Multi-country Analysis…” to analyze every store that matches your app's languages in one go."))
                .frame(maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    SectionBox(title: "Countries", subtitle: "Click a row to open that country's detailed analysis.") {
                        RowHeader(["Country", "Ranked", "Top 10", "Opportunities", "Top opportunities", "Analysis"],
                                  widths: [180, 100, 70, 100, nil, 130])
                        ForEach(results, id: \.country) { r in
                            let sf = Storefronts.byCode(r.country)
                            Button { onOpen(r.country) } label: {
                                HStack(spacing: 8) {
                                    Text("\(sf.flag) \(sf.name)").lineLimit(1).frame(width: 180, alignment: .leading)
                                    Text("\(r.myKeywords.count)").monospacedDigit().frame(width: 100, alignment: .leading)
                                    Text("\(r.myKeywords.filter { ($0.rank ?? 999) <= 10 }.count)").monospacedDigit()
                                        .frame(width: 70, alignment: .leading)
                                    Text("\(r.opportunities.count)").monospacedDigit().foregroundStyle(.green)
                                        .frame(width: 100, alignment: .leading)
                                    Text(r.opportunities.prefix(3).map(\.term).joined(separator: ", "))
                                        .lineLimit(1).foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text(r.createdAt.formatted(.relative(presentation: .named)))
                                        .font(.caption).foregroundStyle(.secondary)
                                        .frame(width: 130, alignment: .trailing)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, 4)
                            Divider()
                        }
                    }

                    SectionBox(title: "Best opportunities across countries",
                               subtitle: "Opportunity keywords that stand out in several stores come first.") {
                        RowHeader(["Keyword", "Best score", "Popularity", "Countries"], widths: [nil, 80, 90, 260])
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
