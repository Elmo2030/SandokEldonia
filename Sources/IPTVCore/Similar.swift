import Foundation
import GRDB

/// "Similar titles", worked out on the device from the names alone: sequels, remakes, the same franchise or the same words in the title.
/// No account, service or model is involved, so it is as good as the names in the playlist (and says nothing a name does not).
public enum Similar {
    /// The words of a title that say what it is: lower case, accents folded, without the year, quality tags, playlist prefixes
    /// ("AR |", "EN:") and the filler words of a few languages.
    public static func tokens(_ name: String) -> Set<String> {
        let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
        let words = folded.split { !($0.isLetter || $0.isNumber) }.map(String.init)
        return Set(words.filter { w in
            w.count >= 2 && !stop.contains(w) && !(w.count == 4 && w.allSatisfy(\.isNumber) && (w.hasPrefix("19") || w.hasPrefix("20")))
        })
    }

    private static let stop: Set<String> = [
        "the", "of", "and", "a", "an", "in", "on", "to", "for", "with", "part", "vol", "season", "episode", "s01", "e01",
        "hd", "fhd", "uhd", "4k", "sd", "hdr", "1080p", "720p", "2160p", "480p", "x264", "x265", "hevc", "bluray", "web", "dl", "cam",
        "en", "ar", "fr", "de", "es", "tr", "us", "uk", "multi", "sub", "subs", "dub", "dubbed", "vf", "vostfr",
        "من", "في", "على", "الى", "إلى", "عن", "مع", "و", "مترجم", "مدبلج", "فيلم", "مسلسل",
        "le", "la", "les", "du", "des", "el", "los", "las", "der", "die", "das", "il", "di",
    ]

    /// 0...1: the share of the words two titles have in common (Jaccard).
    public static func score(_ a: Set<String>, _ b: Set<String>) -> Double {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        return Double(a.intersection(b).count) / Double(a.union(b).count)
    }

    /// Titles of the same kind (movie or series) in the same playlist that share words with `item`, best first. Titles already
    /// watched and `item` itself are left out; a title in the same category gets a small bonus. Nothing under `threshold` is offered.
    public static func titles(like item: Item, in db: Database, limit: Int = 24, threshold: Double = 0.34) throws -> [Item] {
        let mine = tokens(item.name)
        guard !mine.isEmpty, item.type != .live else { return [] }
        // The search index narrows 100k titles to the 600 that match best (a common word matches thousands); the scoring is done on those.
        guard let pattern = FTS5Pattern(matchingAnyTokenIn: mine.sorted().prefix(8).joined(separator: " ")) else { return [] }
        let candidates = try Item.fetchAll(db, sql: """
            SELECT item.* FROM item JOIN item_fts ON item_fts.rowid = item.id AND item_fts MATCH ?
            WHERE item.accountId = ? AND item.type = ? AND item.id <> ?
              AND NOT EXISTS (SELECT 1 FROM history h WHERE h.accountId = item.accountId AND h.type = item.type AND h.streamId = item.streamId)
            ORDER BY rank LIMIT 600
            """, arguments: [pattern.rawPattern, item.accountId, item.type.rawValue, item.id ?? -1])
        var scored: [(item: Item, score: Double)] = []
        for c in candidates {
            var s = score(mine, tokens(c.name))
            if c.categoryId != nil, c.categoryId == item.categoryId { s += 0.1 }
            if s >= threshold { scored.append((c, s)) }
        }
        scored.sort { a, b in
            if a.score != b.score { return a.score > b.score }
            return (a.item.id ?? 0) < (b.item.id ?? 0)
        }
        return scored.prefix(limit).map { $0.item }
    }
}
