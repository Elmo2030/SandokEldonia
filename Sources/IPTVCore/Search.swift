import Foundation
import GRDB

public struct SearchRequest {
    public var accountId: Int64?          // nil = every playlist
    public var text: String
    public var type: ItemType?
    public var categoryId: String?
    public var limit: Int
    /// Movies and series with a provider rating of at least this (0...10). A title without a rating does not pass.
    public var minRating: Double?
    /// Leaves out movies watched to the end (the same 95% as the "watched" mark). Series and channels are not affected.
    public var hideWatched: Bool
    /// Without a search text: titles a sync first saw lately come first (those with no date after them, in list order).
    public var newestFirst: Bool
    public init(accountId: Int64?, text: String = "", type: ItemType? = nil, categoryId: String? = nil, limit: Int = 5000,
                minRating: Double? = nil, hideWatched: Bool = false, newestFirst: Bool = false) {
        self.accountId = accountId; self.text = text; self.type = type; self.categoryId = categoryId; self.limit = limit
        self.minRating = minRating; self.hideWatched = hideWatched; self.newestFirst = newestFirst
    }
}

public enum Search {
    public static func run(_ db: Database, _ r: SearchRequest) throws -> [Item] {
        if r.accountId == nil, r.text.allSatisfy(\.isWhitespace) {   // browsing every playlist: each gets an equal share, or the first one fills the limit
            let ids = try Int64.fetchAll(db, sql: "SELECT DISTINCT accountId FROM item" + (r.type == nil ? "" : " WHERE type = ?") + " ORDER BY accountId",
                                         arguments: StatementArguments(r.type.map { [$0.rawValue] } ?? []))
            if ids.count > 1 {
                return try ids.flatMap { id -> [Item] in var q = r; q.accountId = id; q.limit = max(1, r.limit / ids.count); return try run(db, q) }
            }
        }
        // Every word is a prefix term; 180 of them take seconds on 100k rows and a cancelled Task cannot interrupt the SQL.
        let trimmed = r.text.split(whereSeparator: \.isWhitespace).prefix(8).joined(separator: " ")
        var sql = "SELECT item.* FROM item"
        var args: [DatabaseValueConvertible] = []
        if !trimmed.isEmpty {
            guard let pattern = FTS5Pattern(matchingAllPrefixesIn: trimmed) else { return [] }
            sql += " JOIN item_fts ON item_fts.rowid = item.id AND item_fts MATCH ?"
            args.append(pattern.rawPattern)
        }
        var conds: [String] = []
        if let a = r.accountId { conds.append("item.accountId = ?"); args.append(a) }
        if let t = r.type { conds.append("item.type = ?"); args.append(t.rawValue) }
        if let c = r.categoryId { conds.append("item.categoryId = ?"); args.append(c) }
        if let m = r.minRating { conds.append("CAST(item.rating AS REAL) >= ?"); args.append(m) }
        if r.hideWatched {
            conds.append("""
                (item.type <> 'movie' OR NOT EXISTS (SELECT 1 FROM history h WHERE h.accountId = item.accountId AND h.type = item.type
                 AND h.streamId = item.streamId AND h.duration > 0 AND h.position / h.duration > 0.95))
                """)
        }
        if !conds.isEmpty { sql += " WHERE " + conds.joined(separator: " AND ") }
        sql += trimmed.isEmpty ? (r.newestFirst ? " ORDER BY item.addedAt IS NULL, item.addedAt DESC, item.id" : " ORDER BY item.id") : " ORDER BY rank"
        sql += " LIMIT ?"; args.append(r.limit)
        return try Item.fetchAll(db, sql: sql, arguments: StatementArguments(args))
    }
}
