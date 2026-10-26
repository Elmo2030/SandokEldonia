import Testing
import Foundation
import GRDB
@testable import IPTVCore

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

private func put(_ db: AppDatabase, _ aid: Int64, _ name: String, type: ItemType = .movie, cat: String? = "5",
                 rating: String? = nil, added: Date? = nil) throws {
    try db.dbQueue.write { d in
        var i = Item(accountId: aid, type: type, name: name, streamId: name, categoryId: cat, rating: rating)
        try i.insert(d)
        try d.execute(sql: "UPDATE item SET addedAt = ? WHERE id = ?", arguments: [added, i.id])
    }
}

/// A resume point, `ago` seconds before `t0`.
private func watch(_ db: AppDatabase, _ aid: Int64, _ type: ItemType, _ sid: String, fraction: Double = 0.5, ago: Double = 0) throws {
    try db.dbQueue.write { d in
        try d.execute(sql: "INSERT OR REPLACE INTO history (accountId,type,streamId,position,duration,updated) VALUES (?,?,?,?,?,?)",
                      arguments: [aid, type.rawValue, sid, fraction * 100, 100.0, t0.addingTimeInterval(-ago)])
    }
}

private func names(_ db: AppDatabase, _ r: SearchRequest) throws -> [String] {
    try db.dbQueue.read { try Search.run($0, r) }.map(\.name)
}

@Suite struct SearchFilterTests {
    @Test func minRatingKeepsOnlyRatedTitlesAtOrAboveIt() throws {
        let (db, a) = try makeDB()
        for (n, r) in [("A", "8.1"), ("B", "6.0"), ("C", ""), ("D", nil), ("E", "7")] as [(String, String?)] { try put(db, a, n, rating: r) }
        #expect(try names(db, SearchRequest(accountId: a, type: .movie, minRating: 7)) == ["A", "E"])
        #expect(try names(db, SearchRequest(accountId: a, type: .movie)).count == 5)         // off by default
    }

    @Test func hideWatchedDropsFinishedMoviesOnly() throws {
        let (db, a) = try makeDB()
        for n in ["Done", "Half", "Fresh"] { try put(db, a, n) }
        try put(db, a, "Show", type: .series)
        try watch(db, a, .movie, "Done", fraction: 0.97); try watch(db, a, .movie, "Half", fraction: 0.5)
        try watch(db, a, .series, "Show", fraction: 0.99)
        #expect(try names(db, SearchRequest(accountId: a, type: .movie, hideWatched: true)) == ["Half", "Fresh"])
        #expect(try names(db, SearchRequest(accountId: a, type: .series, hideWatched: true)) == ["Show"])    // series are left alone
    }

    @Test func newestFirstPutsRecentlyAddedFirstAndUndatedLast() throws {
        let (db, a) = try makeDB()
        try put(db, a, "Old"); try put(db, a, "Mid", added: t0.addingTimeInterval(-86_400)); try put(db, a, "New", added: t0)
        #expect(try names(db, SearchRequest(accountId: a, type: .movie, newestFirst: true)) == ["New", "Mid", "Old"])
        #expect(try names(db, SearchRequest(accountId: a, type: .movie)) == ["Old", "Mid", "New"])              // list order otherwise
    }

    @Test func filtersCombineWithSearchText() throws {
        let (db, a) = try makeDB()
        try put(db, a, "Alpha One", rating: "9"); try put(db, a, "Alpha Two", rating: "5"); try put(db, a, "Beta", rating: "9")
        #expect(try names(db, SearchRequest(accountId: a, text: "alpha", type: .movie, minRating: 8)) == ["Alpha One"])
    }
}

@Suite struct HomeRowTests {
    @Test func continueWatchingMixedTakesMoviesAndSeriesInTurns() throws {
        let (db, a) = try makeDB()
        for n in ["m1", "m2", "m3"] { try put(db, a, n) }
        for n in ["s1", "s2"] { try put(db, a, n, type: .series) }
        try watch(db, a, .movie, "m1", ago: 10); try watch(db, a, .movie, "m2", ago: 20); try watch(db, a, .movie, "m3", ago: 30)
        try watch(db, a, .series, "s1", ago: 15); try watch(db, a, .series, "s2", ago: 25)
        let all = try db.dbQueue.read { try UserData.continueWatchingMixed($0, accountId: a) }.map(\.name)
        #expect(all == ["m1", "s1", "m2", "s2", "m3"])
        #expect(try db.dbQueue.read { try UserData.continueWatchingMixed($0, accountId: a, limit: 2) }.map(\.name) == ["m1", "s1"])
    }

    @Test func moreLikeWatchedOffersTheUnseenTitlesOfTheLastWatchedCategory() throws {
        let (db, a) = try makeDB()
        try db.dbQueue.write { d in
            var c = Category(accountId: a, type: .movie, remoteId: "5", name: "Action"); try c.insert(d)
            var o = Category(accountId: a, type: .movie, remoteId: "6", name: "Drama"); try o.insert(d)
        }
        for n in ["a1", "a2", "a3", "a4", "a5", "a6"] { try put(db, a, n, cat: "5", added: n == "a6" ? t0 : nil) }
        try put(db, a, "d1", cat: "6")
        let none = try db.dbQueue.read { try UserData.moreLikeWatched($0, accountId: a) }
        #expect(none == nil)                                              // nothing watched yet

        try watch(db, a, .movie, "d1", ago: 100); try watch(db, a, .movie, "a1", ago: 10)
        let more = try #require(try db.dbQueue.read { try UserData.moreLikeWatched($0, accountId: a) })
        #expect(more.category.name == "Action")                          // the category of what was watched last
        #expect(more.items.map(\.name) == ["a6", "a5", "a4", "a3", "a2"]) // a1 was watched; the newly added one first
    }

    @Test func moreLikeWatchedNeedsEnoughTitlesLeft() throws {
        let (db, a) = try makeDB()
        try db.dbQueue.write { d in var c = Category(accountId: a, type: .movie, remoteId: "5", name: "Action"); try c.insert(d) }
        for n in ["a1", "a2", "a3"] { try put(db, a, n) }
        try watch(db, a, .movie, "a1")
        #expect(try db.dbQueue.read { try UserData.moreLikeWatched($0, accountId: a) } == nil)       // two left: not a row
    }

    @Test func aSeriesWatchedThroughAnEpisodeCounts() throws {
        let (db, a) = try makeDB()
        try db.dbQueue.write { d in
            var c = Category(accountId: a, type: .series, remoteId: "8", name: "Drama"); try c.insert(d)
            var e = Episode(accountId: a, seriesId: "s1", season: 1, number: 1, title: "t", streamId: "900"); try e.insert(d)
        }
        for n in ["s1", "s2", "s3", "s4", "s5"] { try put(db, a, n, type: .series, cat: "8") }
        try watch(db, a, .series, "ep:900")
        let more = try #require(try db.dbQueue.read { try UserData.moreLikeWatched($0, accountId: a) })
        #expect(more.category.name == "Drama")
        #expect(Set(more.items.map(\.name)) == ["s2", "s3", "s4", "s5"])                             // s1 has a watched episode
    }
}

@Suite struct WatchlistTests {
    @Test func togglesAddsAndRemoves() throws {
        let (db, a) = try makeDB()
        #expect(try db.dbQueue.write { try UserData.toggleWatchlist($0, accountId: a, type: .movie, streamId: "9") })
        #expect(try db.dbQueue.read { try UserData.watchlistKeys($0, accountId: a) } == [UserData.favoriteKey(accountId: a, type: .movie, streamId: "9")])
        #expect(try db.dbQueue.write { try UserData.toggleWatchlist($0, accountId: a, type: .movie, streamId: "9") } == false)
        #expect(try db.dbQueue.read { try UserData.watchlistKeys($0, accountId: nil) }.isEmpty)
    }

    @Test func listsTheLatestFirstPerTypeAndSkipsDroppedTitles() throws {
        let (db, a) = try makeDB()
        for n in ["old", "new", "gone"] { try put(db, a, n) }
        try put(db, a, "show", type: .series)
        try db.dbQueue.write { d in
            for (n, t, ago) in [("old", "movie", 300.0), ("new", "movie", 10.0), ("gone", "movie", 5.0), ("show", "series", 1.0)] {
                try d.execute(sql: "INSERT INTO watchlist (accountId,type,streamId,added) VALUES (?,?,?,?)", arguments: [a, t, n, t0.addingTimeInterval(-ago)])
            }
            try d.execute(sql: "DELETE FROM item WHERE name = 'gone'")
        }
        #expect(try db.dbQueue.read { try UserData.watchlist($0, accountId: a, type: .movie) }.map(\.name) == ["new", "old"])
        #expect(try db.dbQueue.read { try UserData.watchlist($0, accountId: a, type: .series) }.map(\.name) == ["show"])
    }

    @Test func goesWithTheBackupAndOldBackupsStillRead() throws {
        let (db, a) = try makeDB()
        let plain = try db.dbQueue.read { try Backup.make($0) }
        #expect(!String(decoding: try plain.encoded(), as: UTF8.self).contains("watchlist"))           // nothing set aside: the key is absent
        _ = try Backup.decode(try plain.encoded())

        _ = try db.dbQueue.write { try UserData.toggleWatchlist($0, accountId: a, type: .movie, streamId: "9") }
        let backup = try db.dbQueue.read { try Backup.make($0) }
        #expect(backup.playlists[0].watchlist == [.init(type: .movie, streamId: "9")])

        let fresh = try AppDatabase()
        try fresh.dbQueue.write { try Backup.decode(try backup.encoded()).merge(into: $0) }
        #expect(try fresh.dbQueue.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM watchlist") } == 1)
    }

    @Test func leavesWithItsPlaylist() throws {
        let (db, a) = try makeDB()
        _ = try db.dbQueue.write { try UserData.toggleWatchlist($0, accountId: a, type: .movie, streamId: "9") }
        try db.dbQueue.write { try $0.execute(sql: "DELETE FROM account WHERE id = ?", arguments: [a]) }
        #expect(try db.dbQueue.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM watchlist") } == 0)
    }
}

@Suite struct ExpiryWarningTests {
    private func info(days: Double) -> SubscriptionInfo { SubscriptionInfo(expires: t0.addingTimeInterval(days * 86_400)) }

    @Test func picksTheEarliestEndingOneAmongThoseWithinAWeek() {
        let list = [("Calm", info(days: 30)), ("Soon", info(days: 3)), ("Over", info(days: -2)), ("NoDate", SubscriptionInfo())]
        #expect(SubscriptionInfo.mostUrgent(list, now: t0)?.name == "Over")
        #expect(SubscriptionInfo.mostUrgent(Array(list[..<2]), now: t0)?.name == "Soon")
    }

    @Test func staysQuietWhenNothingIsNear() {
        #expect(SubscriptionInfo.mostUrgent([("Calm", info(days: 30)), ("NoDate", SubscriptionInfo())], now: t0) == nil)
        #expect(SubscriptionInfo.mostUrgent([], now: t0) == nil)
    }
}
