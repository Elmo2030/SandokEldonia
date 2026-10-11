import Testing
import Foundation
import IPTVCore
@testable import IPTVAppKit

private func ch(_ id: String, account: Int64 = 1, type: ItemType = .live) -> Item { Item(accountId: account, type: type, name: "ch\(id)", streamId: id) }

// MARK: zapping

@Test func zappingMovesThroughTheListAndWrapsAround() {
    let list = [ch("1"), ch("2"), ch("3")]
    #expect(ChannelZap.neighbor(of: list[0], in: list, step: 1)?.streamId == "2")
    #expect(ChannelZap.neighbor(of: list[2], in: list, step: 1)?.streamId == "1")
    #expect(ChannelZap.neighbor(of: list[0], in: list, step: -1)?.streamId == "3")
    #expect(ChannelZap.neighbor(of: list[1], in: list, step: -1)?.streamId == "1")
}

@Test func zappingNeedsAnotherChannelInTheSameList() {
    #expect(ChannelZap.neighbor(of: ch("1"), in: [ch("1")], step: 1) == nil)                   // alone
    #expect(ChannelZap.neighbor(of: ch("9"), in: [ch("1"), ch("2")], step: 1) == nil)           // not in the list (it changed)
    #expect(ChannelZap.neighbor(of: ch("1"), in: [], step: 1) == nil)
}

@Test func zappingSkipsMoviesAndTellsPlaylistsApart() {
    let list = [ch("1"), ch("50", type: .movie), ch("1", account: 2), ch("2")]
    #expect(ChannelZap.neighbor(of: ch("1"), in: list, step: 1)?.accountId == 2)                // same stream id in another playlist is another channel
    #expect(ChannelZap.neighbor(of: ch("1", account: 2), in: list, step: 1)?.streamId == "2")
    #expect(ChannelZap.neighbor(of: ch("2"), in: list, step: 1)?.streamId == "1")               // the movie is not a channel
    #expect(ChannelZap.neighbor(of: ch("1"), in: list, step: 3)?.streamId == "1")               // longer steps wrap too (3 channels... ring of 3)
}

// MARK: up next

private func ep(_ n: Int) -> Episode { Episode(accountId: 1, seriesId: "s", season: 1, number: n, title: "e\(n)", streamId: "\(n)") }

@MainActor @Test func upNextCountsDownThenPlaysTheEpisode() async {
    let up = UpNext(seconds: 3, pause: { await Task.yield() })
    var played: [Episode] = []
    var seen: [Int] = []
    up.begin(ep(2)) { played.append($0) }
    #expect(up.episode?.number == 2 && up.isCounting)
    for _ in 0..<500 where played.isEmpty { seen.append(up.secondsLeft); await Task.yield() }
    #expect(played.map(\.number) == [2])
    #expect(Set(seen).isSuperset(of: [3]))
    #expect(up.episode == nil && up.secondsLeft == 0 && !up.isCounting)
}

@MainActor @Test func cancellingStopsTheCountdownAndNothingPlays() async {
    let gate = AsyncStream<Void>.makeStream()
    let up = UpNext(seconds: 5, pause: { var it = gate.stream.makeAsyncIterator(); _ = await it.next() })
    var played = 0
    up.begin(ep(2)) { _ in played += 1 }
    await Task.yield()
    #expect(up.episode != nil)
    up.cancel()
    #expect(up.episode == nil && up.secondsLeft == 0)
    gate.continuation.yield(); gate.continuation.finish()
    for _ in 0..<50 { await Task.yield() }
    #expect(played == 0)
}

@MainActor @Test func aSecondBeginWhileCountingIsIgnored() async {
    let up = UpNext(seconds: 2, pause: { try? await Task.sleep(for: .seconds(5)) })
    up.begin(ep(2)) { _ in }
    up.begin(ep(3)) { _ in }
    #expect(up.episode?.number == 2)
    up.cancel()
}
