import Testing
import Foundation
@testable import IPTVCore

private let now = Date(timeIntervalSince1970: 1_800_000_000)

@Test func theExpiryIsReadFromAStringOrANumber() {
    #expect(SubscriptionInfo(userInfo: ["exp_date": "1800864000"]).expires == Date(timeIntervalSince1970: 1_800_864_000))
    #expect(SubscriptionInfo(userInfo: ["exp_date": 1_800_864_000]).expires == Date(timeIntervalSince1970: 1_800_864_000))
    #expect(SubscriptionInfo(userInfo: ["exp_date": " 1800864000 "]).expires != nil)
}

@Test func noDateMeansNoExpiry() {
    for v: Any in [NSNull(), "", "0", 0, "never", "-5", "99999999999"] {
        #expect(SubscriptionInfo(userInfo: ["exp_date": v]).expires == nil, "exp_date \(v) is no date")
    }
    #expect(SubscriptionInfo(userInfo: [:]).expires == nil)
    #expect(SubscriptionInfo(userInfo: ["exp_date": "x"]).daysLeft(now: now) == nil)
    #expect(SubscriptionInfo().state(now: now) == .unknown)
}

@Test func daysLeftRoundUpAndTheStateFollows() {
    func info(afterDays d: Double) -> SubscriptionInfo { SubscriptionInfo(expires: now.addingTimeInterval(d * 86_400)) }
    #expect(info(afterDays: 30).daysLeft(now: now) == 30)
    #expect(info(afterDays: 0.1).daysLeft(now: now) == 1, "ends tonight: one day left")
    #expect(info(afterDays: 0).daysLeft(now: now) == 0)
    #expect(info(afterDays: -3).daysLeft(now: now) == -3)
    #expect(info(afterDays: 30).state(now: now) == .active)
    #expect(info(afterDays: 8).state(now: now) == .active)
    #expect(info(afterDays: 7).state(now: now) == .soon)
    #expect(info(afterDays: 1).state(now: now) == .soon)
    #expect(info(afterDays: 0).state(now: now) == .expired)
    #expect(info(afterDays: -1).state(now: now) == .expired)
}

@Test func maxConnectionsMustBePositive() {
    #expect(SubscriptionInfo(userInfo: ["max_connections": "2"]).maxConnections == 2)
    #expect(SubscriptionInfo(userInfo: ["max_connections": "0"]).maxConnections == nil)
    #expect(SubscriptionInfo(userInfo: [:]).maxConnections == nil)
}

@Test func theInfoSurvivesTheDefaultsRoundTrip() throws {
    let a = SubscriptionInfo(expires: Date(timeIntervalSince1970: 1_800_864_000), maxConnections: 3)
    let back = try JSONDecoder().decode(SubscriptionInfo.self, from: JSONEncoder().encode(a))
    #expect(back == a)
}
