import Foundation
import GRDB

public enum UserData {
    public static func toggleFavorite(_ db: Database, accountId: Int64, type: ItemType, streamId: String) throws -> Bool {
        let args: StatementArguments = [accountId, type.rawValue, streamId]
        let exists = try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM favorite WHERE accountId=? AND type=? AND streamId=?)", arguments: args) ?? false
        try db.execute(sql: exists ? "DELETE FROM favorite WHERE accountId=? AND type=? AND streamId=?"
                                   : "INSERT INTO favorite (accountId,type,streamId) VALUES (?,?,?)", arguments: args)
        return !exists
    }

    /// Playlists may reuse the same stream id, so a favorite is identified by its playlist too.
    public static func favoriteKey(accountId: Int64, type: ItemType, streamId: String) -> String { "\(accountId):\(type.rawValue):\(streamId)" }

    /// `accountId: nil` = every playlist (here and in the queries below).
    public static func favoriteKeys(_ db: Database, accountId: Int64?) throws -> Set<String> {
        Set(try Row.fetchAll(db, sql: "SELECT accountId, type, streamId FROM favorite WHERE (? IS NULL OR accountId=?)", arguments: [accountId, accountId])
            .map { favoriteKey(accountId: $0["accountId"], type: ItemType(rawValue: $0["type"]) ?? .live, streamId: $0["streamId"]) })
    }

    public static func favorites(_ db: Database, accountId: Int64?, type: ItemType) throws -> [Item] {
        try Item.fetchAll(db, sql: """
            SELECT item.* FROM item JOIN favorite f ON f.accountId=item.accountId AND f.type=item.type AND f.streamId=item.streamId
            WHERE (? IS NULL OR item.accountId=?) AND item.type=? ORDER BY item.id
            """, arguments: [accountId, accountId, type.rawValue])
    }

    public static func saveProgress(_ db: Database, accountId: Int64, type: ItemType, streamId: String,
                                    position: Double, duration: Double) throws {
        // 0 / 0 means "nothing played yet" (still loading, load failed): saving it would erase the real resume point.
        guard duration > 0, position.isFinite, duration.isFinite, position >= 0 else { return }
        try db.execute(sql: """
            INSERT INTO history (accountId,type,streamId,position,duration,updated) VALUES (?,?,?,?,?,datetime('now'))
            """, arguments: [accountId, type.rawValue, streamId, position, duration])      // `history` is the current profile's view: its trigger replaces the old row
    }

    public static func progress(_ db: Database, accountId: Int64, type: ItemType, streamId: String) throws -> Double? {
        guard let r = try Row.fetchOne(db, sql: "SELECT position, duration FROM history WHERE accountId=? AND type=? AND streamId=?",
                                       arguments: [accountId, type.rawValue, streamId]) else { return nil }
        let p: Double = r["position"], d: Double = r["duration"]
        return (d > 0 && p / d > 0.95) || p < 5 ? nil : p
    }

    /// Settings > Clear data: every playlist's resume points / favorites.
    public static func clearHistory(_ db: Database) throws { try db.execute(sql: "DELETE FROM history") }
    public static func clearFavorites(_ db: Database) throws { try db.execute(sql: "DELETE FROM favorite") }

    public static func continueWatching(_ db: Database, accountId: Int64?, type: ItemType) throws -> [Item] {
        var items = try Item.fetchAll(db, sql: """
            SELECT item.* FROM item JOIN history h ON h.accountId=item.accountId AND h.type=item.type AND h.streamId=item.streamId
            WHERE (? IS NULL OR item.accountId=?) AND item.type=? AND (h.duration <= 0 OR h.position / h.duration <= 0.95)
            ORDER BY h.updated DESC
            """, arguments: [accountId, accountId, type.rawValue])
        if type == .series {
            // Xtream episodes are saved as "ep:<episodeId>": map them to their series through the cached episode list.
            let viaEpisodes = try Item.fetchAll(db, sql: """
                SELECT item.* FROM item JOIN (
                    SELECT e.accountId AS aid, e.seriesId AS sid, MAX(h.updated) AS u FROM history h
                    JOIN episode e ON e.accountId = h.accountId AND h.streamId = 'ep:' || e.streamId
                    WHERE (? IS NULL OR h.accountId = ?) AND h.type = 'series' AND (h.duration <= 0 OR h.position / h.duration <= 0.95)
                    GROUP BY e.accountId, e.seriesId) x ON x.aid = item.accountId AND x.sid = item.streamId
                WHERE item.type = 'series' ORDER BY x.u DESC
                """, arguments: [accountId, accountId])
            let have = Set(items.compactMap(\.id))
            items = viaEpisodes.filter { !have.contains($0.id ?? -1) } + items
        }
        return items
    }

    /// How far back "recently added" reaches.
    public static let recentWindow: TimeInterval = 14 * 86_400

    /// Movies and series a sync first saw in the last `recentWindow`, newest first. Titles that were there from the start have no
    /// date and never show up here. `accountId: nil` = every playlist.
    public static func recentlyAdded(_ db: Database, accountId: Int64?, types: [ItemType] = [.movie, .series],
                                     now: Date = Date(), limit: Int = 60) throws -> [Item] {
        let marks = types.map { _ in "?" }.joined(separator: ",")
        var args: [DatabaseValueConvertible?] = [accountId, accountId, now.addingTimeInterval(-recentWindow)]
        args += types.map(\.rawValue)
        args.append(limit)
        return try Item.fetchAll(db, sql: """
            SELECT * FROM item WHERE (? IS NULL OR accountId = ?) AND addedAt >= ? AND type IN (\(marks))
            ORDER BY addedAt DESC, id DESC LIMIT ?
            """, arguments: StatementArguments(args))
    }

    // MARK: Home rows

    /// Movies and series to resume, newest first: the two lists are each in order of last watched, so they are taken in turns.
    public static func continueWatchingMixed(_ db: Database, accountId: Int64?, limit: Int = 12) throws -> [Item] {
        let movies = try continueWatching(db, accountId: accountId, type: .movie)
        let series = try continueWatching(db, accountId: accountId, type: .series)
        var out: [Item] = []
        for i in 0..<max(movies.count, series.count) {
            if i < movies.count { out.append(movies[i]) }
            if i < series.count { out.append(series[i]) }
        }
        return Array(out.prefix(limit))
    }

    /// "More from <category>": the category of the movie or series watched last, with its titles not watched yet, recently added first.
    /// Nil when nothing was watched, or fewer than `minimum` titles are left (a row of two posters is not a row).
    public static func moreLikeWatched(_ db: Database, accountId: Int64?, limit: Int = 24, minimum: Int = 4) throws -> (category: Category, items: [Item])? {
        guard let last = try Row.fetchOne(db, sql: """
            SELECT accountId, type, categoryId FROM (
              SELECT i.accountId, i.type, i.categoryId, h.updated FROM history h
                JOIN item i ON i.accountId = h.accountId AND i.type = h.type AND i.streamId = h.streamId
              UNION ALL
              SELECT i.accountId, i.type, i.categoryId, h.updated FROM history h
                JOIN episode e ON e.accountId = h.accountId AND h.streamId = 'ep:' || e.streamId
                JOIN item i ON i.accountId = e.accountId AND i.type = 'series' AND i.streamId = e.seriesId
                WHERE h.type = 'series')
            WHERE categoryId IS NOT NULL AND type IN ('movie', 'series') AND (? IS NULL OR accountId = ?)
            ORDER BY updated DESC LIMIT 1
            """, arguments: [accountId, accountId]) else { return nil }
        let aid: Int64 = last["accountId"], type: String = last["type"], cat: String = last["categoryId"]
        guard let category = try Category.filter(Column("accountId") == aid && Column("type") == type && Column("remoteId") == cat).fetchOne(db)
        else { return nil }
        let items = try Item.fetchAll(db, sql: """
            SELECT * FROM item WHERE accountId = ? AND type = ? AND categoryId = ?
              AND NOT EXISTS (SELECT 1 FROM history h WHERE h.accountId = item.accountId AND h.type = item.type AND h.streamId = item.streamId)
              AND NOT EXISTS (SELECT 1 FROM history h JOIN episode e ON e.accountId = h.accountId AND h.streamId = 'ep:' || e.streamId
                              WHERE h.type = 'series' AND e.accountId = item.accountId AND e.seriesId = item.streamId)
            ORDER BY addedAt IS NULL, addedAt DESC, id DESC LIMIT ?
            """, arguments: [aid, type, cat, limit])
        return items.count >= minimum ? (category, items) : nil
    }

    /// The movie or series watched last (a series counts when one of its episodes was).
    public static func lastWatchedTitle(_ db: Database, accountId: Int64?) throws -> Item? {
        try Item.fetchOne(db, sql: """
            SELECT * FROM item WHERE id = (SELECT itemId FROM (
              SELECT i.id AS itemId, h.updated FROM history h
                JOIN item i ON i.accountId = h.accountId AND i.type = h.type AND i.streamId = h.streamId
                WHERE i.type IN ('movie', 'series') AND (? IS NULL OR i.accountId = ?)
              UNION ALL
              SELECT i.id, h.updated FROM history h
                JOIN episode e ON e.accountId = h.accountId AND h.streamId = 'ep:' || e.streamId
                JOIN item i ON i.accountId = e.accountId AND i.type = 'series' AND i.streamId = e.seriesId
                WHERE h.type = 'series' AND (? IS NULL OR i.accountId = ?))
              ORDER BY updated DESC LIMIT 1)
            """, arguments: [accountId, accountId, accountId, accountId])
    }

    // MARK: Watch later

    /// Adds the title to "watch later", or removes it when it is there. Returns whether it is on the list now.
    public static func toggleWatchlist(_ db: Database, accountId: Int64, type: ItemType, streamId: String) throws -> Bool {
        let args: StatementArguments = [accountId, type.rawValue, streamId]
        let exists = try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM watchlist WHERE accountId=? AND type=? AND streamId=?)", arguments: args) ?? false
        try db.execute(sql: exists ? "DELETE FROM watchlist WHERE accountId=? AND type=? AND streamId=?"
                                   : "INSERT INTO watchlist (accountId,type,streamId) VALUES (?,?,?)", arguments: args)
        return !exists
    }

    /// Same key shape as `favoriteKey`.
    public static func watchlistKeys(_ db: Database, accountId: Int64?) throws -> Set<String> {
        Set(try Row.fetchAll(db, sql: "SELECT accountId, type, streamId FROM watchlist WHERE (? IS NULL OR accountId=?)", arguments: [accountId, accountId])
            .map { favoriteKey(accountId: $0["accountId"], type: ItemType(rawValue: $0["type"]) ?? .live, streamId: $0["streamId"]) })
    }

    /// Titles of one type that were set aside, the latest first. A title the provider has dropped since is not listed (it is not in `item`).
    public static func watchlist(_ db: Database, accountId: Int64?, type: ItemType) throws -> [Item] {
        try Item.fetchAll(db, sql: """
            SELECT item.* FROM item JOIN watchlist w ON w.accountId=item.accountId AND w.type=item.type AND w.streamId=item.streamId
            WHERE (? IS NULL OR item.accountId=?) AND item.type=? ORDER BY w.added DESC, item.id DESC
            """, arguments: [accountId, accountId, type.rawValue])
    }

    public static func clearWatchlist(_ db: Database) throws { try db.execute(sql: "DELETE FROM watchlist") }
}
