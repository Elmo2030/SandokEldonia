import Testing
import Foundation
@testable import IPTVPlayer

@Test func aLiveChannelRetriesThreeTimesWithGrowingDelaysFromTheLiveEdge() {
    #expect(PlaybackRetry.decide(isLive: true, attempt: 0, position: 120, requestedStart: 0) == .retry(after: 2, start: 0))
    #expect(PlaybackRetry.decide(isLive: true, attempt: 1, position: 0, requestedStart: 0) == .retry(after: 4, start: 0))
    #expect(PlaybackRetry.decide(isLive: true, attempt: 2, position: 0, requestedStart: 0) == .retry(after: 8, start: 0))
    #expect(PlaybackRetry.decide(isLive: true, attempt: 3, position: 0, requestedStart: 0) == .giveUp)
}

@Test func aMovieThatBrokeMidwayResumesAMomentBeforeTheBreak() {
    #expect(PlaybackRetry.decide(isLive: false, attempt: 0, position: 1500, requestedStart: 0) == .retry(after: 2, start: 1498))
    #expect(PlaybackRetry.decide(isLive: false, attempt: 2, position: 1500, requestedStart: 0) == .retry(after: 8, start: 1498))
    #expect(PlaybackRetry.decide(isLive: false, attempt: 3, position: 1500, requestedStart: 0) == .giveUp)
    #expect(PlaybackRetry.decide(isLive: false, attempt: 0, position: 1, requestedStart: 0) == .retry(after: 2, start: 0))   // never before 0
}

@Test func aMovieThatNeverStartedGetsOneMoreTryAtItsRequestedStart() {
    #expect(PlaybackRetry.decide(isLive: false, attempt: 0, position: 0, requestedStart: 600) == .retry(after: 2, start: 600))
    #expect(PlaybackRetry.decide(isLive: false, attempt: 1, position: 0, requestedStart: 600) == .giveUp)
}

@Test func aNegativeAttemptNeverRetries() {
    #expect(PlaybackRetry.decide(isLive: true, attempt: -1, position: 0, requestedStart: 0) == .giveUp)
}

@Test func diagnosticsKeepTheServerAndFileTypeButNeverTheAccount() {
    let url = URL(string: "http://panel.example:8080/movie/alice/s3cret/4711.MKV?token=abc123")!
    let text = PlaybackDiagnostics.report(
        kind: "movie", url: url, position: 3725, duration: 7200, retries: 2,
        error: "loading failed: http://panel.example:8080/movie/alice/s3cret/4711.MKV?token=abc123 (403)",
        appVersion: "0.9.3", system: "macOS 27.0")
    #expect(text.contains("Server: http://panel.example:8080"))
    #expect(text.contains("File type: mkv"))
    #expect(text.contains("Position: 1:02:05 / 2:00:00"))
    #expect(text.contains("Retries: 2"))
    #expect(text.contains("Error: loading failed: <address> (403)"))
    for secret in ["alice", "s3cret", "abc123", "4711"] { #expect(!text.contains(secret)) }
}

@Test func diagnosticsCopeWithMissingPartsAndNonFiniteNumbers() {
    let text = PlaybackDiagnostics.report(kind: "live", url: URL(string: "rtmp://h/live")!, position: .nan, duration: -5,
                                          retries: 0, error: nil, appVersion: "1", system: "macOS")
    #expect(text.contains("Position: 0:00:00 / 0:00:00"))
    #expect(text.contains("Error: -"))
    #expect(text.contains("File type: -"))
}

@Test func volumeMovesInStepsOfFiveAndStaysInRange() {
    #expect(PlayerVolume.stepped(from: 100, up: true) == 100)
    #expect(PlayerVolume.stepped(from: 100, up: false) == 95)
    #expect(PlayerVolume.stepped(from: 0, up: false) == 0)
    #expect(PlayerVolume.stepped(from: 47, up: true) == 50)          // an odd value snaps to the grid first
    #expect(PlayerVolume.stepped(from: 130, up: false) == 100)       // above the range comes back into it
    #expect(PlayerVolume.stepped(from: .nan, up: false) == 100)
}
