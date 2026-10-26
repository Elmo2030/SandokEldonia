import Foundation

public struct M3UEntry: Equatable {
    public var name: String, url: String
    public var group: String?, logo: String?, tvgId: String?
    public var catchupDays: Int?
}

public struct M3UParser {
    private var pending: (name: String, attrs: [String: String])?
    private static let attrRegex = try! NSRegularExpression(pattern: #"([A-Za-z0-9_-]+)="([^"]*)""#)

    public init() {}

    public mutating func feed(_ raw: String) -> M3UEntry? {
        var line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.hasPrefix("\u{FEFF}") { line.removeFirst() }
        if line.isEmpty || line.hasPrefix("#EXTM3U") { return nil }
        if line.hasPrefix("#EXTINF") { pending = Self.parseInf(line); return nil }
        if line.hasPrefix("#") { return nil }
        defer { pending = nil }
        // Never use the URL itself as the title: it carries the account's username and password.
        let fallback = Self.fallbackName(line)
        let info = pending ?? (name: fallback, attrs: [:])
        let name = info.name.isEmpty ? fallback : info.name
        func attr(_ k: String) -> String? { info.attrs[k].flatMap { $0.isEmpty ? nil : $0 } }
        return M3UEntry(name: name, url: line, group: attr("group-title"), logo: attr("tvg-logo"),
                        tvgId: attr("tvg-id"), catchupDays: attr("catchup-days").flatMap { Int($0) })
    }

    /// Where the header of a playlist (`#EXTM3U url-tvg="..."`, also written `x-tvg-url`) says its program guide is. Several links may be
    /// given, separated by commas: the first web link is used. Nil when there is none.
    public static func guideURL(inHeader line: String) -> String? {
        guard line.utf8.count <= 8192 else { return nil }
        let ns = line as NSString
        for m in attrRegex.matches(in: line, range: NSRange(location: 0, length: ns.length)) where ["url-tvg", "x-tvg-url"].contains(ns.substring(with: m.range(at: 1)).lowercased()) {
            for part in ns.substring(with: m.range(at: 2)).split(separator: ",") {
                let link = part.trimmingCharacters(in: .whitespaces)
                if let u = URL(string: link), ["http", "https"].contains(u.scheme?.lowercased() ?? ""), u.host?.isEmpty == false { return link }
            }
        }
        return nil
    }

    /// Last path component without query/userinfo, or a neutral label.
    static func fallbackName(_ url: String) -> String {
        let last = URL(string: url)?.lastPathComponent ?? ""
        return last.isEmpty || last == "/" ? "Channel" : last
    }

    private static func parseInf(_ line: String) -> (name: String, attrs: [String: String]) {
        // A crafted multi-hundred-KB "attribute" line makes the regex scan quadratic: real lines are far shorter.
        if line.utf8.count > 8192 { return ("", [:]) }
        var inQuote = false
        var commaIndex: String.Index?
        for i in line.indices {
            let c = line[i]
            if c == "\"" { inQuote.toggle() }
            else if c == "," && !inQuote { commaIndex = i; break }
        }
        let head = commaIndex.map { String(line[..<$0]) } ?? line
        let name = commaIndex.map { String(line[line.index(after: $0)...]).trimmingCharacters(in: .whitespaces) } ?? ""
        var attrs: [String: String] = [:]
        let ns = head as NSString
        for m in attrRegex.matches(in: head, range: NSRange(location: 0, length: ns.length)) {
            attrs[ns.substring(with: m.range(at: 1))] = ns.substring(with: m.range(at: 2))
        }
        return (name, attrs)
    }
}

public enum M3UClassifier {
    // ponytail: heuristic only, no per-category override in v1; add a settings override if misclassified lists show up.
    public static func type(url: String, group: String?) -> ItemType {
        let u = url.lowercased()
        if u.contains("/movie/") { return .movie }
        if u.contains("/series/") { return .series }
        let g = (group ?? "").lowercased()
        if ["series", "tv show", "סדר"].contains(where: g.contains) { return .series }
        if ["vod", "movie", "film", "סרט"].contains(where: g.contains) { return .movie }
        if [".mp4", ".mkv", ".avi"].contains(where: u.hasSuffix) { return .movie }
        return .live
    }
}
