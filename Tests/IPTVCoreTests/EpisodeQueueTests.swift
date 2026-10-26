import Testing
@testable import IPTVCore

@Test func nextEpisodeFollowsSeasonAndNumberOrder() {
    func ep(_ s: Int, _ n: Int, _ id: String) -> Episode { Episode(accountId: 1, seriesId: "9", season: s, number: n, title: "t", streamId: id) }
    let all = [ep(2, 1, "c"), ep(1, 2, "b"), ep(1, 1, "a"), ep(1, 10, "z")]   // unsorted, with a gap in numbering
    #expect(EpisodeQueue.next(after: "a", in: all)?.streamId == "b")
    #expect(EpisodeQueue.next(after: "b", in: all)?.streamId == "z")
    #expect(EpisodeQueue.next(after: "z", in: all)?.streamId == "c")     // next season starts
    #expect(EpisodeQueue.next(after: "c", in: all) == nil)               // last episode
    #expect(EpisodeQueue.next(after: "nope", in: all) == nil)
    #expect(EpisodeQueue.next(after: "a", in: []) == nil)
}

@Test func previousEpisodeIsTheMirrorOfNext() {
    func ep(_ s: Int, _ n: Int, _ id: String) -> Episode { Episode(accountId: 1, seriesId: "9", season: s, number: n, title: "t", streamId: id) }
    let all = [ep(2, 1, "c"), ep(1, 2, "b"), ep(1, 1, "a"), ep(1, 10, "z")]
    #expect(EpisodeQueue.previous(before: "c", in: all)?.streamId == "z")     // back into the earlier season
    #expect(EpisodeQueue.previous(before: "b", in: all)?.streamId == "a")
    #expect(EpisodeQueue.previous(before: "a", in: all) == nil)               // first episode
    #expect(EpisodeQueue.previous(before: "nope", in: all) == nil)
}
