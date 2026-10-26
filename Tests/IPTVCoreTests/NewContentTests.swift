import Testing
import Foundation
import GRDB
@testable import IPTVCore

// Same suite as SyncTests: MockURLProtocol.handler is global, so network tests must run serially together.
extension SyncTests {
    private func vodJSON(_ ids: [Int]) -> String {
        "[" + ids.map { #"{"stream_id":\#($0),"name":"Movie \#($0)","category_id":"7"}"# }.joined(separator: ",") + "]"
    }

    /// Serves `ids` as the movie list (live and series stay as in the other tests).
    private func serve(movies ids: [Int]) {
        MockURLProtocol.handler = { r in
            actionOf(r) == "get_vod_streams" ? (200, Data(self.vodJSON(ids).utf8)) : (200, Data(self.body(actionOf(r)).utf8))
        }
    }

    private func addedAt(_ db: AppDatabase, _ sid: String) throws -> Date? {
        try db.dbQueue.read { try Date.fetchOne($0, sql: "SELECT addedAt FROM item WHERE type = 'movie' AND streamId = ?", arguments: [sid]) }
    }

    @Test func firstSyncOfAPlaylistIsTheBaseline() async throws {
        let db = try AppDatabase(); let a = try account(db)
        serve(movies: [1, 2, 3])
        let r = try await SyncService(db: db, session: mockSession()).sync(account: a, password: "p")
        #expect(r.newCounts.isEmpty)
        let stamped = try await db.dbQueue.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM item WHERE addedAt IS NOT NULL") }
        #expect(stamped == 0)
    }

    @Test func laterSyncCountsAndStampsOnlyTheNewTitles() async throws {
        let db = try AppDatabase(); let a = try account(db)
        let svc = SyncService(db: db, session: mockSession())
        serve(movies: [1, 2, 3])
        try await svc.sync(account: a, password: "p")
        let t = Date(timeIntervalSince1970: 1_800_000_000)
        serve(movies: [1, 2, 3, 4, 5])
        let r = try await svc.sync(account: a, password: "p", now: t)
        #expect(r.newCounts == [.movie: 2])                               // live and series did not change
        #expect(try addedAt(db, "4") == t); #expect(try addedAt(db, "5") == t)
        #expect(try addedAt(db, "1") == nil)

        // A third sync with nothing new reports nothing and keeps the stamps.
        let r3 = try await svc.sync(account: a, password: "p", now: t.addingTimeInterval(3600))
        #expect(r3.newCounts.isEmpty)
        #expect(try addedAt(db, "4") == t)
    }

    @Test func removedAndReturnedTitleCountsAsNewAgain() async throws {
        let db = try AppDatabase(); let a = try account(db)
        let svc = SyncService(db: db, session: mockSession())
        serve(movies: [1, 2]); try await svc.sync(account: a, password: "p")
        serve(movies: [1]); try await svc.sync(account: a, password: "p")
        serve(movies: [1, 2])
        let r = try await svc.sync(account: a, password: "p", now: Date(timeIntervalSince1970: 1_800_000_000))
        #expect(r.newCounts == [.movie: 1])
    }

    @Test func aRenumberedCatalogIsNotReportedAsNew() async throws {
        let db = try AppDatabase(); let a = try account(db)
        let svc = SyncService(db: db, session: mockSession())
        serve(movies: Array(1...300)); try await svc.sync(account: a, password: "p")
        serve(movies: Array(1001...1300))                                  // every id changed: a panel rebuild, not 300 new films
        let r = try await svc.sync(account: a, password: "p")
        #expect(r.newCounts.isEmpty)
        let stamped = try await db.dbQueue.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM item WHERE addedAt IS NOT NULL") }
        #expect(stamped == 0)
    }

    @Test func aSmallCatalogGrowingFastIsStillNew() async throws {
        let db = try AppDatabase(); let a = try account(db)
        let svc = SyncService(db: db, session: mockSession())
        serve(movies: [1, 2]); try await svc.sync(account: a, password: "p")
        serve(movies: [1, 2, 3, 4, 5, 6])                                  // 4 of 2 before: over half, but far below the renumber floor
        let r = try await svc.sync(account: a, password: "p")
        #expect(r.newCounts == [.movie: 4])
    }

    @Test func aFailedSyncChangesNothing() async throws {
        let db = try AppDatabase(); let a = try account(db)
        let svc = SyncService(db: db, session: mockSession())
        serve(movies: [1, 2]); try await svc.sync(account: a, password: "p")
        serve(movies: [1, 2, 3]); try await svc.sync(account: a, password: "p", now: Date(timeIntervalSince1970: 1_800_000_000))
        MockURLProtocol.handler = { _ in (500, Data()) }
        await #expect(throws: (any Error).self) { try await svc.sync(account: a, password: "p") }
        #expect(try addedAt(db, "3") == Date(timeIntervalSince1970: 1_800_000_000))
    }

    @Test func m3uNewLinkIsNewAndTheFirstSyncIsNot() async throws {
        let db = try AppDatabase(); let a = try m3uAccount(db)
        let svc = SyncService(db: db, session: mockSession())
        MockURLProtocol.handler = { _ in (200, Data(self.playlist.utf8)) }
        #expect(try await svc.sync(account: a, password: nil).newCounts.isEmpty)
        let more = self.playlist + "\r\n#EXTINF:-1 group-title=\"Movies\",Fresh Film\r\nhttp://h/movie/u/p/10.mkv\r\n"
        MockURLProtocol.handler = { _ in (200, Data(more.utf8)) }
        #expect(try await svc.sync(account: a, password: nil).newCounts == [.movie: 1])
    }

    @Test func eachPlaylistIsComparedOnlyWithItself() async throws {
        let db = try AppDatabase(); let a = try account(db)
        let b = try await db.dbQueue.write { d -> Account in var x = Account(name: "y", kind: .xtream, server: "http://h2", username: "u"); try x.insert(d); return x }
        let svc = SyncService(db: db, session: mockSession())
        serve(movies: [1, 2]); try await svc.sync(account: a, password: "p")
        serve(movies: [1, 2, 3])                                           // playlist B has never synced: id 3 is not "new" there
        let r = try await svc.sync(account: b, password: "p")
        #expect(r.newCounts.isEmpty)
    }
}

@Suite struct RecentlyAddedTests {
    private func stamp(_ db: AppDatabase, _ aid: Int64, _ name: String, type: ItemType = .movie, at date: Date?) throws {
        try db.dbQueue.write { d in
            var i = Item(accountId: aid, type: type, name: name, streamId: name, categoryId: "1")
            try i.insert(d)
            try d.execute(sql: "UPDATE item SET addedAt = ? WHERE id = ?", arguments: [date, i.id])
        }
    }

    @Test func listsTheLastFourteenDaysNewestFirstAndSkipsUndatedAndLive() throws {
        let (db, a) = try makeDB()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        try stamp(db, a, "old", at: now.addingTimeInterval(-15 * 86_400))
        try stamp(db, a, "undated", at: nil)
        try stamp(db, a, "mid", at: now.addingTimeInterval(-3 * 86_400))
        try stamp(db, a, "newest", type: .series, at: now.addingTimeInterval(-3600))
        try stamp(db, a, "channel", type: .live, at: now.addingTimeInterval(-60))
        let names = try db.dbQueue.read { try UserData.recentlyAdded($0, accountId: a, now: now) }.map(\.name)
        #expect(names == ["newest", "mid"])
    }

    @Test func canBeLimitedToOnePlaylist() throws {
        let (db, a) = try makeDB(); let b = try addAccount(db, "other")
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        try stamp(db, a, "A film", at: now.addingTimeInterval(-60))
        try stamp(db, b, "B film", at: now.addingTimeInterval(-30))
        #expect(try db.dbQueue.read { try UserData.recentlyAdded($0, accountId: a, now: now) }.map(\.name) == ["A film"])
        #expect(try db.dbQueue.read { try UserData.recentlyAdded($0, accountId: nil, now: now) }.map(\.name) == ["B film", "A film"])
    }

    @Test func migrationKeepsExistingRowsUndated() throws {
        let queue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(queue, upTo: "v4-item-info")
        try queue.write { d in
            try d.execute(sql: "INSERT INTO account (name, kind) VALUES ('t', 'm3u')")
            try d.execute(sql: "INSERT INTO item (accountId, type, name, streamId) VALUES (1, 'movie', 'Old', 'o')")
        }
        try AppDatabase.migrator.migrate(queue)
        let row = try queue.read { try Row.fetchOne($0, sql: "SELECT name, addedAt FROM item") }
        #expect(row?["name"] as String? == "Old")
        #expect(row?["addedAt"] as Date? == nil)
    }
}
