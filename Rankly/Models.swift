import Foundation
import SwiftData

@Model
final class TrackedApp {
    @Attribute(.unique) var appId: String
    var name: String
    var developer: String
    var iconURL: String?
    var isCompetitor: Bool
    var addedAt: Date
    @Relationship(deleteRule: .cascade, inverse: \Keyword.app) var keywords: [Keyword] = []

    init(appId: String, name: String, developer: String, iconURL: String?, isCompetitor: Bool = false) {
        self.appId = appId
        self.name = name
        self.developer = developer
        self.iconURL = iconURL
        self.isCompetitor = isCompetitor
        self.addedAt = .now
    }
}

@Model
final class Keyword {
    var term: String
    var country: String          // ISO code, e.g. "us"
    var app: TrackedApp?
    var addedAt: Date
    var popularity: Int?         // estimated 5...100
    var popularityUpdatedAt: Date?
    var difficulty: Int?         // 0...100
    var lastCheckedAt: Date?
    var lastError: String?
    @Relationship(deleteRule: .cascade, inverse: \RankSnapshot.keyword) var snapshots: [RankSnapshot] = []

    init(term: String, country: String, app: TrackedApp) {
        self.term = term
        self.country = country
        self.app = app
        self.addedAt = .now
    }

    var sortedSnapshots: [RankSnapshot] { snapshots.sorted { $0.date < $1.date } }

    var latest: RankSnapshot? { snapshots.max { $0.date < $1.date } }

    /// Snapshot from an earlier calendar day than the latest one.
    var previous: RankSnapshot? {
        guard let latest else { return nil }
        let cal = Calendar.current
        return snapshots
            .filter { !cal.isDate($0.date, inSameDayAs: latest.date) && $0.date < latest.date }
            .max { $0.date < $1.date }
    }

    var currentRank: Int? { latest?.rank }

    /// Positive = moved up.
    var change: Int? {
        guard let prev = previous else { return nil }
        switch (prev.rank, latest?.rank) {
        case let (p?, c?): return p - c
        case (nil, _?): return RankSnapshot.notRanked - (latest?.rank ?? 0)
        case (_?, nil): return -(RankSnapshot.notRanked - (prev.rank ?? 0))
        default: return 0
        }
    }
}

@Model
final class RankSnapshot {
    static let notRanked = 251
    var date: Date
    var rank: Int?               // nil = not in top results
    var resultCount: Int
    var keyword: Keyword?

    init(date: Date = .now, rank: Int?, resultCount: Int) {
        self.date = date
        self.rank = rank
        self.resultCount = resultCount
    }
}
