import Foundation

struct AppInfo: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let name: String
    let developer: String
    let iconURL: String?
    let ratingCount: Int
    let rating: Double
    let genre: String?
    let price: String?
    var genreIds: [String] = []
    var description: String? = nil
    var subtitle: String? = nil
    var languages: [String]? = nil
}

struct SearchResult: Sendable {
    let ids: [String]
    /// Name/subtitle for the first few results (Apple only sends full lockups for the top ~8).
    let lockups: [String: (name: String, subtitle: String?)]

    func rank(of appId: String) -> Int? { ids.firstIndex(of: appId).map { $0 + 1 } }
}

enum AppStoreError: LocalizedError {
    case badResponse(Int)
    case decoding
    case blocked(until: Date)
    var errorDescription: String? {
        switch self {
        case .blocked(let until):
            return String(localized: "Apple temporarily blocked App Store search for this network (403). Try again after \(until.formatted(date: .omitted, time: .shortened)).")
        case .badResponse(403): return String(localized: "The App Store denied access (403)")
        case .badResponse(429): return String(localized: "App Store rate limit (429). Try again in a moment.")
        case .badResponse(let code): return String(localized: "App Store HTTP \(code)")
        case .decoding: return String(localized: "Couldn't read the App Store response")
        }
    }
}

/// Talks to Apple's public App Store endpoints (no account required).
/// Caches responses and spaces requests out so long analyses don't get rate-limited.
actor AppStoreClient {
    static let shared = AppStoreClient()

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 20
        cfg.httpAdditionalHeaders = ["User-Agent": "AppStore/3.0 iOS/17.0 model/iPhone15,2"]
        return URLSession(configuration: cfg)
    }()

    private let cacheTTL: TimeInterval = 6 * 3600
    private var lookupCache: [String: (Date, AppInfo)] = [:]
    private var searchCache: [String: (Date, SearchResult)] = [:]
    private var hintsCache: [String: (Date, [String])] = [:]
    private var subtitles: [String: String] = [:]          // appId -> subtitle, learned from search lockups
    private var nextSlot = Date.distantPast
    private var nextSearchSlot = Date.distantPast
    private let minSpacing: TimeInterval = 0.3
    /// The ranking endpoint is the one Apple blocks (403) when hit too often; pace it separately.
    /// Adaptive: doubles after every block (max 8 s) and is remembered across launches.
    private var searchSpacing: TimeInterval = {
        let v = UserDefaults.standard.double(forKey: "searchSpacing")
        return v > 0 ? v : 1.5
    }()

    func currentSearchSpacing() -> TimeInterval { searchSpacing }
    private(set) var searchBlockedUntil: Date?

    func isSearchBlocked() -> Date? {
        if let u = searchBlockedUntil, u > Date() { return u }
        return nil
    }

    // MARK: Search ranking

    /// Ordered App Store search result ids for a term (what the iPhone App Store shows).
    func searchRanking(term: String, country: String) async throws -> [String] {
        try await search(term: term, country: country).ids
    }

    func search(term: String, country: String) async throws -> SearchResult {
        let key = "\(country)|\(term.lowercased())"
        if let (d, r) = searchCache[key], Date().timeIntervalSince(d) < cacheTTL { return r }
        var comps = URLComponents(string: "https://search.itunes.apple.com/WebObjects/MZStore.woa/wa/search")!
        comps.queryItems = [
            .init(name: "clientApplication", value: "Software"),
            .init(name: "media", value: "software"),
            .init(name: "term", value: term),
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue("\(Storefronts.byCode(country).id),29", forHTTPHeaderField: "X-Apple-Store-Front")
        let data = try await fetch(req)
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let page = json["pageData"] as? [String: Any],
            let bubbles = page["bubbles"] as? [[String: Any]]
        else { throw AppStoreError.decoding }
        let bubble = bubbles.first { ($0["name"] as? String) == "software" } ?? bubbles.first ?? [:]
        let items = bubble["results"] as? [[String: Any]] ?? []
        let ids: [String] = items.compactMap { item in
            if let s = item["id"] as? String { return s }
            if let n = item["id"] as? Int { return String(n) }
            return nil
        }
        var lockups: [String: (name: String, subtitle: String?)] = [:]
        if let spd = json["storePlatformData"] as? [String: Any],
           let nsl = spd["native-search-lockup"] as? [String: Any],
           let results = nsl["results"] as? [String: [String: Any]] {
            for (id, r) in results {
                guard let name = r["name"] as? String else { continue }
                let sub = r["subtitle"] as? String
                lockups[id] = (name, sub)
                if let sub { subtitles[id] = sub }
            }
        }
        let result = SearchResult(ids: ids, lockups: lockups)
        searchCache[key] = (Date(), result)
        return result
    }

    func knownSubtitle(for appId: String) -> String? { subtitles[appId] }

    // MARK: Lookup / search apps

    func lookup(ids: [String], country: String, lang: String? = nil) async throws -> [AppInfo] {
        let ck = lang.map { "\(country)/\($0)" } ?? country
        let now = Date()
        var found: [String: AppInfo] = [:]
        var missing: [String] = []
        for id in ids {
            if let (d, info) = lookupCache["\(ck):\(id)"], now.timeIntervalSince(d) < cacheTTL {
                found[id] = info
            } else if !missing.contains(id) { missing.append(id) }
        }
        for chunk in missing.chunked(into: 100) {
            var comps = URLComponents(string: "https://itunes.apple.com/lookup")!
            comps.queryItems = [.init(name: "id", value: chunk.joined(separator: ",")),
                                .init(name: "country", value: country),
                                .init(name: "entity", value: "software")] + (lang.map { [.init(name: "lang", value: $0)] } ?? [])
            let data = try await fetch(URLRequest(url: comps.url!))
            for info in try Self.parseITunes(data) {
                found[info.id] = info
                lookupCache["\(ck):\(info.id)"] = (now, info)
            }
        }
        return ids.compactMap { id in
            guard var info = found[id] else { return nil }
            if info.subtitle == nil { info.subtitle = subtitles[id] }
            return info
        }
    }

    /// Find apps by name or numeric App Store id.
    func findApps(query: String, country: String) async throws -> [AppInfo] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let digits = trimmed.replacingOccurrences(of: "id", with: "")
        if !digits.isEmpty, digits.allSatisfy(\.isNumber) {
            return try await lookup(ids: [digits], country: country)
        }
        if let url = URL(string: trimmed), let idPart = url.path.split(separator: "/").last(where: { $0.hasPrefix("id") }) {
            return try await lookup(ids: [String(idPart.dropFirst(2))], country: country)
        }
        var comps = URLComponents(string: "https://itunes.apple.com/search")!
        comps.queryItems = [.init(name: "term", value: trimmed), .init(name: "country", value: country),
                            .init(name: "entity", value: "software"), .init(name: "limit", value: "25")]
        let data = try await fetch(URLRequest(url: comps.url!))
        return try Self.parseITunes(data)
    }

    // MARK: Suggestions (App Store autocomplete)

    func hints(for term: String, country: String) async throws -> [String] {
        let key = "\(country)|\(term.lowercased())"
        if let (d, h) = hintsCache[key], Date().timeIntervalSince(d) < cacheTTL { return h }
        var comps = URLComponents(string: "https://search.itunes.apple.com/WebObjects/MZSearchHints.woa/wa/hints")!
        comps.queryItems = [.init(name: "clientApplication", value: "Software"), .init(name: "term", value: term)]
        var req = URLRequest(url: comps.url!)
        req.setValue("\(Storefronts.byCode(country).id),29", forHTTPHeaderField: "X-Apple-Store-Front")
        let data = try await fetch(req)
        guard
            let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            let hints = plist["hints"] as? [[String: Any]]
        else { return [] }
        let result = hints.compactMap { $0["term"] as? String }
        hintsCache[key] = (Date(), result)
        return result
    }

    // MARK: Helpers

    /// Reserve the next request slot (actor-safe even with reentrancy).
    private func waitForSlot(search: Bool) async {
        let now = Date()
        var slot = max(now, nextSlot)
        if search { slot = max(slot, nextSearchSlot) }
        nextSlot = slot.addingTimeInterval(minSpacing)
        if search { nextSearchSlot = slot.addingTimeInterval(searchSpacing + Double.random(in: 0...0.4)) }
        let delay = slot.timeIntervalSince(now)
        if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
    }

    private func fetch(_ req: URLRequest) async throws -> Data {
        var lastError: Error = AppStoreError.decoding
        let isSearch = req.url?.path.contains("MZStore.woa") == true
        for attempt in 0..<4 {
            if isSearch, let until = isSearchBlocked() { throw AppStoreError.blocked(until: until) }
            await waitForSlot(search: isSearch)
            do {
                let (data, resp) = try await session.data(for: req)
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                if code == 200 { return data }
                lastError = AppStoreError.badResponse(code)
                if code == 403 && isSearch {
                    // Hammering a blocked endpoint only extends the block: stop everything for an hour.
                    let until = Date().addingTimeInterval(3600)
                    searchBlockedUntil = until
                    searchSpacing = min(8, searchSpacing * 2)
                    UserDefaults.standard.set(searchSpacing, forKey: "searchSpacing")
                    throw AppStoreError.blocked(until: until)
                }
                if code != 429 && code < 500 { throw lastError }
                if code == 429 {
                    // Back off everyone, not just this request.
                    nextSlot = max(nextSlot, Date().addingTimeInterval(Double(attempt + 1) * 10))
                }
            } catch let e as AppStoreError { throw e } catch { lastError = error }
            try await Task.sleep(nanoseconds: UInt64(attempt + 1) * 1_500_000_000)
        }
        throw lastError
    }

    private static func parseITunes(_ data: Data) throws -> [AppInfo] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else { throw AppStoreError.decoding }
        return results.compactMap { r in
            guard let id = r["trackId"] as? Int, let name = r["trackName"] as? String else { return nil }
            return AppInfo(id: String(id), name: name,
                           developer: r["sellerName"] as? String ?? r["artistName"] as? String ?? "",
                           iconURL: r["artworkUrl100"] as? String,
                           ratingCount: r["userRatingCount"] as? Int ?? 0,
                           rating: r["averageUserRating"] as? Double ?? 0,
                           genre: r["primaryGenreName"] as? String,
                           price: r["formattedPrice"] as? String,
                           genreIds: r["genreIds"] as? [String] ?? [],
                           description: r["description"] as? String,
                           languages: r["languageCodesISO2A"] as? [String])
        }
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
