import Foundation
import Compression
import GRDB

/// One program of a channel's guide.
public struct Programme: Equatable, Sendable {
    public var channel: String, title: String
    public var start: Date, stop: Date
    public init(channel: String, title: String, start: Date, stop: Date) { self.channel = channel; self.title = title; self.start = start; self.stop = stop }
}

/// Reads an XMLTV guide file (what an M3U playlist's `url-tvg` points at). A guide covers every channel of a provider for days, so only what
/// the app can show is kept: the playlist's own channels, from an hour ago to two days ahead. The file is untrusted text: titles are length-capped
/// and stripped of control characters, and the number of programs is capped.
public enum XMLTVParser {
    public static let maxProgrammes = 400_000

    public static func parse(_ xml: Data, wanted: Set<String>, now: Date = Date()) -> [Programme] {
        let reader = Reader(wanted: wanted, from: now.addingTimeInterval(-3600), until: now.addingTimeInterval(48 * 3600))
        let parser = XMLParser(data: xml)
        parser.shouldResolveExternalEntities = false
        parser.delegate = reader
        parser.parse()
        return reader.found
    }

    private static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// "20261026183000 +0200" (the offset is optional and means UTC when absent; the seconds are optional too).
    static func date(_ s: String) -> Date? {
        let parts = s.split(separator: " ")
        guard let stamp = parts.first, stamp.utf8.count == 12 || stamp.utf8.count == 14, stamp.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) else { return nil }
        let d = Array(stamp.utf8).map { Int($0) - 48 }
        func n(_ a: Int, _ b: Int) -> Int { d[a..<b].reduce(0) { $0 * 10 + $1 } }
        var c = DateComponents()
        c.year = n(0, 4); c.month = n(4, 6); c.day = n(6, 8); c.hour = n(8, 10); c.minute = n(10, 12); c.second = d.count == 14 ? n(12, 14) : 0
        let cal = utc
        guard (1...12).contains(c.month!), (1...31).contains(c.day!), c.hour! < 24, c.minute! < 60, c.second! < 61, let utc = cal.date(from: c) else { return nil }
        var offset = 0
        if parts.count > 1, parts[1].utf8.count == 5, let sign = parts[1].first, sign == "+" || sign == "-", let h = Int(parts[1].dropFirst().prefix(2)), let m = Int(parts[1].suffix(2)) {
            offset = (sign == "-" ? -1 : 1) * (h * 3600 + m * 60)
        }
        return utc.addingTimeInterval(TimeInterval(-offset))
    }

    private final class Reader: NSObject, XMLParserDelegate {
        let wanted: Set<String>, from: Date, until: Date
        var found: [Programme] = []
        private var channel: String?, start: Date?, stop: Date?, title: String?
        private var text = "", inTitle = false

        init(wanted: Set<String>, from: Date, until: Date) { self.wanted = wanted; self.from = from; self.until = until }

        func parser(_ p: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
            if name == "programme" {
                channel = a["channel"].flatMap { wanted.contains($0) ? $0 : nil }
                title = nil
                // A guide lists every channel of a provider: dates are read only for the playlist's own.
                if channel != nil { start = a["start"].flatMap(XMLTVParser.date); stop = a["stop"].flatMap(XMLTVParser.date) } else { start = nil; stop = nil }
            } else if name == "title", channel != nil, title == nil { inTitle = true; text = "" }
        }

        func parser(_ p: XMLParser, foundCharacters s: String) { if inTitle, text.utf8.count < 1000 { text += s } }

        func parser(_ p: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            if name == "title", inTitle { inTitle = false; title = Self.clean(text) }
            guard name == "programme" else { return }
            defer { channel = nil; title = nil }
            guard let channel, let start, let stop, stop > start, stop > from, start < until, let title, !title.isEmpty else { return }
            found.append(Programme(channel: channel, title: title, start: start, stop: stop))
            if found.count >= XMLTVParser.maxProgrammes { p.abortParsing() }
        }

        static func clean(_ s: String) -> String {
            String(String.UnicodeScalarView(s.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.prefix(200)))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

/// gzip, as guides are usually served. A file that does not start with the gzip marker is returned as it is.
public enum Gzip {
    public static func inflate(_ data: Data, maxBytes: Int) throws -> Data {
        guard data.count >= 2, data[data.startIndex] == 0x1f, data[data.startIndex + 1] == 0x8b else { return data }
        let b = [UInt8](data)
        guard b.count > 18, b[2] == 8 else { throw IPTVError.badResponse }
        var i = 10
        if b[3] & 4 != 0 { guard i + 2 <= b.count else { throw IPTVError.badResponse }; i += 2 + (Int(b[i]) | Int(b[i + 1]) << 8) }
        for flag: UInt8 in [8, 16] where b[3] & flag != 0 {                       // a zero-terminated file name / comment
            while i < b.count, b[i] != 0 { i += 1 }
            i += 1
        }
        if b[3] & 2 != 0 { i += 2 }
        guard i < b.count - 8 else { throw IPTVError.badResponse }
        let body = Data(b[i..<(b.count - 8)])                                      // the last 8 bytes are the checksum and length
        var offset = 0, out = Data()
        let filter = try InputFilter(.decompress, using: .zlib) { (length: Int) -> Data? in
            guard offset < body.count else { return nil }
            let end = min(offset + length, body.count)
            defer { offset = end }
            return body.subdata(in: offset..<end)
        }
        while let chunk = try filter.readData(ofLength: 1 << 16) {
            out.append(chunk)
            if out.count > maxBytes { throw IPTVError.badResponse }                // a decompression bomb
        }
        return out
    }
}

/// The guide programs kept for the M3U playlists (Xtream playlists ask their panel instead).
public enum GuideStore {
    /// Replaces a playlist's programs. Called only with a non-empty list: a failed or empty download must not wipe a working guide.
    public static func replace(_ db: Database, accountId: Int64, with list: [Programme]) throws {
        try db.execute(sql: "DELETE FROM programme WHERE accountId = ?", arguments: [accountId])
        let st = try db.cachedStatement(sql: "INSERT OR IGNORE INTO programme (accountId,channel,start,stop,title) VALUES (?,?,?,?,?)")
        for p in list {
            try st.execute(arguments: [accountId, p.channel, Int64(p.start.timeIntervalSince1970), Int64(p.stop.timeIntervalSince1970), p.title])
        }
    }

    /// The program on now and the ones after it, from the program that is on at `now`.
    public static func entries(_ db: Database, accountId: Int64, channel: String, now: Date = Date(), limit: Int) throws -> [EPGEntry] {
        try Row.fetchAll(db, sql: "SELECT title, start, stop FROM programme WHERE accountId = ? AND channel = ? AND stop > ? ORDER BY start LIMIT ?",
                         arguments: [accountId, channel, Int64(now.timeIntervalSince1970), limit]).map {
            EPGEntry(title: $0["title"], start: Date(timeIntervalSince1970: $0["start"]), end: Date(timeIntervalSince1970: $0["stop"]))
        }
    }
}

/// Downloads and stores the guide of an M3U playlist.
public final class GuideService {
    let db: AppDatabase
    let session: URLSession
    static let maxDownloadBytes = 150_000_000, maxXMLBytes = 700_000_000

    public init(db: AppDatabase, session: URLSession = apiSession) { self.db = db; self.session = session }

    /// Returns how many programs were stored (0 = nothing to do or nothing usable; the old guide stays).
    @discardableResult
    public func refresh(account: Account, now: Date = Date()) async throws -> Int {
        guard account.kind == .m3u, let aid = account.id else { return 0 }
        let (link, wanted) = try await db.dbQueue.read { d in
            (try String.fetchOne(d, sql: "SELECT guideURL FROM account WHERE id = ?", arguments: [aid]),
             Set(try String.fetchAll(d, sql: "SELECT DISTINCT epgChannelId FROM item WHERE accountId = ? AND type = 'live' AND epgChannelId IS NOT NULL", arguments: [aid])))
        }
        // The address comes from the playlist file: never a device on the user's own network (the same rule as for logos).
        guard let link, !wanted.isEmpty, let url = RemoteImage.safeURL(link) else { return 0 }
        let (data, resp) = try await session.data(from: url)
        if let code = (resp as? HTTPURLResponse)?.statusCode, !(200..<300).contains(code) { throw IPTVError.http(code) }
        guard data.count <= Self.maxDownloadBytes else { throw IPTVError.badResponse }
        let programmes = XMLTVParser.parse(try Gzip.inflate(data, maxBytes: Self.maxXMLBytes), wanted: wanted, now: now)
        guard !programmes.isEmpty else { return 0 }
        try await db.dbQueue.write { try GuideStore.replace($0, accountId: aid, with: programmes) }
        return programmes.count
    }
}
