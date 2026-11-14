import SwiftUI

/// Every tracked keyword of an app × every country it is tracked in, with the current search rank per cell.
/// Clicking a rank opens that keyword; clicking + starts tracking the term in that country too.
struct CountryMatrixView: View {
    @Environment(\.appPalette) private var palette
    let app: TrackedApp
    var filter: String = ""
    var onOpen: (Keyword) -> Void
    var onTrack: (_ term: String, _ country: String) -> Void

    private let termWidth: CGFloat = 210
    private let cellWidth: CGFloat = 76

    var body: some View {
        let byCountry = Dictionary(grouping: app.keywords, by: \.country)
        let countries = byCountry.keys.sorted {
            (byCountry[$0]!.count, Storefronts.byCode($1).name) > (byCountry[$1]!.count, Storefronts.byCode($0).name)
        }
        let byTerm = Dictionary(grouping: app.keywords) { $0.term.lowercased() }
        let terms = byTerm.keys
            .filter { filter.isEmpty || $0.localizedCaseInsensitiveContains(filter) }
            .sorted { a, b in
                let ra = byTerm[a]!.map(\.rankSort).min() ?? 999, rb = byTerm[b]!.map(\.rankSort).min() ?? 999
                return (ra, a) < (rb, b)
            }

        if app.keywords.isEmpty {
            ContentUnavailableView("No keywords yet", systemImage: "globe",
                                   description: Text("Track keywords in one or more countries to compare them here."))
        } else {
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        ForEach(terms, id: \.self) { term in
                            let cells = Dictionary((byTerm[term] ?? []).map { ($0.country, $0) }) { a, _ in a }
                            HStack(spacing: 0) {
                                Text(term).lineLimit(1).frame(width: termWidth, alignment: .leading).padding(.leading, 16)
                                ForEach(countries, id: \.self) { c in
                                    cell(cells[c], term: term, country: c).frame(width: cellWidth)
                                }
                            }
                            .frame(height: 30)
                            Divider()
                        }
                    } header: {
                        HStack(spacing: 0) {
                            Text("\(terms.count) keywords · \(countries.count) countries")
                                .font(.caption).foregroundStyle(.secondary)
                                .frame(width: termWidth, alignment: .leading).padding(.leading, 16)
                            ForEach(countries, id: \.self) { c in
                                let sf = Storefronts.byCode(c)
                                VStack(spacing: 0) {
                                    Text(sf.flag).font(.title3)
                                    Text(c.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                                }
                                .frame(width: cellWidth)
                                .help(sf.name)
                            }
                        }
                        .padding(.vertical, 6)
                        .background(.bar)
                    }
                }
                .padding(.bottom, 12)
            }
        }
    }

    @ViewBuilder
    private func cell(_ kw: Keyword?, term: String, country: String) -> some View {
        if let kw {
            Button { onOpen(kw) } label: {
                HStack(spacing: 2) {
                    if kw.latest == nil {
                        Text("…").foregroundStyle(.secondary)
                    } else if let r = kw.currentRank {
                        Text("#\(r)").monospacedDigit().fontWeight(r <= 10 ? .bold : .regular)
                        if let c = kw.change, c != 0 {
                            Image(systemName: c > 0 ? "arrow.up" : "arrow.down")
                                .font(.system(size: 8, weight: .bold)).foregroundStyle(c > 0 ? .green : .red)
                        }
                    } else {
                        Text("—").foregroundStyle(.secondary)
                    }
                }
                .frame(width: cellWidth - 8, height: 24)
                .background(RoundedRectangle(cornerRadius: 6).fill(tint(kw.currentRank)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(Text("\(term) · \(Storefronts.byCode(country).name)"))
        } else {
            Button { onTrack(term, country) } label: {
                Image(systemName: "plus").font(.caption).foregroundStyle(.tertiary)
                    .frame(width: cellWidth - 8, height: 24).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(Text("Track “\(term)” in \(Storefronts.byCode(country).name)"))
        }
    }

    private func tint(_ rank: Int?) -> Color {
        guard let rank else { return .clear }
        if rank <= 10 { return .green.opacity(0.18) }
        if rank <= 50 { return palette.primary.opacity(0.15) }
        return .secondary.opacity(0.08)
    }
}
