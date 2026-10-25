import Testing
import Foundation
@testable import IPTVPlayer

// Real libmpv with no video output (vo=null) and a synthetic source: the controller's polling, failure handling and rules.

@MainActor private func controller(retryDelay: TimeInterval = 0.05) -> PlaybackController {
    let c = PlaybackController(subLang: nil, audioLang: nil, tickInterval: nil, retryDelay: retryDelay)
    c.mpv.setProperty("vo", "null")
    c.mpv.setProperty("ao", "null")
    return c
}

@MainActor private func wait(_ c: PlaybackController, up limit: Int = 60, _ done: () -> Bool) async {
    for _ in 0..<limit where !done() { try? await Task.sleep(for: .milliseconds(100)); c.tick() }
}

private let lavfi = "av://lavfi:testsrc=size=320x240:rate=25"

@MainActor @Test func tickingReflectsPlaybackAndPause() async throws {
    let c = controller()
    defer { c.close() }
    c.play(lavfi, isLive: false, start: 0)
    #expect(c.buffering)                                                     // nothing decoded yet
    await wait(c) { c.position > 0.5 }
    #expect(c.position > 0.5 && !c.paused && !c.failed)
    #expect(c.tracks.contains { $0.type == "video" })
    c.setPlaying(false)
    try await Task.sleep(for: .milliseconds(300)); c.tick()
    #expect(c.paused)
    c.togglePause()
    try await Task.sleep(for: .milliseconds(300)); c.tick()
    #expect(!c.paused)
}

@MainActor @Test func speedIsClampedAndRoundedAndSetAtOnce() {
    let c = controller()
    defer { c.close() }
    c.setSpeed(1.52)
    #expect(c.speed == 1.5 && c.mpv.double("speed") == 1.5)
    c.setSpeed(9)
    #expect(c.speed == 4)
    c.setSpeed(.nan)
    #expect(c.speed == 1)
}

@MainActor @Test func seekingMovesThePositionAtOnceAndStaysInsideTheFile() async throws {
    let c = controller()
    defer { c.close() }
    c.play(lavfi, isLive: false, start: 0)
    await wait(c) { c.position > 0.2 }
    c.seek(to: 7)
    #expect(c.position == 7)
    c.seek(by: -100)
    #expect(c.position == 0)
    c.seek(to: -4)
    #expect(c.position == 0)
}

@MainActor @Test func aMovieThatCannotBeOpenedFailsWithMpvsReason() async {
    let c = controller()
    defer { c.close() }
    c.play(URL(string: "file:///nonexistent/none.mkv")!, isLive: false, start: 0)
    await wait(c) { c.failed }
    #expect(c.failed)
    #expect(c.failure?.isEmpty == false, "the reason must be there to show")
    #expect(!c.buffering)
}

@MainActor @Test func aLiveStreamThatCannotBeOpenedIsRetriedThreeTimesBeforeItFails() async {
    let c = controller(retryDelay: 0.2)
    defer { c.close() }
    let t0 = Date()
    c.play(URL(string: "file:///nonexistent/live.ts")!, isLive: true, start: 0)
    await wait(c, up: 100) { c.failed }
    #expect(c.failed, "after three reloads the live stream gives up")
    #expect(Date().timeIntervalSince(t0) >= 0.55, "three reloads, 0.2 s apart, come before the error screen")
    #expect(c.failure?.isEmpty == false)
}

@MainActor @Test func retryClearsTheFailureAndReloads() async {
    let c = controller()
    defer { c.close() }
    c.play(URL(string: "file:///nonexistent/none.mkv")!, isLive: false, start: 0)
    await wait(c) { c.failed }
    #expect(c.failed)
    c.retry()
    #expect(!c.failed && c.failure == nil && c.buffering)
    await wait(c) { c.failed }
    #expect(c.failed)                                                        // still nonexistent: it fails again, with a reason
}

@MainActor @Test func theSleepTimerFiresOnceAndTheMinutesLeftAreShown() {
    let c = controller()
    defer { c.close() }
    let t0 = Date(timeIntervalSince1970: 5000)
    nonisolated(unsafe) var slept = 0
    c.onSleep = { slept += 1 }
    c.setSleep(minutes: 15, now: t0)
    #expect(c.sleepMinutesLeft == 15)
    c.tick(now: t0.addingTimeInterval(61))
    #expect(c.sleepMinutesLeft == 14 && slept == 0)
    c.tick(now: t0.addingTimeInterval(15 * 60))
    #expect(slept == 1 && c.sleepMinutesLeft == nil)
    c.tick(now: t0.addingTimeInterval(16 * 60))
    #expect(slept == 1)
    c.setSleep(minutes: 30, now: t0)
    c.setSleep(minutes: 0, now: t0)
    #expect(c.sleepMinutesLeft == nil)
}

@MainActor @Test func aShortMovieReportsItsEndOnceAndReplayStartsOver() async throws {
    guard let video = await makeBrightnessRampVideo(seconds: 2) else { return }   // a machine that cannot encode skips this one
    defer { try? FileManager.default.removeItem(at: video) }
    let c = controller()
    defer { c.close() }
    nonisolated(unsafe) var changes: [Bool] = []
    c.onEndChanged = { changes.append($0) }
    c.play(video, isLive: false, start: 0)
    await wait(c, up: 80) { changes.contains(true) }
    #expect(changes.contains(true) && c.atEnd, "the end of the file was not reported: \(changes)")
    let ends = changes.filter { $0 }.count
    for _ in 0..<5 { try await Task.sleep(for: .milliseconds(100)); c.tick() }
    #expect(changes.filter { $0 }.count == ends, "the end is reported once")
    c.setPlaying(true)                                                         // at the end, play means replay
    #expect(!c.paused && c.position == 0)
}

@MainActor @Test func progressIsSavedPeriodicallyOnCloseAndOnReplaceButNeverAsZeroOrForLive() async throws {
    guard let video = await makeBrightnessRampVideo(seconds: 6) else { return }
    defer { try? FileManager.default.removeItem(at: video) }
    let c = controller()
    nonisolated(unsafe) var saves: [(Double, Bool)] = []
    c.onSaveProgress = { p, _, bg in saves.append((p, bg)) }
    c.play(video, isLive: false, start: 0)
    #expect(saves.isEmpty)                                                     // nothing played yet: a 0 would erase the resume point
    await wait(c) { c.position > 0.5 }
    for _ in 0..<20 { c.tick() }                                               // 20 ticks = one periodic save, as background
    #expect(saves.last?.1 == true && (saves.last?.0 ?? 0) > 0)
    let before = saves.count
    c.play(lavfi, isLive: true, start: 0)                                      // replace: the old position is saved synchronously
    #expect(saves.count == before + 1 && saves.last?.1 == false)
    for _ in 0..<40 { c.tick() }
    c.close()
    #expect(saves.count == before + 1, "a live stream is never saved")
}

@MainActor @Test(arguments: [("1280x720", "HD"), ("1920x1080", "FHD"), ("3840x2160", "4K")])
func theQualityTagComesFromTheDecodedPictureSize(size: String, tag: String) async {
    let c = controller()
    defer { c.close() }
    #expect(c.quality == nil)                                                // unknown until a picture is decoded
    c.play("av://lavfi:testsrc=size=\(size):rate=10", isLive: false, start: 0)
    await wait(c) { c.quality != nil }
    #expect(c.quality == tag)
}
