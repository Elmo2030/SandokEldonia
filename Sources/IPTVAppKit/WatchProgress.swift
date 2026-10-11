import Foundation
import GRDB
import IPTVCore

/// A title that can be resumed, with how far along it is (and, for a series, the episode that was last watched).
public struct ContinueEntry: Identifiable, Equatable {
    public var item: Item
    public var fraction: Double?                     // 0...1, nil when unknown
    public var season: Int?, episode: Int?
    public var id: Int64? { item.id }
}

public struct EpisodeProgress: Equatable {
    public var position: Double, duration: Double
    public var rank: Int                             // 0 = watched longest ago; the highest rank is the latest
    public var fraction: Double { duration > 0 ? min(max(position / duration, 0), 1) : 0 }
    public var isWatched: Bool { fraction > 0.95 }
}

public enum WatchProgress {
    /// The continue-watching list of one type with progress, newest first (the shelf shows the first `limit`).
    public static func continueEntries(_ db: Database, accountId: Int64?, type: ItemType, limit: Int = 20) throws -> [ContinueEntry] {
        try UserData.continueWatching(db, accountId: accountId, type: type).prefix(limit).map { item in
            if type == .series, let r = try Row.fetchOne(db, sql: """
                SELECT h.position, h.duration, e.season, e.number FROM history h
                JOIN episode e ON e.accountId = h.accountId AND h.streamId = 'ep:' || e.streamId
                WHERE e.accountId = ? AND e.seriesId = ? AND h.type = 'series' ORDER BY h.updated DESC, h.rowid DESC LIMIT 1
                """, arguments: [item.accountId, item.streamId]) {
                return ContinueEntry(item: item, fraction: fraction(r["position"], r["duration"]), season: r["season"], episode: r["number"])
            }
            let r = try Row.fetchOne(db, sql: "SELECT position, duration FROM history WHERE accountId = ? AND type = ? AND streamId = ?",
                                     arguments: [item.accountId, item.type.rawValue, item.streamId])
            return ContinueEntry(item: item, fraction: r.flatMap { fraction($0["position"], $0["duration"]) })
        }
    }

    private static func fraction(_ p: Double, _ d: Double) -> Double? { d > 0 ? min(max(p / d, 0), 1) : nil }

    /// Resume points of a series' episodes, keyed by the episode's stream id.
    public static func episodeProgress(_ db: Database, accountId: Int64) throws -> [String: EpisodeProgress] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT streamId, position, duration FROM history WHERE accountId = ? AND type = 'series' AND streamId LIKE 'ep:%' ORDER BY updated, rowid
            """, arguments: [accountId])
        var out: [String: EpisodeProgress] = [:]
        for (i, r) in rows.enumerated() {
            let sid: String = r["streamId"]
            out[String(sid.dropFirst(3))] = EpisodeProgress(position: r["position"], duration: r["duration"], rank: i)
        }
        return out
    }

    /// What the series screen offers first: the episode left halfway (resume), else the one after the last finished, else the first.
    /// nil once every episode up to the last one is watched.
    public static func upNext(_ episodes: [Episode], progress: [String: EpisodeProgress]) -> (episode: Episode, resume: Bool)? {
        let ordered = episodes.sorted { ($0.season, $0.number) < ($1.season, $1.number) }
        guard let first = ordered.first else { return nil }
        let seen = ordered.compactMap { e in progress[e.streamId].map { (e, $0) } }
        guard let (last, p) = seen.max(by: { $0.1.rank < $1.1.rank }) else { return (first, false) }
        if !p.isWatched && p.position >= 5 { return (last, true) }
        return EpisodeQueue.next(after: last.streamId, in: ordered).map { ($0, false) }
    }
}
