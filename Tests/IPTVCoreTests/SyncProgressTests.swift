import Testing
import Foundation
@testable import IPTVCore

/// Collects what the progress callback is told, from any thread.
private final class Seen: @unchecked Sendable {
    private let lock = NSLock()
    private var all: [Double] = []
    func add(_ v: Double) { lock.withLock { all.append(v) } }
    var values: [Double] { lock.withLock { all } }
}

@Test func theMeterNeverGoesBackwardsAndOnlyReportsGrowth() {
    let seen = Seen()
    let m = SyncMeter { seen.add($0) }
    m.reach(0.2); m.reach(0.1); m.reach(0.2); m.advance(by: 0.2); m.reach(0.3); m.reach(5); m.advance(by: 1)
    #expect(seen.values == [0.2, 0.4, 1.0], "a smaller or equal value is not reported, and nothing passes 100%")
}

@Test func theMeterIsSafeWhenThreeDownloadsFinishAtTheSameTime() async {
    let seen = Seen()
    let m = SyncMeter { seen.add($0) }
    await withTaskGroup(of: Void.self) { g in
        for _ in 0..<3 { g.addTask { for _ in 0..<50 { m.advance(by: 0.001) } } }
    }
    let v = seen.values
    #expect(v == v.sorted() && v.count == 150 && abs((v.last ?? 0) - 0.15) < 1e-9)
}

// The network tests share the one mocked URL handler, so they live in the serial SyncTests suite.
extension SyncTests {
    @Test func anXtreamSyncReportsProgressUpToOneHundredPercent() async throws {
        let db = try AppDatabase()
        let a = try await db.dbQueue.write { d in var a = Account(name: "x", kind: .xtream, server: "http://h", username: "u"); try a.insert(d); return a }
        MockURLProtocol.handler = { r in
            let action = actionOf(r)
            let body = switch action {
            case "get_live_categories": #"[{"category_id":"5","category_name":"News"}]"#
            case "get_live_streams": #"[{"stream_id":1,"name":"News 24","category_id":"5"}]"#
            case "get_vod_categories", "get_series_categories", "get_vod_streams", "get_series": "[]"
            default: #"{"user_info":{"auth":1},"server_info":{}}"#
            }
            return (200, Data(body.utf8))
        }
        let seen = Seen()
        try await SyncService(db: db, session: mockSession()).sync(account: a, password: "p") { seen.add($0) }
        let v = seen.values
        #expect(v == v.sorted() && v.first! >= 0.05 && v.last == 1, "forward only, ending at 100%: \(v)")
        #expect(v.contains(0.05) && v.contains { abs($0 - 0.65) < 1e-9 }, "the login, then the three lists")
    }

    @Test func writingManyRowsReportsProgressInsideTheWrite() async throws {
        let db = try AppDatabase()
        let a = try await db.dbQueue.write { d in var a = Account(name: "m", kind: .m3u, url: "http://h/list.m3u"); try a.insert(d); return a }
        var text = "#EXTM3U\n"
        for i in 0..<5000 { text += "#EXTINF:-1 group-title=\"G\",Channel \(i)\nhttp://h/live/\(i).ts\n" }
        MockURLProtocol.handler = { _ in (200, Data(text.utf8)) }
        let seen = Seen()
        try await SyncService(db: db, session: mockSession()).sync(account: a, password: nil) { seen.add($0) }
        let v = seen.values
        #expect(v == v.sorted() && v.last == 1)
        #expect(v.contains(0.5) && v.contains(0.7), "downloaded, then decoded")
        #expect(v.filter { $0 > 0.7 && $0 < 1 }.count >= 2, "the write itself is counted in rows: \(v)")
    }
}
