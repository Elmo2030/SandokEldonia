import Testing
import Foundation
import GRDB
@testable import IPTVCore

@Suite struct RatingTests {
    @Test func readsTheScalesPanelsUse() {
        #expect(Rating.value(rating: "7.5") == 7.5)
        #expect(Rating.value(rating: "7,5") == 7.5)                      // a decimal comma
        #expect(Rating.value(rating: "8") == 8)
        #expect(Rating.value(rating: "75") == 7.5)                       // 0-100
        #expect(Rating.value(rating: "7.46") == 7.5)                     // one decimal
        #expect(Rating.value(rating: "8.1/10") == 8.1)
    }

    @Test func treatsUnratedAndNonsenseAsNoRating() {
        for raw in [nil, "", "0", "0.0", "n/a", "-3", "250", " "] as [String?] { #expect(Rating.value(rating: raw) == nil, "\(raw ?? "nil")") }
    }

    @Test func fallsBackToTheFiveStarFieldOnlyWhenTheMainOneIsEmpty() {
        #expect(Rating.value(rating: "", fiveBased: "3.75") == 7.5)
        #expect(Rating.value(rating: "0", fiveBased: "4") == 8)
        #expect(Rating.value(rating: "6", fiveBased: "4") == 6)
        #expect(Rating.value(rating: "", fiveBased: "9") == nil)         // not a 0-5 number
    }

    @Test func storesTheNormalizedNumberAndTheItemReadsItBack() {
        #expect(Rating.stored(rating: "75") == "7.5")
        #expect(Rating.stored(rating: "0") == nil)
        let item = Item(accountId: 1, type: .movie, name: "x", streamId: "1", rating: Rating.stored(rating: "", fiveBased: "4.5"))
        #expect(item.ratingValue == 9)
        #expect(Item(accountId: 1, type: .live, name: "x", streamId: "1").ratingValue == nil)
    }
}

extension SyncTests {
    @Test func syncKeepsOneScaleForTheRatingAndTheFilterUsesIt() async throws {
        let db = try AppDatabase(); let a = try account(db)
        let vodJSON = #"[{"stream_id":1,"name":"Ten","rating":"8.4"},{"stream_id":2,"name":"Hundred","rating":"75"},{"stream_id":3,"name":"Five","rating":"0","rating_5based":3},{"stream_id":4,"name":"None","rating":""}]"#
        MockURLProtocol.handler = { r in actionOf(r) == "get_vod_streams" ? (200, Data(vodJSON.utf8)) : (200, Data(self.body(actionOf(r)).utf8)) }
        try await SyncService(db: db, session: mockSession()).sync(account: a, password: "p")
        let items = try await db.dbQueue.read { try Item.filter(Column("type") == "movie").fetchAll($0) }
        #expect(Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.ratingValue) }) == ["Ten": 8.4, "Hundred": 7.5, "Five": 6, "None": nil])
        let top = try await db.dbQueue.read { try Search.run($0, SearchRequest(accountId: a.id, type: .movie, minRating: 7)) }.map(\.name)
        #expect(Set(top) == ["Ten", "Hundred"])                          // the 0-100 panel's 75 passes a "7+" filter as 7.5
    }
}
