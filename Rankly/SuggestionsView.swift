import SwiftUI

struct Suggestion: Identifiable {
    var id: String { term }
    let term: String
    var popularity: Int?
    var difficulty: Int?
}

struct SuggestionsView: View {
    @Environment(\.appPalette) private var palette
    let app: TrackedApp
    let country: String
    var onAdd: ([String]) -> Void

    @State private var seed = ""
    @State private var items: [Suggestion] = []
    @State private var loading = false
    @State private var added = Set<String>()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Keyword Suggestions").font(.title3.bold())
            Text("Related searches from App Store autocomplete.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                TextField("Seed keyword", text: $seed).textFieldStyle(.roundedBorder).onSubmit(load)
                Button("Find", action: load)
            }
            if loading { ProgressView().frame(maxWidth: .infinity) }
            List(items) { s in
                HStack {
                    Text(s.term).lineLimit(1)
                    Spacer()
                    Text(s.popularity.map { "~\($0)" } ?? "…").monospacedDigit().foregroundStyle(palette.primary)
                        .frame(width: 34).help("Popularity (estimated)")
                    Text(s.difficulty.map(String.init) ?? "…").monospacedDigit()
                        .foregroundStyle(difficultyColor(s.difficulty)).frame(width: 28).help("Difficulty")
                    let isAdded = added.contains(s.term) || existing.contains(s.term)
                    Button { onAdd([s.term]); added.insert(s.term) } label: {
                        Image(systemName: isAdded ? "checkmark" : "plus")
                    }
                    .buttonStyle(.borderless)
                    .disabled(isAdded)
                }
            }
            .listStyle(.inset)
        }
        .padding(16)
        .onAppear {
            if seed.isEmpty {
                seed = app.keywords.first(where: { $0.country == country })?.term
                    ?? app.name.split(separator: ":").first.map { String($0).lowercased() } ?? ""
                load()
            }
        }
    }

    private var existing: Set<String> {
        Set(app.keywords.filter { $0.country == country }.map(\.term))
    }

    private func load() {
        let base = seed.trimmingCharacters(in: .whitespaces).lowercased()
        guard !base.isEmpty else { return }
        loading = true
        items = []
        Task {
            let client = AppStoreClient.shared
            var terms: [String] = []
            for q in [base, base + " "] + base.split(separator: " ").map(String.init) {
                for t in (try? await client.hints(for: q, country: country)) ?? [] {
                    let lt = t.lowercased()
                    if !terms.contains(lt) { terms.append(lt) }
                }
            }
            items = terms.prefix(30).map { Suggestion(term: $0) }
            loading = false
            // Fill scores progressively.
            for i in items.indices {
                guard i < items.count else { break }
                let term = items[i].term
                async let pop = Scoring.estimatePopularity(term: term, country: country, client: client)
                let ids = (try? await client.searchRanking(term: term, country: country)) ?? []
                let top = (try? await client.lookup(ids: Array(ids.prefix(10)), country: country)) ?? []
                let diff = Scoring.difficulty(term: term, topApps: top)
                let p = await pop
                if i < items.count, items[i].term == term {
                    items[i].popularity = p
                    items[i].difficulty = diff
                }
            }
        }
    }
}
