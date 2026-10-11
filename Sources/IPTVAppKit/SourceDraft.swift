import Foundation
import IPTVCore

/// The add-source form as plain data: what is complete, what looks wrong while typing, and what a pasted link means.
public struct SourceDraft: Equatable {
    public var kind: AccountKind = .xtream
    public var name = "", server = "", username = "", password = "", url = ""
    public init() {}

    public var isComplete: Bool { LibraryModel.isValidSource(kind: kind, name: name, server: server, username: username, url: url) }

    /// Shown while typing, only for a field that has text: an Xtream server the app cannot build addresses from.
    public var serverLooksWrong: Bool {
        let s = server.trimmingCharacters(in: .whitespacesAndNewlines)
        return !s.isEmpty && XtreamURLs(server: s, username: "u", password: "p") == nil
    }
    /// A playlist link must be a full http(s) address (an Xtream server may be typed without the scheme, a link may not).
    public var urlLooksWrong: Bool {
        let s = url.trimmingCharacters(in: .whitespacesAndNewlines)
        return !s.isEmpty && !Self.isWebLink(s)
    }
    public var canTest: Bool { isComplete && (kind == .xtream ? !serverLooksWrong : !urlLooksWrong) }

    public static func isWebLink(_ s: String) -> Bool {
        guard let u = URL(string: s.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return ["http", "https"].contains(u.scheme?.lowercased() ?? "") && u.host?.isEmpty == false
    }

    /// Providers hand out one link that holds the whole login: `http://host:8080/get.php?username=u&password=p&type=m3u_plus`.
    public static func xtreamLogin(inLink s: String) -> (server: String, username: String, password: String)? {
        guard isWebLink(s), var c = URLComponents(string: s.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["/get.php", "/player_api.php"].contains(where: { c.path.lowercased().hasSuffix($0) }),
              let user = c.queryItems?.first(where: { $0.name == "username" })?.value, !user.isEmpty,
              let pass = c.queryItems?.first(where: { $0.name == "password" })?.value else { return nil }
        c.query = nil; c.fragment = nil; c.path = ""
        guard let server = c.string else { return nil }
        return (server, user, pass)
    }

    /// The account to save and the password to keep apart from it (it never goes into the database row).
    public func makeAccount() -> (account: Account, password: String?) {
        let n = name.trimmingCharacters(in: .whitespaces)
        let a = kind == .xtream
            ? Account(name: n, kind: .xtream, server: server.trimmingCharacters(in: .whitespacesAndNewlines), username: username.trimmingCharacters(in: .whitespacesAndNewlines))
            : Account(name: n, kind: .m3u, url: url.trimmingCharacters(in: .whitespacesAndNewlines))
        return (a, kind == .xtream ? password : nil)
    }
}

/// Recent search terms: local only (UserDefaults), newest first, no duplicates.
public struct RecentSearches {
    private let defaults: UserDefaults
    private let key: String
    public static let limit = 8
    public init(defaults: UserDefaults = .standard, key: String = "recentSearches") { self.defaults = defaults; self.key = key }

    public var items: [String] { defaults.stringArray(forKey: key) ?? [] }

    public func add(_ term: String) {
        let t = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 2 else { return }
        defaults.set(Array(([t] + items.filter { $0.caseInsensitiveCompare(t) != .orderedSame }).prefix(Self.limit)), forKey: key)
    }
    public func remove(_ term: String) { defaults.set(items.filter { $0 != term }, forKey: key) }
    public func clear() { defaults.removeObject(forKey: key) }
}
