import Foundation
import SwiftData
import AppKit

/// Local integration API (v1) used by Vitrin and MCP clients. See docs/api.md.
/// Security: 127.0.0.1 only, no browser requests (Origin header), Host header checked, bearer token per paired client.
@MainActor
final class RanklyAPI {
    static let version = 1
    let container: ModelContainer
    let analysis: AnalysisCenter
    let refresher: RankRefresher
    let store: IntegrationStore
    private var server: LocalHTTPServer?
    private var pairingInProgress = false
    private lazy var mcp = MCPHandler(api: self)

    init(container: ModelContainer, analysis: AnalysisCenter, refresher: RankRefresher, store: IntegrationStore) {
        self.container = container
        self.analysis = analysis
        self.refresher = refresher
        self.store = store
    }

    var context: ModelContext { container.mainContext }

    // MARK: Lifecycle

    func start() {
        guard server == nil else { return }
        let s = LocalHTTPServer { [weak self] req in
            guard let self else { return .error(503, "Rankly is shutting down") }
            return await self.handle(req)
        }
        do {
            store.apiPort = try s.start()
            store.apiError = nil
            server = s
        } catch {
            store.apiPort = nil
            store.apiError = error.localizedDescription
        }
    }

    func stop() {
        server?.stop()
        server = nil
        store.apiPort = nil
    }

    // MARK: Entry point

    func handle(_ req: HTTPRequest) async -> HTTPResponse {
        // Browsers always send Origin on cross-site requests; integrations never do.
        if req.headers["origin"] != nil { return .error(403, "Browser requests are not allowed") }
        if let port = store.apiPort {
            let allowed = ["127.0.0.1:\(port)", "localhost:\(port)"]
            if let host = req.headers["host"], !allowed.contains(host) { return .error(403, "Invalid Host header") }
        }
        let client = bearer(req).flatMap { store.client(forToken: $0) }

        switch (req.method, req.path) {
        case ("GET", "/v1/status"):
            return .json(StatusDTO(app: "Rankly", version: Self.appVersion, api: Self.version, authorized: client != nil,
                                   client: client?.name))
        case ("POST", "/v1/pair"):
            return await pair(req)
        default:
            break
        }

        guard client != nil else { return .error(401, "Missing or invalid token. Pair first: POST /v1/pair") }
        if req.path == "/mcp" {
            return req.method == "POST" ? await mcp.handle(req) : .error(405, "Use POST for MCP")
        }
        return await route(req)
    }

    /// Routes an authorised request (also used internally by MCP tools).
    func route(_ req: HTTPRequest) async -> HTTPResponse {
        do {
            switch (req.method, req.path) {
            case ("GET", "/v1/apps"): return .json(["apps": appsDTO()])
            case ("GET", "/v1/apps/resolve"): return try await resolve(req)
            case ("POST", "/v1/apps"): return try await trackApp(req)
            case ("GET", "/v1/keywords"): return try keywords(req)
            case ("POST", "/v1/keywords"): return try await addKeywords(req)
            case ("POST", "/v1/ranks"): return try await ranks(req)
            case ("GET", "/v1/analysis"): return try analysisGet(req)
            case ("GET", "/v1/analysis/countries"): return try analysisCountries(req)
            case ("GET", "/v1/analysis/status"): return try analysisStatus(req)
            case ("POST", "/v1/analysis"): return try await analysisStart(req)
            case ("GET", "/v1/events"): return try eventsGet(req)
            case ("POST", "/v1/events"): return try eventsPost(req)
            case ("DELETE", "/v1/events"):
                guard let id = req.query["id"], store.removeEvent(id: id) else { throw APIError(status: 404, message: "Event not found") }
                return .json(["deleted": id])
            default: return .error(404, "Unknown endpoint \(req.method) \(req.path)")
            }
        } catch let e as APIError {
            return .error(e.status, e.message)
        } catch let e as AppStoreError {
            if case .blocked = e { return .error(503, e.localizedDescription) }
            return .error(502, e.localizedDescription)
        } catch {
            return .error(400, "Invalid request: \(error.localizedDescription)")
        }
    }

    struct APIError: Error { let status: Int; let message: String }

    // MARK: Pairing

    private func pair(_ req: HTTPRequest) async -> HTTPResponse {
        struct Body: Decodable { var client: String? }
        let body = (try? req.json(Body.self)) ?? Body()
        let raw = (body.client ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let name = String(raw.filter { !$0.isNewline }.prefix(40))
        guard !name.isEmpty else { return .error(400, "client name is required") }
        guard !pairingInProgress else { return .error(409, "Another pairing request is waiting for approval") }
        pairingInProgress = true
        defer { pairingInProgress = false }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = String(localized: "Allow “\(name)” to connect to Rankly?")
        alert.informativeText = String(localized: "It will be able to read your tracked apps, keywords, ranks and analyses, add keywords and start analyses. You can revoke access at any time in Settings.")
        alert.addButton(withTitle: String(localized: "Allow"))
        alert.addButton(withTitle: String(localized: "Don't Allow"))
        guard alert.runModal() == .alertFirstButtonReturn else { return .error(403, "The user denied the request") }
        let token = store.addClient(name: name)
        return .json(["token": token, "client": name])
    }

    private func bearer(_ req: HTTPRequest) -> String? {
        guard let h = req.headers["authorization"], h.lowercased().hasPrefix("bearer ") else { return nil }
        return String(h.dropFirst(7)).trimmingCharacters(in: .whitespaces)
    }

    // MARK: Apps

    struct StatusDTO: Encodable { let app: String; let version: String; let api: Int; let authorized: Bool; let client: String? }

    struct AppDTO: Encodable {
        let appId: String, bundleId: String?, name: String, developer: String, iconURL: String?
        let competitor: Bool, keywordCount: Int, countries: [String]
    }

    func allApps() -> [TrackedApp] {
        (try? context.fetch(FetchDescriptor<TrackedApp>(sortBy: [SortDescriptor(\.addedAt)]))) ?? []
    }

    func appsDTO() -> [AppDTO] {
        allApps().map {
            AppDTO(appId: $0.appId, bundleId: $0.bundleId, name: $0.name, developer: $0.developer, iconURL: $0.iconURL,
                   competitor: $0.isCompetitor, keywordCount: $0.keywords.count,
                   countries: Array(Set($0.keywords.map(\.country))).sorted())
        }
    }

    /// Finds a tracked app by appId or bundleId; with `lookup`, asks the App Store when it isn't tracked.
    func findApp(appId: String?, bundleId: String?, country: String = "us", lookup: Bool = false) async throws -> (TrackedApp?, AppInfo?) {
        let apps = allApps()
        if let appId, let a = apps.first(where: { $0.appId == appId }) { return (a, nil) }
        if let bundleId, let a = apps.first(where: { $0.bundleId == bundleId }) { return (a, nil) }
        // Older entries have no bundle id yet: fill it in for this lookup.
        if let bundleId, lookup || apps.contains(where: { $0.bundleId == nil }) {
            if let info = try await AppStoreClient.shared.lookup(bundleId: bundleId, country: country) {
                if let a = apps.first(where: { $0.appId == info.id }) {
                    a.bundleId = info.bundleId
                    try? context.save()
                    return (a, info)
                }
                return (nil, info)
            }
        }
        if let appId, lookup, let info = try await AppStoreClient.shared.lookup(ids: [appId], country: country).first {
            return (nil, info)
        }
        return (nil, nil)
    }

    private func resolve(_ req: HTTPRequest) async throws -> HTTPResponse {
        let country = req.query["country"] ?? "us"
        let (app, info) = try await findApp(appId: req.query["appId"], bundleId: req.query["bundleId"], country: country, lookup: true)
        guard app != nil || info != nil else { throw APIError(status: 404, message: "App not found") }
        return .json(ResolveDTO(appId: app?.appId ?? info!.id, bundleId: app?.bundleId ?? info?.bundleId,
                                name: app?.name ?? info!.name, tracked: app != nil, competitor: app?.isCompetitor ?? false))
    }

    struct ResolveDTO: Encodable { let appId: String; let bundleId: String?; let name: String; let tracked: Bool; let competitor: Bool }

    private func trackApp(_ req: HTTPRequest) async throws -> HTTPResponse {
        struct Body: Decodable { var appId: String?; var bundleId: String?; var competitor: Bool?; var country: String? }
        let b = try req.json(Body.self)
        let app = try await ensureApp(appId: b.appId, bundleId: b.bundleId, competitor: b.competitor ?? false, country: b.country ?? "us")
        return .json(["appId": app.appId, "name": app.name])
    }

    func ensureApp(appId: String?, bundleId: String?, competitor: Bool, country: String) async throws -> TrackedApp {
        guard appId != nil || bundleId != nil else { throw APIError(status: 400, message: "appId or bundleId is required") }
        let (existing, info) = try await findApp(appId: appId, bundleId: bundleId, country: country, lookup: true)
        if let existing { return existing }
        guard let info else { throw APIError(status: 404, message: "App not found on the App Store") }
        let app = TrackedApp(appId: info.id, name: info.name, developer: info.developer, iconURL: info.iconURL,
                             isCompetitor: competitor, bundleId: info.bundleId)
        context.insert(app)
        try? context.save()
        return app
    }

    func requireApp(_ req: HTTPRequest) async throws -> TrackedApp {
        let (app, _) = try await findApp(appId: req.query["appId"], bundleId: req.query["bundleId"], country: req.query["country"] ?? "us")
        guard let app else { throw APIError(status: 404, message: "App is not tracked in Rankly") }
        return app
    }

    private func requireAppSync(_ req: HTTPRequest) throws -> TrackedApp {
        let apps = allApps()
        if let id = req.query["appId"], let a = apps.first(where: { $0.appId == id }) { return a }
        if let b = req.query["bundleId"], let a = apps.first(where: { $0.bundleId == b }) { return a }
        throw APIError(status: 404, message: "App is not tracked in Rankly (use appId, or resolve the bundleId first)")
    }

    // MARK: Keywords

    struct KeywordDTO: Encodable {
        let term: String, country: String, rank: Int?, change: Int?, popularity: Int?, difficulty: Int?
        let lastCheckedAt: Date?, error: String?, history: [Point]
        struct Point: Encodable { let date: Date; let rank: Int? }
    }

    private func keywords(_ req: HTTPRequest) throws -> HTTPResponse {
        let app = try requireAppSync(req)
        let country = req.query["country"]
        let rows = app.keywords
            .filter { country == nil || $0.country == country }
            .sorted { ($0.country, $0.rankSort) < ($1.country, $1.rankSort) }
            .map { kw in
                KeywordDTO(term: kw.term, country: kw.country, rank: kw.currentRank, change: kw.change,
                           popularity: kw.popularity, difficulty: kw.difficulty, lastCheckedAt: kw.lastCheckedAt,
                           error: kw.lastError,
                           history: kw.sortedSnapshots.map { .init(date: $0.date, rank: $0.rank) })
            }
        return .json(["keywords": rows])
    }

    private func addKeywords(_ req: HTTPRequest) async throws -> HTTPResponse {
        struct Body: Decodable { var appId: String?; var bundleId: String?; var country: String; var terms: [String] }
        let b = try req.json(Body.self)
        guard Storefronts.all.contains(where: { $0.code == b.country }) else { throw APIError(status: 400, message: "Unknown country \(b.country)") }
        let app = try await ensureApp(appId: b.appId, bundleId: b.bundleId, competitor: false, country: b.country)
        let existing = Set(app.keywords.filter { $0.country == b.country }.map(\.term))
        var added: [Keyword] = []
        for raw in b.terms.prefix(200) {
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !t.isEmpty, t.count <= 100, !existing.contains(t), !added.contains(where: { $0.term == t }) else { continue }
            let kw = Keyword(term: t, country: b.country, app: app)
            context.insert(kw)
            added.append(kw)
        }
        try? context.save()
        if !added.isEmpty {
            let refresher = self.refresher, context = self.context
            Task { await refresher.refresh(keywords: added, context: context) }
        }
        return .json(AddedDTO(appId: app.appId, added: added.map(\.term),
                              existing: b.terms.map { $0.lowercased() }.filter(existing.contains)))
    }

    struct AddedDTO: Encodable { let appId: String; let added: [String]; let existing: [String] }

    /// Live App Store ranks for arbitrary terms (paced and cached by Rankly).
    private func ranks(_ req: HTTPRequest) async throws -> HTTPResponse {
        struct Body: Decodable { var appId: String?; var bundleId: String?; var country: String; var terms: [String]; var rivals: [String]? }
        let b = try req.json(Body.self)
        guard b.terms.count <= 60 else { throw APIError(status: 413, message: "At most 60 terms per request") }
        var appId = b.appId
        if appId == nil, let bundleId = b.bundleId {
            let (tracked, info) = try await findApp(appId: nil, bundleId: bundleId, country: b.country, lookup: true)
            appId = tracked?.appId ?? info?.id
        }
        guard let appId else { throw APIError(status: 404, message: "App not found") }
        var out: [String: RankDTO] = [:]
        for term in b.terms {
            let t = term.trimmingCharacters(in: .whitespaces).lowercased()
            guard !t.isEmpty else { continue }
            let r = try await AppStoreClient.shared.search(term: t, country: b.country)
            var rivals: [String: Int?] = [:]
            for id in b.rivals ?? [] { rivals[id] = r.rank(of: id) }
            out[t] = RankDTO(rank: r.rank(of: appId), results: r.ids.count, rivals: b.rivals == nil ? nil : rivals)
        }
        return .json(RanksDTO(appId: appId, country: b.country, source: "app-store-search", ranks: out))
    }

    struct RankDTO: Encodable { let rank: Int?; let results: Int; let rivals: [String: Int?]? }
    struct RanksDTO: Encodable { let appId: String; let country: String; let source: String; let ranks: [String: RankDTO] }

    // MARK: Analysis

    struct RunDTO: Encodable { let country: String; let phase: String; let fraction: Double; let error: String? }
    struct BatchDTO: Encodable {
        let countries: [String]; let index: Int; let current: String?; let failed: [String]; let finished: Bool; let blockedUntil: Date?
    }

    private func analysisGet(_ req: HTTPRequest) throws -> HTTPResponse {
        let app = try requireAppSync(req)
        guard let country = req.query["country"] else { throw APIError(status: 400, message: "country is required") }
        let r = analysis.result(appId: app.appId, country: country)
        let s = analysis.state(appId: app.appId, country: country)
        return .json(AnalysisDTO(analysis: r, running: s.map { RunDTO(country: country, phase: $0.phase, fraction: $0.fraction, error: $0.error) }))
    }

    struct AnalysisDTO: Encodable { let analysis: AnalysisResult?; let running: RunDTO? }

    private func analysisCountries(_ req: HTTPRequest) throws -> HTTPResponse {
        let app = try requireAppSync(req)
        let list = analysis.allResults(appId: app.appId).map {
            CountryDTO(country: $0.country, createdAt: $0.createdAt, ranked: $0.myKeywords.count,
                       opportunities: $0.opportunities.count, competitors: $0.competitors.count)
        }
        return .json(["countries": list])
    }

    struct CountryDTO: Encodable { let country: String; let createdAt: Date; let ranked: Int; let opportunities: Int; let competitors: Int }

    private func analysisStatus(_ req: HTTPRequest) throws -> HTTPResponse {
        let app = try requireAppSync(req)
        let running = analysis.running.compactMap { key, s -> RunDTO? in
            guard key.hasPrefix(app.appId + "-") else { return nil }
            return RunDTO(country: String(key.dropFirst(app.appId.count + 1)), phase: s.phase, fraction: s.fraction, error: s.error)
        }
        let b = analysis.batch(appId: app.appId).map {
            BatchDTO(countries: $0.countries, index: $0.index, current: $0.current, failed: $0.failed,
                     finished: $0.finished, blockedUntil: $0.blockedUntil)
        }
        return .json(StatusRunDTO(batch: b, running: running))
    }

    struct StatusRunDTO: Encodable { let batch: BatchDTO?; let running: [RunDTO] }

    private func analysisStart(_ req: HTTPRequest) async throws -> HTTPResponse {
        struct Body: Decodable { var appId: String?; var bundleId: String?; var countries: [String] }
        let b = try req.json(Body.self)
        let codes = b.countries.map { $0.lowercased() }.filter { c in Storefronts.all.contains { $0.code == c } }
        guard !codes.isEmpty else { throw APIError(status: 400, message: "countries must contain App Store country codes") }
        if let until = await AppStoreClient.shared.isSearchBlocked() {
            throw APIError(status: 503, message: AppStoreError.blocked(until: until).localizedDescription)
        }
        let app = try await ensureApp(appId: b.appId, bundleId: b.bundleId, competitor: false, country: codes[0])
        let pinned = allApps().filter(\.isCompetitor).map(\.appId)
        if analysis.batch(appId: app.appId).map({ !$0.finished }) ?? false {
            throw APIError(status: 409, message: "A multi-country analysis is already running for this app")
        }
        analysis.dismissBatch(appId: app.appId)
        if codes.count == 1 {
            analysis.start(appId: app.appId, country: codes[0], pinnedCompetitors: pinned)
        } else {
            analysis.startBatch(appId: app.appId, countries: codes, pinnedCompetitors: pinned)
        }
        return .json(StartedDTO(appId: app.appId, countries: codes, started: true))
    }

    struct StartedDTO: Encodable { let appId: String; let countries: [String]; let started: Bool }

    // MARK: Events

    private func eventsGet(_ req: HTTPRequest) throws -> HTTPResponse {
        let app = try requireAppSync(req)
        return .json(["events": store.events(for: app.appId)])
    }

    private func eventsPost(_ req: HTTPRequest) throws -> HTTPResponse {
        struct Body: Decodable { var appId: String?; var bundleId: String?; var date: Date?; var kind: String?; var note: String; var countries: [String]? }
        let b = try req.json(Body.self)
        let apps = allApps()
        guard let app = apps.first(where: { $0.appId == b.appId }) ?? apps.first(where: { b.bundleId != nil && $0.bundleId == b.bundleId }) else {
            throw APIError(status: 404, message: "App is not tracked in Rankly")
        }
        let client = bearer(req).flatMap { store.client(forToken: $0) }?.name ?? "API"
        let kind = b.kind == "release" ? "release" : "note"
        let e = IntegrationStore.Event(appId: app.appId, date: b.date ?? .now, kind: kind, note: String(b.note.prefix(200)),
                                       source: client, countries: b.countries)
        store.addEvent(e)
        return .json(e)
    }

    static var appVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?" }
}
