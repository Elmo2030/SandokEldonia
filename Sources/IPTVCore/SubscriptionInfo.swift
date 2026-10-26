import Foundation

/// What an Xtream panel says about the subscription itself (`user_info` of the login answer). Everything is optional: a panel may leave any of
/// it out, and the app shows only what it got. Untrusted text, but only numbers are read here.
public struct SubscriptionInfo: Codable, Equatable, Sendable {
    /// When the subscription ends; nil when the panel gave no date (or `exp_date` is null/0/"", which panels use for "never").
    public var expires: Date?
    public var maxConnections: Int?

    public init(expires: Date? = nil, maxConnections: Int? = nil) { self.expires = expires; self.maxConnections = maxConnections }

    /// From the `user_info` object: `exp_date` is a Unix time in seconds, as a string or a number.
    public init(userInfo u: [String: Any]) {
        func number(_ v: Any?) -> Double? {
            if let n = v as? NSNumber { return n.doubleValue }
            if let s = v as? String { return Double(s.trimmingCharacters(in: .whitespaces)) }
            return nil
        }
        let exp = number(u["exp_date"])
        self.init(expires: exp.flatMap { $0 > 0 && $0 < 4_102_444_800 ? Date(timeIntervalSince1970: $0) : nil },   // < year 2100: bigger is "never"
                  maxConnections: number(u["max_connections"]).map { Int($0) }.flatMap { $0 > 0 ? $0 : nil })
    }

    public enum State: Equatable { case unknown, active, soon, expired }

    /// Whole days left, rounded up (a subscription that ends tonight has 1 day left); 0 or less once it ended. Nil without a date.
    public func daysLeft(now: Date = Date()) -> Int? {
        expires.map { Int(ceil($0.timeIntervalSince(now) / 86_400)) }
    }

    /// The playlist to warn about: among those that end within a week or already ended, the one that ends first. Nil when none does.
    public static func mostUrgent(_ list: [(name: String, info: SubscriptionInfo)], now: Date = Date()) -> (name: String, info: SubscriptionInfo)? {
        list.filter { [.soon, .expired].contains($0.info.state(now: now)) }
            .min { ($0.info.expires ?? .distantFuture) < ($1.info.expires ?? .distantFuture) }
    }

    /// `soon` = a week or less, the point where the app should make the date stand out.
    public func state(now: Date = Date()) -> State {
        guard let d = daysLeft(now: now) else { return .unknown }
        return d <= 0 ? .expired : d <= 7 ? .soon : .active
    }
}
