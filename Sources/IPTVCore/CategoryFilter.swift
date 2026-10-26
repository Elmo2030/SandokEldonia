import Foundation
import GRDB

/// "Hide categories": a plain name filter (not a parental lock). Built from the comma-separated preference (Arabic comma too).
/// The kids profile uses the opposite form: only categories whose name contains one of a list of words are shown. That is a guess from
/// category names, which providers write as they like: a convenience for children, not a guarantee.
public struct CategoryFilter: Sendable {
    public let words: [String]
    /// When not empty, ONLY categories whose name contains one of these are shown (and titles without a category are not).
    public let allowOnly: [String]

    public init(_ csv: String) {
        words = csv.split(whereSeparator: { $0 == "," || $0 == "،" }).map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty }
        allowOnly = []
    }

    private init(allowOnly: [String]) { words = []; self.allowOnly = allowOnly }

    /// What the kids profile shows.
    public static let kids = CategoryFilter(allowOnly: [
        "kids", "kid", "children", "child", "cartoon", "animation", "anime", "family", "junior", "baby", "toon", "disney", "nick", "pixar",
        "أطفال", "اطفال", "كرتون", "عائل", "ديزني", "سبيس", "طيور", "رسوم متحركة", "انمي", "أنمي",
    ])

    public var isEmpty: Bool { words.isEmpty && allowOnly.isEmpty }

    public func hides(_ name: String) -> Bool {
        func has(_ w: String) -> Bool { name.range(of: w, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        return allowOnly.isEmpty ? words.contains(where: has) : !allowOnly.contains(where: has)
    }

    public func visible(_ categories: [Category]) -> [Category] { categories.filter { !hides($0.name) } }

    /// Drops the items of hidden categories (a category is a playlist + type + remote id). Items without a category stay, except
    /// in the kids form, where only an allowed category counts.
    public func visible(_ items: [Item], in db: Database) throws -> [Item] {
        guard !isEmpty else { return items }
        let all = try Category.fetchAll(db)
        if !allowOnly.isEmpty {
            let shown = Set(all.filter { !hides($0.name) }.map { Self.key($0.accountId, $0.type, $0.remoteId) })
            return items.filter { i in i.categoryId.map { shown.contains(Self.key(i.accountId, i.type, $0)) } ?? false }
        }
        let hidden = Set(all.filter { hides($0.name) }.map { Self.key($0.accountId, $0.type, $0.remoteId) })
        guard !hidden.isEmpty else { return items }
        return items.filter { i in i.categoryId.map { !hidden.contains(Self.key(i.accountId, i.type, $0)) } ?? true }
    }

    private static func key(_ account: Int64, _ type: ItemType, _ remoteId: String) -> String { "\(account)|\(type.rawValue)|\(remoteId)" }
}
