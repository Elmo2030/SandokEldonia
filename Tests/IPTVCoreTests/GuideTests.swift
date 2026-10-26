import Testing
import Foundation
import GRDB
@testable import IPTVCore

private let now = Date(timeIntervalSince1970: 1_793_000_000)      // 2026-10-26 06:13 UTC

private func xml(_ programmes: String) -> Data {
    Data(#"<?xml version="1.0" encoding="UTF-8"?><tv><channel id="a"><display-name>A</display-name></channel>\#(programmes)</tv>"#.utf8)
}

private func prog(_ channel: String, _ title: String, start: Date, hours: Double = 1) -> String {
    func f(_ d: Date) -> String {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: d)
        return String(format: "%04d%02d%02d%02d%02d%02d +0000", c.year!, c.month!, c.day!, c.hour!, c.minute!, c.second!)
    }
    return #"<programme start="\#(f(start))" stop="\#(f(start.addingTimeInterval(hours * 3600)))" channel="\#(channel)"><title>\#(title)</title></programme>"#
}

@Suite struct XMLTVTests {
    @Test func readsDatesWithAndWithoutAnOffset() {
        #expect(XMLTVParser.date("20261026120000 +0200") == XMLTVParser.date("20261026100000"))
        #expect(XMLTVParser.date("20261026120000 -0530") == XMLTVParser.date("20261026173000 +0000"))
        #expect(XMLTVParser.date("202610261200") == XMLTVParser.date("20261026120000"))           // seconds are optional
        for bad in ["", "2026", "20261326120000", "20261026250000", "abcdefghijklmn", "20261026120000 +02"] {
            if bad == "20261026120000 +02" { #expect(XMLTVParser.date(bad) == XMLTVParser.date("20261026120000")) }   // an odd offset is ignored
            else { #expect(XMLTVParser.date(bad) == nil, "\(bad)") }
        }
    }

    @Test func keepsOnlyWantedChannelsInTheWindow() {
        let data = xml([
            prog("a", "On now", start: now.addingTimeInterval(-1800)),
            prog("a", "Next", start: now.addingTimeInterval(1800)),
            prog("a", "Long gone", start: now.addingTimeInterval(-6 * 3600)),
            prog("a", "Far ahead", start: now.addingTimeInterval(5 * 86_400)),
            prog("other", "Not ours", start: now),
        ].joined())
        let list = XMLTVParser.parse(data, wanted: ["a"], now: now)
        #expect(list.map(\.title) == ["On now", "Next"])
        #expect(list.allSatisfy { $0.channel == "a" })
    }

    @Test func cleansTitlesAndSkipsBrokenProgrammes() {
        let data = xml(#"""
            <programme start="20261026060000 +0000" stop="20261026070000 +0000" channel="a"><title>  Good&#x0;Show  </title></programme>
            <programme start="nonsense" stop="20261026070000 +0000" channel="a"><title>Bad start</title></programme>
            <programme start="20261026070000 +0000" stop="20261026060000 +0000" channel="a"><title>Ends before it starts</title></programme>
            <programme start="20261026060000 +0000" stop="20261026070000 +0000" channel="a"></programme>
            """#)
        #expect(XMLTVParser.parse(data, wanted: ["a"], now: now).map(\.title).count <= 1)
        #expect(!XMLTVParser.parse(data, wanted: ["a"], now: now).contains { $0.title.contains("\u{0}") })
        #expect(XMLTVParser.parse(Data("not xml at all".utf8), wanted: ["a"], now: now).isEmpty)
    }

    @Test func readsAGzipFileWithAndWithoutAFileName() throws {
        let plain = "H4sIAAAAAAAC/1WPwQrCMAyG7z5FyVXmugnioetuHnfSByhbmIU2HW2Z+vZmOmQGQuD/yZ8vqn16J2aMyQZqoDpIEEh9GCyNDdyul+IMrd6pPGvV3w0ROmGHBggf6VCBVoNNkzOvgoxH3bGqyj9Jlesah0wxjNF4jyJlE3MDtaxP1dK15BJ7yRPYDNPGO269NWwDkG12KJxZeJFAdyGQ+IJ8LCb43WWGkj95A82xfIz1AAAA"
        let named = "H4sICAAAAAAC/2d1aWRlLnhtbABVj8EKwjAMhu8+RclV5roJ4qHrbh530gcoW5iFNh1tmfr2ZjpkBkLg/8mfL6p9eidmjMkGaqA6SBBIfRgsjQ3crpfiDK3eqTxr1d8NETphhwYIH+lQgVaDTZMzr4KMR92xqso/SZXrGodMMYzReI8iZRNzA7WsT9XSteQSe8kT2AzTxjtuvTVsA5BtdiicWXiRQHchkPiCfCwm+N1lhpI/eQPNsXyM9QAAAA=="
        for b64 in [plain, named] {
            let text = String(decoding: try Gzip.inflate(Data(base64Encoded: b64)!, maxBytes: 100_000), as: UTF8.self)
            #expect(text.contains("Noon News"))
        }
        let raw = Data("<tv/>".utf8)
        #expect(try Gzip.inflate(raw, maxBytes: 10) == raw)                         // not gzip: returned as it is
    }

    @Test func refusesAGzipThatInflatesPastTheLimitOrIsCutShort() throws {
        let gz = Data(base64Encoded: "H4sIAAAAAAAC/1WPwQrCMAyG7z5FyVXmugnioetuHnfSByhbmIU2HW2Z+vZmOmQGQuD/yZ8vqn16J2aMyQZqoDpIEEh9GCyNDdyul+IMrd6pPGvV3w0ROmGHBggf6VCBVoNNkzOvgoxH3bGqyj9Jlesah0wxjNF4jyJlE3MDtaxP1dK15BJ7yRPYDNPGO269NWwDkG12KJxZeJFAdyGQ+IJ8LCb43WWGkj95A82xfIz1AAAA")!
        #expect(throws: (any Error).self) { try Gzip.inflate(gz, maxBytes: 20) }
        #expect(throws: (any Error).self) { try Gzip.inflate(gz.prefix(12), maxBytes: 100_000) }
    }

    @Test func findsTheGuideLinkInAPlaylistHeader() {
        #expect(M3UParser.guideURL(inHeader: #"#EXTM3U url-tvg="http://g.example/epg.xml.gz""#) == "http://g.example/epg.xml.gz")
        #expect(M3UParser.guideURL(inHeader: #"#EXTM3U x-tvg-url="https://a.example/1.xml, https://b.example/2.xml""#) == "https://a.example/1.xml")
        #expect(M3UParser.guideURL(inHeader: #"#EXTM3U url-tvg="file:///etc/passwd,http://ok.example/g.xml""#) == "http://ok.example/g.xml")
        #expect(M3UParser.guideURL(inHeader: #"#EXTM3U url-tvg="ftp://x/y""#) == nil)
        #expect(M3UParser.guideURL(inHeader: "#EXTM3U") == nil)
    }
}

// Same suite as SyncTests: MockURLProtocol.handler is global, so network tests must run serially together.
extension SyncTests {
    private func guidePlaylist(_ guide: String?) -> String {
        "#EXTM3U\(guide.map { #" url-tvg="\#($0)""# } ?? "")\r\n#EXTINF:-1 tvg-id=\"a\" group-title=\"News\",One\r\nhttp://h/live/1.ts\r\n"
    }

    private func guideAccount(_ db: AppDatabase) throws -> Account {
        try db.dbQueue.write { d in var a = Account(name: "m", kind: .m3u, url: "http://h/list.m3u"); try a.insert(d); return a }
    }

    @Test func syncRemembersTheGuideLinkAndTheGuideServesNowAndNext() async throws {
        let db = try AppDatabase(); let a = try guideAccount(db)
        let guide = xml([prog("a", "Now show", start: now.addingTimeInterval(-600)), prog("a", "Later show", start: now.addingTimeInterval(3000))].joined())
        MockURLProtocol.handler = { r in
            r.url!.host == "g.example" ? (200, guide) : (200, Data(self.guidePlaylist("http://g.example/epg.xml").utf8))
        }
        try await SyncService(db: db, session: mockSession()).sync(account: a, password: nil)
        #expect(try await db.dbQueue.read { try String.fetchOne($0, sql: "SELECT guideURL FROM account") } == "http://g.example/epg.xml")

        let stored = try await GuideService(db: db, session: mockSession()).refresh(account: a, now: now)
        #expect(stored == 2)
        let entries = try await db.dbQueue.read { try GuideStore.entries($0, accountId: a.id!, channel: "a", now: now, limit: 2) }
        #expect(entries.map(\.title) == ["Now show", "Later show"])
        #expect(try await db.dbQueue.read { try GuideStore.entries($0, accountId: a.id!, channel: "a", now: now.addingTimeInterval(3300), limit: 2) }.map(\.title) == ["Later show"])
    }

    @Test func aFailedOrEmptyDownloadKeepsTheOldGuide() async throws {
        let db = try AppDatabase(); let a = try guideAccount(db)
        MockURLProtocol.handler = { r in
            r.url!.host == "g.example" ? (200, xml(prog("a", "Kept", start: now.addingTimeInterval(-60)))) : (200, Data(self.guidePlaylist("http://g.example/g.xml").utf8))
        }
        try await SyncService(db: db, session: mockSession()).sync(account: a, password: nil)
        let svc = GuideService(db: db, session: mockSession())
        #expect(try await svc.refresh(account: a, now: now) == 1)

        MockURLProtocol.handler = { _ in (200, xml("")) }                          // a guide with nothing for our channels
        #expect(try await svc.refresh(account: a, now: now) == 0)
        MockURLProtocol.handler = { _ in (500, Data()) }
        await #expect(throws: (any Error).self) { try await svc.refresh(account: a, now: now) }
        #expect(try await db.dbQueue.read { try GuideStore.entries($0, accountId: a.id!, channel: "a", now: now, limit: 1) }.map(\.title) == ["Kept"])
    }

    @Test func doesNothingWithoutALinkOrToALocalAddress() async throws {
        let db = try AppDatabase(); let a = try guideAccount(db)
        MockURLProtocol.handler = { _ in (200, Data(self.guidePlaylist(nil).utf8)) }
        try await SyncService(db: db, session: mockSession()).sync(account: a, password: nil)
        MockURLProtocol.handler = { _ in Issue.record("nothing may be downloaded"); return (500, Data()) }
        #expect(try await GuideService(db: db, session: mockSession()).refresh(account: a, now: now) == 0)

        try await db.dbQueue.write { try $0.execute(sql: "UPDATE account SET guideURL = 'http://192.168.1.1/epg.xml'") }
        #expect(try await GuideService(db: db, session: mockSession()).refresh(account: a, now: now) == 0)
    }

    @Test func theGuideLeavesWithItsPlaylist() async throws {
        let db = try AppDatabase(); let a = try guideAccount(db)
        try await db.dbQueue.write { d in try GuideStore.replace(d, accountId: a.id!, with: [Programme(channel: "a", title: "x", start: now, stop: now.addingTimeInterval(60))]) }
        try await db.dbQueue.write { try $0.execute(sql: "DELETE FROM account") }
        #expect(try await db.dbQueue.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM programme") } == 0)
    }
}
