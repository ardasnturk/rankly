import Foundation

/// Runs analyses in the background (single country or a multi-country queue per app)
/// and stores results as JSON in Application Support.
@MainActor
final class AnalysisCenter: ObservableObject {
    struct RunState {
        var phase = ""
        var fraction = 0.0
        var error: String?
    }

    struct BatchState {
        var countries: [String]
        var index = 0
        var current: String?
        var failed: [String] = []
        var reasons: [String: String] = [:]
        var blockedUntil: Date?
        var finished = false
        var fraction: Double { countries.isEmpty ? 1 : Double(index) / Double(countries.count) }
    }

    @Published private(set) var running: [String: RunState] = [:]      // key: appId-country
    @Published private(set) var results: [String: AnalysisResult] = [:] // key: appId-country
    @Published private(set) var batches: [String: BatchState] = [:]    // key: appId

    private var tasks: [String: Task<Void, Never>] = [:]
    private var batchTasks: [String: Task<Void, Never>] = [:]
    private var loadedFromDisk = Set<String>()

    static func key(_ appId: String, _ country: String) -> String { "\(appId)-\(country)" }

    private var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Rankly/analysis", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    // MARK: Reading

    func result(appId: String, country: String) -> AnalysisResult? {
        loadAll(appId: appId)
        return results[Self.key(appId, country)]
    }

    /// Every saved country result for an app, sorted by country name.
    func allResults(appId: String) -> [AnalysisResult] {
        loadAll(appId: appId)
        return results.values.filter { $0.appId == appId }
            .sorted { Storefronts.byCode($0.country).name < Storefronts.byCode($1.country).name }
    }

    private func loadAll(appId: String) {
        guard !loadedFromDisk.contains(appId) else { return }
        loadedFromDisk.insert(appId)
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        var loaded: [String: AnalysisResult] = [:]
        for url in files where url.lastPathComponent.hasPrefix("\(appId)-") && url.pathExtension == "json" {
            if let data = try? Data(contentsOf: url), let r = try? dec.decode(AnalysisResult.self, from: data) {
                loaded[Self.key(r.appId, r.country)] = r
            }
        }
        // Publishing during a view update is not allowed; defer.
        DispatchQueue.main.async { self.results.merge(loaded) { current, _ in current } }
        results.merge(loaded) { current, _ in current }
    }

    func state(appId: String, country: String) -> RunState? { running[Self.key(appId, country)] }
    func batch(appId: String) -> BatchState? { batches[appId] }

    // MARK: Single country

    func start(appId: String, country: String, pinnedCompetitors: [String]) {
        let k = Self.key(appId, country)
        guard tasks[k] == nil, batchTasks[appId] == nil else { return }
        tasks[k] = Task { [weak self] in
            await self?.runOne(appId: appId, country: country, pinned: pinnedCompetitors, analyzer: KeywordAnalyzer())
            self?.tasks[k] = nil
        }
    }

    func cancel(appId: String, country: String) {
        let k = Self.key(appId, country)
        tasks[k]?.cancel()
        tasks[k] = nil
        running[k] = nil
    }

    func dismissError(appId: String, country: String) {
        running[Self.key(appId, country)] = nil
    }

    // MARK: Multi-country queue

    func startBatch(appId: String, countries: [String], pinnedCompetitors: [String]) {
        guard batchTasks[appId] == nil, !countries.isEmpty else { return }
        batches[appId] = BatchState(countries: countries)
        batchTasks[appId] = Task { [weak self] in
            for (i, country) in countries.enumerated() {
                if Task.isCancelled { break }
                self?.batches[appId]?.index = i
                self?.batches[appId]?.current = country
                if let until = await AppStoreClient.shared.isSearchBlocked() {
                    self?.stopBatchBlocked(appId: appId, from: i, until: until)
                    return
                }
                var ok = await self?.runOne(appId: appId, country: country, pinned: pinnedCompetitors,
                                            analyzer: .quick) ?? false
                if !ok, let until = await AppStoreClient.shared.isSearchBlocked() {
                    self?.stopBatchBlocked(appId: appId, from: i, until: until)
                    return
                }
                // Usually Apple rate limiting (429): pause longer each time, up to 3 retries.
                for (attempt, wait) in [90, 180, 300].enumerated() where !ok && !Task.isCancelled {
                    for left in stride(from: wait, to: 0, by: -5) {
                        self?.running[Self.key(appId, country)] = RunState(
                            phase: "Apple istek sınırı, \(left) sn sonra tekrar denenecek (\(attempt + 1)/3)", fraction: 0)
                        try? await Task.sleep(nanoseconds: 5_000_000_000)
                        if Task.isCancelled { break }
                    }
                    if Task.isCancelled { break }
                    ok = await self?.runOne(appId: appId, country: country, pinned: pinnedCompetitors,
                                            analyzer: .quick) ?? false
                }
                if !ok {
                    self?.batches[appId]?.failed.append(country)
                    self?.batches[appId]?.reasons[country] = self?.running[Self.key(appId, country)]?.error ?? "Bilinmeyen hata"
                    self?.running[Self.key(appId, country)] = nil
                }
            }
            self?.batches[appId]?.index = countries.count
            self?.batches[appId]?.current = nil
            self?.batches[appId]?.finished = true
            self?.batchTasks[appId] = nil
        }
    }

    /// Apple blocked search: don't retry, keep the remaining countries to resume later.
    private func stopBatchBlocked(appId: String, from index: Int, until: Date) {
        guard var b = batches[appId] else { return }
        let rest = Array(b.countries[index...])
        let reason = AppStoreError.blocked(until: until).localizedDescription
        for c in rest {
            b.failed.append(c)
            b.reasons[c] = reason
            running[Self.key(appId, c)] = nil
        }
        b.index = b.countries.count
        b.current = nil
        b.finished = true
        b.blockedUntil = until
        batches[appId] = b
        batchTasks[appId] = nil
    }

    func cancelBatch(appId: String) {
        batchTasks[appId]?.cancel()
        batchTasks[appId] = nil
        if let c = batches[appId]?.current { running[Self.key(appId, c)] = nil }
        batches[appId] = nil
    }

    func dismissBatch(appId: String) {
        if batches[appId]?.finished == true { batches[appId] = nil }
    }

    // MARK: Internals

    @discardableResult
    private func runOne(appId: String, country: String, pinned: [String], analyzer: KeywordAnalyzer) async -> Bool {
        let k = Self.key(appId, country)
        running[k] = RunState(phase: "Başlıyor", fraction: 0)
        do {
            let result = try await analyzer.run(appId: appId, country: country, pinnedCompetitorIds: pinned) { [weak self] phase, f in
                await MainActor.run { self?.running[k] = RunState(phase: phase, fraction: f) }
            }
            results[k] = result
            save(result, key: k)
            running[k] = nil
            return true
        } catch is CancellationError {
            running[k] = nil
            return false
        } catch {
            if Task.isCancelled { running[k] = nil; return false }
            running[k]?.error = error.localizedDescription
            return false
        }
    }

    private func save(_ r: AnalysisResult, key: String) {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(r) {
            try? data.write(to: folder.appendingPathComponent("\(key).json"), options: .atomic)
        }
    }
}
