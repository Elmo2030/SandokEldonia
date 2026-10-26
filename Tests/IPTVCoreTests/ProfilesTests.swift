import Testing
import Foundation
import GRDB
@testable import IPTVCore

private func add(_ db: AppDatabase, _ aid: Int64, _ name: String, type: ItemType = .movie, cat: String? = "1") throws {
    try db.dbQueue.write { d in var i = Item(accountId: aid, type: type, name: name, streamId: name, categoryId: cat); try i.insert(d) }
}

@Suite struct ProfilesTests {
    @Test func startsWithOneMainProfileInUse() throws {
        let (db, _) = try makeDB()
        let all = try db.dbQueue.read { try Profiles.all($0) }
        #expect(all.map(\.name) == ["Main"])
        #expect(try db.dbQueue.read { try Profiles.current($0) }.id == all[0].id)
    }

    @Test func favoritesHistoryAndWatchLaterBelongToTheProfileInUse() throws {
        let (db, a) = try makeDB()
        try add(db, a, "Film")
        let kid = try db.dbQueue.write { try Profiles.create($0, name: "Sara", kids: true) }
        try db.dbQueue.write { d in
            _ = try UserData.toggleFavorite(d, accountId: a, type: .movie, streamId: "Film")
            _ = try UserData.toggleWatchlist(d, accountId: a, type: .movie, streamId: "Film")
            try UserData.saveProgress(d, accountId: a, type: .movie, streamId: "Film", position: 50, duration: 100)
        }
        try db.dbQueue.write { try Profiles.switchTo($0, id: kid.id!) }
        // Sara sees none of it ...
        #expect(try db.dbQueue.read { try UserData.favoriteKeys($0, accountId: nil) }.isEmpty)
        #expect(try db.dbQueue.read { try UserData.watchlistKeys($0, accountId: nil) }.isEmpty)
        #expect(try db.dbQueue.read { try UserData.progress($0, accountId: a, type: .movie, streamId: "Film") } == nil)
        #expect(try db.dbQueue.read { try UserData.continueWatching($0, accountId: a, type: .movie) }.isEmpty)
        // ... and her own marks do not reach Main.
        _ = try db.dbQueue.write { try UserData.toggleFavorite($0, accountId: a, type: .movie, streamId: "Film") }
        try db.dbQueue.write { try UserData.saveProgress($0, accountId: a, type: .movie, streamId: "Film", position: 80, duration: 100) }
        try db.dbQueue.write { try Profiles.switchTo($0, id: 1) }
        #expect(try db.dbQueue.read { try UserData.favoriteKeys($0, accountId: nil) }.count == 1)
        #expect(try db.dbQueue.read { try UserData.progress($0, accountId: a, type: .movie, streamId: "Film") } == 50)
        #expect(try db.dbQueue.read { try UserData.watchlistKeys($0, accountId: nil) }.count == 1)
    }

    @Test func deletingAProfileTakesItsDataAndNeverTheLastOrCurrentOne() throws {
        let (db, a) = try makeDB()
        let other = try db.dbQueue.write { try Profiles.create($0, name: "Other", kids: false) }
        try db.dbQueue.write { try Profiles.switchTo($0, id: other.id!) }
        _ = try db.dbQueue.write { try UserData.toggleFavorite($0, accountId: a, type: .movie, streamId: "x") }
        #expect(throws: ProfileError.cannotDelete) { try db.dbQueue.write { try Profiles.delete($0, id: other.id!) } }     // in use
        try db.dbQueue.write { try Profiles.switchTo($0, id: 1) }
        try db.dbQueue.write { try Profiles.delete($0, id: other.id!) }
        #expect(try db.dbQueue.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM favorite_all") } == 0)
        #expect(throws: ProfileError.cannotDelete) { try db.dbQueue.write { try Profiles.delete($0, id: 1) } }               // the last one
    }

    @Test func namesAreCheckedAndTheNumberOfProfilesIsLimited() throws {
        let (db, _) = try makeDB()
        #expect(throws: ProfileError.invalidName) { try db.dbQueue.write { try Profiles.create($0, name: "   ", kids: false) } }
        let long = try db.dbQueue.write { try Profiles.create($0, name: String(repeating: "x", count: 99), kids: false) }
        #expect(long.name.count == Profiles.maxNameLength)
        for i in 0..<(Profiles.maxCount - 2) { try db.dbQueue.write { _ = try Profiles.create($0, name: "P\(i)", kids: false) } }
        #expect(throws: ProfileError.tooMany) { try db.dbQueue.write { try Profiles.create($0, name: "One too many", kids: false) } }
    }

    @Test func aPinIsStoredHashedAndChecked() throws {
        let (db, _) = try makeDB()
        try db.dbQueue.write { try Profiles.setPIN($0, id: 1, pin: "4821") }
        let p = try db.dbQueue.read { try Profiles.current($0) }
        #expect(p.hasPIN); #expect(!(p.pin ?? "").contains("4821"))
        #expect(Profiles.accepts(p, pin: "4821")); #expect(!Profiles.accepts(p, pin: "1234")); #expect(!Profiles.accepts(p, pin: nil))
        for bad in ["123", "123456789", "12a4", "١٢٣٤"] {
            #expect(throws: ProfileError.invalidPIN, "\(bad)") { try db.dbQueue.write { try Profiles.setPIN($0, id: 1, pin: bad) } }
        }
        try db.dbQueue.write { try Profiles.setPIN($0, id: 1, pin: nil) }
        #expect(Profiles.accepts(try db.dbQueue.read { try Profiles.current($0) }, pin: nil))
    }

    @Test func theKidsFilterShowsOnlyCategoriesMadeForChildren() throws {
        let (db, a) = try makeDB()
        try db.dbQueue.write { d in
            for (id, name) in [("1", "Kids Cartoons"), ("2", "Action Movies"), ("3", "أفلام أطفال"), ("4", "Family")] {
                var c = Category(accountId: a, type: .movie, remoteId: id, name: name); try c.insert(d)
            }
        }
        try add(db, a, "Toy Story", cat: "1"); try add(db, a, "Die Hard", cat: "2"); try add(db, a, "Frozen", cat: "3")
        try add(db, a, "Shrek", cat: "4"); try add(db, a, "Loose", cat: nil)
        let all = try db.dbQueue.read { try Item.fetchAll($0) }
        let shown = try db.dbQueue.read { try CategoryFilter.kids.visible(all, in: $0) }.map(\.name)
        #expect(Set(shown) == ["Toy Story", "Frozen", "Shrek"])
        #expect(CategoryFilter.kids.visible([Category(accountId: a, type: .movie, remoteId: "1", name: "Sports"), Category(accountId: a, type: .movie, remoteId: "2", name: "Kids")]).map(\.name) == ["Kids"])
        #expect(try db.dbQueue.read { try CategoryFilter("").visible(all, in: $0) }.count == 5)           // the ordinary filter is unchanged
    }

    @Test func withoutAnyCategoryTheKidsFilterShowsNothing() throws {
        let (db, a) = try makeDB()
        try add(db, a, "Whatever", cat: "9")
        #expect(try db.dbQueue.read { try CategoryFilter.kids.visible(try Item.fetchAll($0), in: $0) }.isEmpty)
    }

    @Test func existingDataMovesToTheMainProfileInTheMigration() throws {
        let queue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(queue, upTo: "v7-guide")
        try queue.write { d in
            try d.execute(sql: "INSERT INTO account (id, name, kind) VALUES (1, 'a', 'm3u')")
            try d.execute(sql: "INSERT INTO favorite VALUES (1, 'movie', 'f1'), (99, 'movie', 'orphan')")        // 99: a playlist that is gone
            try d.execute(sql: "INSERT INTO history VALUES (1, 'movie', 'h1', 10, 100, '2026-01-01 10:00:00')")
            try d.execute(sql: "INSERT INTO watchlist (accountId,type,streamId) VALUES (1, 'movie', 'w1')")
        }
        try AppDatabase.migrator.migrate(queue)
        let seen = try queue.read { d in
            (name: try Profiles.current(d).name, favorites: try UserData.favoriteKeys(d, accountId: nil),
             progress: try UserData.progress(d, accountId: 1, type: .movie, streamId: "h1"), watchLater: try UserData.watchlistKeys(d, accountId: nil))
        }
        #expect(seen.name == "Main")
        #expect(seen.favorites == [UserData.favoriteKey(accountId: 1, type: .movie, streamId: "f1")])      // the orphan row is not carried over
        #expect(seen.progress == 10)
        #expect(seen.watchLater.count == 1)
    }
}

@Suite struct SimilarTitlesTests {
    @Test func tokensKeepTheWordsThatNameTheTitle() {
        #expect(Similar.tokens("AR | Fast & Furious 6 (2013) 4K") == ["fast", "furious"])      // prefix, year, quality and a lone sequel digit are not the title
        #expect(Similar.tokens("Amélie") == ["amelie"])
        #expect(Similar.tokens("") .isEmpty)
        #expect(Similar.tokens("The Movie 2020").contains("movie"))
    }

    @Test func scoreIsTheShareOfWordsInCommon() {
        #expect(Similar.score(["a", "b"], ["a", "b"]) == 1)
        #expect(Similar.score(["a", "b"], ["b", "c"]) == 1.0 / 3.0)
        #expect(Similar.score([], ["a"]) == 0)
    }

    @Test func offersTheNearestNamesAndLeavesOutTheWatchedTheUnrelatedAndOtherKinds() throws {
        let (db, a) = try makeDB()
        try add(db, a, "Fast & Furious", cat: "1")
        try add(db, a, "Fast & Furious 6", cat: "1")
        try add(db, a, "AR | Furious Fast 7 (2015) 4K", cat: "2")
        try add(db, a, "Fast Cars", cat: "2")                                    // one word of two: under the threshold
        try add(db, a, "Cooking Show", cat: "1")
        try add(db, a, "Fast & Furious 8", cat: "1")
        try add(db, a, "Fast & Furious Show", type: .series, cat: "1")
        try db.dbQueue.write { try UserData.saveProgress($0, accountId: a, type: .movie, streamId: "Fast & Furious 8", position: 5, duration: 100) }
        let base = try #require(try db.dbQueue.read { try Item.filter(Column("name") == "Fast & Furious").fetchOne($0) })
        let names = try db.dbQueue.read { try Similar.titles(like: base, in: $0) }.map(\.name)
        #expect(names == ["Fast & Furious 6", "AR | Furious Fast 7 (2015) 4K"])
    }

    @Test func aChannelOrANameWithoutWordsHasNoSimilarTitles() throws {
        let (db, a) = try makeDB()
        try add(db, a, "News", type: .live)
        try add(db, a, "4K", cat: "1")
        #expect(try db.dbQueue.read { d in try Similar.titles(like: try #require(try Item.filter(Column("name") == "News").fetchOne(d)), in: d) }.isEmpty)
        #expect(try db.dbQueue.read { d in try Similar.titles(like: try #require(try Item.filter(Column("name") == "4K").fetchOne(d)), in: d) }.isEmpty)
    }

    @Test func theLastWatchedTitleIsTheOneToCompareWith() throws {
        let (db, a) = try makeDB()
        try add(db, a, "Alpha"); try add(db, a, "Beta")
        try db.dbQueue.write { d in
            try d.execute(sql: "INSERT INTO history VALUES (?, 'movie', 'Alpha', 1, 10, '2026-01-02 10:00:00'), (?, 'movie', 'Beta', 1, 10, '2026-01-01 10:00:00')", arguments: [a, a])
        }
        #expect(try db.dbQueue.read { try UserData.lastWatchedTitle($0, accountId: a) }?.name == "Alpha")
        #expect(try makeDB().0.dbQueue.read { try UserData.lastWatchedTitle($0, accountId: nil) } == nil)
    }
}
