import Foundation

// MARK: - Result types

struct KeywordStat: Codable, Identifiable, Hashable {
    var id: String { term }
    let term: String
    let source: String
    let rank: Int?
    var popularity: Int?
    var difficulty: Int?
}

struct CompetitorStat: Codable, Identifiable, Hashable {
    var id: String { app.id }
    let app: AppInfo
    let sameGenre: Bool
    let sharedKeywords: Int      // terms where both rank in top 50
    let rankedKeywords: Int      // terms where this competitor ranks in top 50
    let overlapScore: Double
}

struct Opportunity: Codable, Identifiable, Hashable {
    var id: String { term }
    let term: String
    let myRank: Int?
    let competitorRanks: [String: Int]   // competitor appId -> rank
    var popularity: Int?
    var difficulty: Int?
    var score: Double
}

struct AnalysisResult: Codable {
    let appId: String
    let country: String
    let createdAt: Date
    let app: AppInfo
    let searchedTerms: Int
    let myKeywords: [KeywordStat]          // terms the app ranks for
    let missedTitleTerms: [KeywordStat]    // name/subtitle terms it does NOT rank for
    let competitors: [CompetitorStat]
    let opportunities: [Opportunity]
    let keywordField: String               // suggested 100-char keyword field
}

// MARK: - Engine

struct KeywordAnalyzer {
    typealias Progress = @Sendable (_ phase: String, _ fraction: Double) async -> Void

    var client: AppStoreClient = .shared
    var myCandidateLimit = 110
    var competitorCandidateLimit = 35
    var maxCompetitors = 6
    var scoredOpportunityLimit = 40
    var scoredKeywordLimit = 30
    var concurrency = 4

    /// Lighter profile for analysing many countries in one go (~2-3x faster).
    static var quick: KeywordAnalyzer {
        var a = KeywordAnalyzer()
        a.myCandidateLimit = 50
        a.competitorCandidateLimit = 12
        a.maxCompetitors = 4
        a.scoredOpportunityLimit = 20
        a.scoredKeywordLimit = 12
        a.concurrency = 2
        return a
    }

    func run(appId: String, country: String, pinnedCompetitorIds: [String] = [],
             progress: Progress) async throws -> AnalysisResult {
        // 1. Metadata of my app (+ subtitle via a search for its own name).
        await progress(String(localized: "Fetching app details"), 0.02)
        let store = Storefronts.byCode(country)
        // Without `lang`, Apple returns the default (usually English) metadata even in localized stores.
        let storeLang = store.languages.first.map { "\($0.lowercased())_\(country)" }
        guard let base = try await client.lookup(ids: [appId], country: country).first else {
            throw AppStoreError.decoding
        }
        let appLangs = Set((base.languages ?? []).map { $0.uppercased() })
        let myLang = store.languages.first(where: appLangs.contains).map { "\($0.lowercased())_\(country)" }
        var me = base
        if let myLang, let localized = try await client.lookup(ids: [appId], country: country, lang: myLang).first {
            me = localized
        }
        if me.subtitle == nil {
            let r = try await client.search(term: me.name, country: country)
            me.subtitle = r.lockups[appId]?.subtitle
        }

        // 2. Candidate terms for my app.
        await progress(String(localized: "Extracting candidate keywords"), 0.05)
        let title = KeywordExtractor.titleTerms(name: me.name, subtitle: me.subtitle, country: country)
        var candidates = title
        candidates += KeywordExtractor.descriptionTerms(me.description, country: country, limit: 45)
        let seeds = title.filter { $0.term.split(separator: " ").count <= 2 }.prefix(6)
        for seed in seeds {
            for h in ((try? await client.hints(for: seed.term, country: country)) ?? []).prefix(8) {
                candidates.append(.init(term: KeywordExtractor.lower(h), source: KeywordSource.suggestion))
            }
        }
        let myCandidates = Array(dedupe(candidates).prefix(myCandidateLimit))
        var sourceOf: [String: String] = [:]
        for c in myCandidates { sourceOf[c.term] = c.source }

        // 3. Search every candidate once (results give ranks for ALL apps at once).
        var results: [String: SearchResult] = [:]
        try await searchAll(myCandidates.map(\.term), country: country, into: &results) { done, total in
            await progress(String(localized: "Searching keywords (\(done)/\(total))"), 0.05 + 0.35 * Double(done) / Double(max(1, total)))
        }

        // 4. Competitor discovery: apps that keep showing up near the top for my terms.
        await progress(String(localized: "Finding competitors"), 0.42)
        var overlap: [String: Double] = [:]
        for r in results.values {
            for (i, id) in r.ids.prefix(15).enumerated() where id != appId {
                overlap[id, default: 0] += Double(15 - i) / 15
            }
        }
        let topIds = overlap.sorted { $0.value > $1.value }.prefix(20).map(\.key)
        let infos = try await client.lookup(ids: topIds + pinnedCompetitorIds, country: country, lang: storeLang)
        let myGenre = me.genreIds.first
        var ranked: [(AppInfo, Double, Bool)] = infos
            .filter { $0.developer != me.developer || pinnedCompetitorIds.contains($0.id) }
            .map { info in
                let same = myGenre != nil && info.genreIds.first == myGenre
                // Different category = probably a word collision (e.g. "trend" -> a shopping app).
                return (info, (overlap[info.id] ?? 0) * (same ? 1.3 : 0.3), same)
            }
        ranked.sort { $0.1 > $1.1 }
        var chosen = ranked.filter { pinnedCompetitorIds.contains($0.0.id) }
        for r in ranked where chosen.count < maxCompetitors && !chosen.contains(where: { $0.0.id == r.0.id }) {
            chosen.append(r)
        }
        // Subtitles for competitors (cheap: learned from lockups, else search their name).
        var competitors: [AppInfo] = []
        for (info, _, _) in chosen {
            var c = info
            if c.subtitle == nil {
                c.subtitle = await client.knownSubtitle(for: c.id)
                if c.subtitle == nil {
                    c.subtitle = (try? await client.search(term: c.name, country: country))?.lockups[c.id]?.subtitle
                }
            }
            competitors.append(c)
        }

        // 5. Competitors' own candidate terms.
        var compCandidates: [KeywordExtractor.Candidate] = []
        for c in competitors {
            let t = KeywordExtractor.titleTerms(name: c.name, subtitle: c.subtitle, country: country)
            let d = KeywordExtractor.descriptionTerms(c.description, country: country, limit: 15)
            compCandidates += Array(dedupe(t + d).prefix(competitorCandidateLimit))
        }
        let newTerms = dedupe(compCandidates).map(\.term).filter { results[$0] == nil }
        for t in newTerms where sourceOf[t] == nil { sourceOf[t] = KeywordSource.competitor }
        try await searchAll(newTerms, country: country, into: &results) { done, total in
            await progress(String(localized: "Searching competitor keywords (\(done)/\(total))"), 0.45 + 0.30 * Double(done) / Double(max(1, total)))
        }

        // 6. Rank maps.
        let compIds = competitors.map(\.id)
        let myTitleWords = Set(KeywordExtractor.words(of: me.name + " " + (me.subtitle ?? ""), country: country))
        // Brand = first part of a competitor's name, or any single-word part ("Kilo Verme - DiyetLab").
        let brands: Set<String> = Set(competitors.flatMap { c -> [String] in
            let segs = KeywordExtractor.lower(c.name)
                .components(separatedBy: CharacterSet(charactersIn: ":-–—|,"))
                .map { $0.trimmingCharacters(in: .whitespaces.union(.punctuationCharacters)) }
                .filter { !$0.isEmpty }
            return segs.enumerated().compactMap { i, seg in
                guard i == 0 || !seg.contains(" ") else { return nil }
                return myTitleWords.contains(seg) ? nil : seg
            }
        })
        let developerBrands: [String] = competitors.map {
            KeywordExtractor.lower($0.developer).filter { $0.isLetter || $0.isNumber }
        }
        func isBrandQuery(_ term: String, _ r: SearchResult) -> Bool {
            if brands.contains(where: { term == $0 || term.hasPrefix($0 + " ") }) { return true }
            // A query word that is a competitor's developer/brand name (e.g. "mynetdiary").
            for w in KeywordExtractor.words(of: term, country: country) where w.count >= 4 && !myTitleWords.contains(w) {
                if developerBrands.contains(where: { $0.contains(w) }) { return true }
            }
            // Navigational search for one app: a word of the query appears only in the #1 result's name.
            guard let first = r.ids.first, let topName = r.lockups[first]?.name else { return false }
            func squash(_ s: String) -> String {
                KeywordExtractor.lower(s).filter { $0.isLetter || $0.isNumber }
            }
            let top = squash(topName)
            let others = r.ids.dropFirst().prefix(7).compactMap { r.lockups[$0]?.name }.map(squash)
            guard others.count >= 3 else { return top == squash(term) }
            for w in KeywordExtractor.words(of: term, country: country) where w.count >= 3 && !myTitleWords.contains(w) {
                if top.contains(squash(w)) && others.filter({ $0.contains(squash(w)) }).count <= 1 { return true }
            }
            return false
        }
        var mine: [KeywordStat] = []
        var opps: [Opportunity] = []
        for (term, r) in results {
            let myRank = r.rank(of: appId)
            if let myRank { mine.append(KeywordStat(term: term, source: sourceOf[term] ?? "", rank: myRank)) }
            var cr: [String: Int] = [:]
            for id in compIds { if let rk = r.rank(of: id), rk <= 30 { cr[id] = rk } }
            let strong = cr.values.contains { $0 <= 10 } || cr.count >= 2
            if !cr.isEmpty, strong, (myRank ?? Int.max) > 30, !isBrandQuery(term, r) {
                let prelim = cr.values.reduce(0.0) { $0 + (1 - Double($1 - 1) / 30) }
                opps.append(Opportunity(term: term, myRank: myRank, competitorRanks: cr, score: prelim))
            }
        }
        mine.sort { ($0.rank ?? 999, $0.term) < ($1.rank ?? 999, $1.term) }
        opps.sort { $0.score > $1.score }
        opps = Array(opps.prefix(scoredOpportunityLimit))

        let compStats: [CompetitorStat] = competitors.map { c in
            var shared = 0, rankedCount = 0
            for r in results.values {
                guard let rk = r.rank(of: c.id), rk <= 50 else { continue }
                rankedCount += 1
                if let m = r.rank(of: appId), m <= 50 { shared += 1 }
            }
            let same = myGenre != nil && c.genreIds.first == myGenre
            return CompetitorStat(app: c, sameGenre: same, sharedKeywords: shared, rankedKeywords: rankedCount,
                                  overlapScore: overlap[c.id] ?? 0)
        }

        // 7. Difficulty + popularity for the terms we show.
        let titleSet = Set(title.map(\.term))
        var missed = title.filter { results[$0.term]?.rank(of: appId) == nil && results[$0.term] != nil }
            .map { KeywordStat(term: $0.term, source: $0.source, rank: nil) }
        let scoreTerms = Array(Set(mine.prefix(scoredKeywordLimit).map(\.term) + opps.map(\.term) + missed.map(\.term)))
        let top10 = scoreTerms.flatMap { results[$0]?.ids.prefix(10) ?? [] }
        let topInfos = try await client.lookup(ids: Array(Set(top10)), country: country)
        let infoById = Dictionary(topInfos.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var diff: [String: Int] = [:]
        for t in scoreTerms {
            let apps = (results[t]?.ids.prefix(10) ?? []).compactMap { infoById[$0] }
            diff[t] = Scoring.difficulty(term: t, topApps: apps)
        }
        var pop: [String: Int] = [:]
        var done = 0
        for chunk in scoreTerms.chunked(into: 3) {
            await withTaskGroup(of: (String, Int).self) { group in
                for t in chunk {
                    group.addTask { (t, await Scoring.estimatePopularity(term: t, country: country, client: client)) }
                }
                for await (t, p) in group { pop[t] = p }
            }
            done += chunk.count
            await progress(String(localized: "Calculating popularity and difficulty (\(done)/\(scoreTerms.count))"),
                           0.77 + 0.21 * Double(done) / Double(max(1, scoreTerms.count)))
        }

        for i in mine.indices { mine[i].popularity = pop[mine[i].term]; mine[i].difficulty = diff[mine[i].term] }
        for i in missed.indices { missed[i].popularity = pop[missed[i].term]; missed[i].difficulty = diff[missed[i].term] }
        missed.sort { ($0.popularity ?? 0) > ($1.popularity ?? 0) }
        for i in opps.indices {
            let p = Double(pop[opps[i].term] ?? 5), d = Double(diff[opps[i].term] ?? 50)
            opps[i].popularity = pop[opps[i].term]
            opps[i].difficulty = diff[opps[i].term]
            var s = p * (1 - 0.6 * d / 100) * (1 + 0.15 * Double(opps[i].competitorRanks.count - 1))
            if let m = opps[i].myRank, m <= 100 { s *= 1.1 }   // already partly relevant
            opps[i].score = min(100, (s * 10).rounded() / 10)
        }
        opps.sort { $0.score > $1.score }

        // 8. Keyword field suggestion (100 chars, comma separated, no words already in name/subtitle).
        let field = keywordField(me: me, country: country,
                                 terms: opps.filter { $0.score >= 15 }.map(\.term) + mine.filter { ($0.rank ?? 0) > 5 && !titleSet.contains($0.term) }.map(\.term))

        await progress(String(localized: "Done"), 1)
        return AnalysisResult(appId: appId, country: country, createdAt: Date(), app: me,
                              searchedTerms: results.count, myKeywords: mine, missedTitleTerms: missed,
                              competitors: compStats, opportunities: opps, keywordField: field)
    }

    // MARK: Helpers

    private func dedupe(_ c: [KeywordExtractor.Candidate]) -> [KeywordExtractor.Candidate] {
        var seen = Set<String>()
        return c.filter { cand in
            let t = cand.term
            // Autocomplete often returns full app names ("brand: tagline", "x & y - z"): not real keywords.
            let allowed = CharacterSet.alphanumerics.union(.whitespaces).union(CharacterSet(charactersIn: "'"))
            let appNameLike = t.unicodeScalars.contains { !allowed.contains($0) }
            return !t.isEmpty && t.count <= 40 && !appNameLike && seen.insert(t).inserted
        }
    }

    private func searchAll(_ terms: [String], country: String, into results: inout [String: SearchResult],
                           tick: (Int, Int) async -> Void) async throws {
        var done = 0, failed = 0
        for chunk in terms.chunked(into: concurrency) {
            let batch = await withTaskGroup(of: (String, SearchResult?).self) { group in
                for t in chunk {
                    group.addTask { (t, try? await client.search(term: t, country: country)) }
                }
                var out: [(String, SearchResult?)] = []
                for await r in group { out.append(r) }
                return out
            }
            for (t, r) in batch {
                if let r { results[t] = r } else { failed += 1 }
            }
            if let until = await client.isSearchBlocked() { throw AppStoreError.blocked(until: until) }
            done += chunk.count
            await tick(done, terms.count)
            if done >= 12 && failed * 2 > done { throw AppStoreError.badResponse(429) }
        }
    }

    private func keywordField(me: AppInfo, country: String, terms: [String]) -> String {
        let used = Set(KeywordExtractor.words(of: me.name + " " + (me.subtitle ?? ""), country: country))
        var words: [String] = []
        func has(_ w: String) -> Bool {
            words.contains(w) || words.contains(w + "s") || (w.hasSuffix("s") && words.contains(String(w.dropLast())))
                || used.contains(w) || (w.hasSuffix("s") && used.contains(String(w.dropLast()))) || used.contains(w + "s")
        }
        var length = 0
        for t in terms {
            for w in KeywordExtractor.words(of: t, country: country) where !has(w) {
                let add = w.count + (words.isEmpty ? 0 : 1)
                guard length + add <= 100 else { continue }
                words.append(w)
                length += add
            }
        }
        return words.joined(separator: ",")
    }
}
