import Testing
import Foundation
@testable import IPTVPlayer

// MARK: live recovery

@Test func aDroppedLiveStreamIsReloadedThreeTimesThenGivesUp() {
    var r = LiveRecovery()
    let v1 = r.failed()
    let v2 = r.failed()
    let v3 = r.failed()
    #expect(v1 && v2 && v3)
    #expect(r.retries == 3)
    let v4 = r.failed()
    #expect(v4 == false)                      // budget spent: the error screen
}

@Test func aStreamThatPlaysAgainGetsAFreshRetryBudget() {
    var r = LiveRecovery()
    let v5 = r.failed()
    let v6 = r.failed()
    #expect(v5 && v6)
    r.reloaded()                                      // time-pos restarts at 0 after the reload
    r.observe(position: 0.3)                          // not enough movement yet
    #expect(r.retries == 2)
    r.observe(position: 1.2)
    #expect(r.retries == 0)
    let v7 = r.failed()
    let v8 = r.failed()
    let v9 = r.failed()
    let v10 = r.failed()
    #expect(v7 && v8 && v9 && !v10)
}

@Test func recoveryTracksTheLastPositionSoAStalledStreamIsNotRefreshed() {
    var r = LiveRecovery()
    r.observe(position: 10)
    let v11 = r.failed()
    #expect(v11)
    r.observe(position: 10.2)                         // still within half a second of the last good position
    #expect(r.retries == 1)
    r.observe(position: 11)
    #expect(r.retries == 0)
    r.reset()
    #expect(r == LiveRecovery())
}

// MARK: end of media

@Test func theEndIsReportedOnceAndOnlyWhenTheFileReallyEnded() {
    var e = EndOfMedia()
    let v12 = e.observe(atEOF: false, position: 100, duration: 3600)
    #expect(v12 == nil)
    let v13 = e.observe(atEOF: true, position: 100, duration: 3600)
    #expect(v13 == nil)        // a connection cut early also sets eof-reached
    let v14 = e.observe(atEOF: true, position: 3595, duration: 3600)
    #expect(v14 == true)
    let v15 = e.observe(atEOF: true, position: 3599, duration: 3600)
    #expect(v15 == nil)      // no repeat
    let v16 = e.observe(atEOF: false, position: 3000, duration: 3600)
    #expect(v16 == false)    // seeked back: the up-next countdown stops
    let v17 = e.observe(atEOF: true, position: 5, duration: 0)
    #expect(v17 == nil)             // no duration known
}

@Test func aNewFileIgnoresTheOldFilesLastTick() {
    var e = EndOfMedia()
    _ = e.observe(atEOF: true, position: 59, duration: 60)
    e.newFile()
    let v18 = e.observe(atEOF: true, position: 59, duration: 60)
    #expect(v18 == nil)           // the old file still reports its end for a tick
    let v19 = e.observe(atEOF: false, position: 1, duration: 120)
    #expect(v19 == false)
    let v20 = e.observe(atEOF: true, position: 118, duration: 120)
    #expect(v20 == true)
}

// MARK: paused live stream

@Test func aLiveStreamPausedForAWhileIsReloadedOnResume() {
    let t0 = Date(timeIntervalSince1970: 1000)
    var c = PauseClock()
    c.paused(at: t0)
    let v21 = c.resumed(at: t0.addingTimeInterval(5), isLive: true)
    #expect(v21 == false)      // a short pause resumes from the cache
    c.paused(at: t0)
    let v22 = c.resumed(at: t0.addingTimeInterval(PauseClock.staleAfter), isLive: true)
    #expect(v22)
    c.paused(at: t0)
    let v23 = c.resumed(at: t0.addingTimeInterval(600), isLive: false)
    #expect(v23 == false)   // a movie never needs it
    let v24 = c.resumed(at: t0.addingTimeInterval(900), isLive: true)
    #expect(v24 == false)    // not paused at all
}

@Test func theFirstPauseCountsNotLaterOnes() {
    let t0 = Date(timeIntervalSince1970: 0)
    var c = PauseClock()
    c.paused(at: t0); c.paused(at: t0.addingTimeInterval(30))
    let v25 = c.resumed(at: t0.addingTimeInterval(31), isLive: true)
    #expect(v25)
}

// MARK: controls auto-hide

@Test func controlsHideThreeSecondsAfterTheLastTouch() {
    let t0 = Date(timeIntervalSince1970: 0)
    var v = ControlsVisibility(hideAfter: 3, now: t0)
    v.tick(now: t0.addingTimeInterval(2.9), holding: false)
    #expect(v.shown)
    v.tick(now: t0.addingTimeInterval(3), holding: false)
    #expect(!v.shown)
    v.touch(now: t0.addingTimeInterval(10))
    #expect(v.shown)
    v.tick(now: t0.addingTimeInterval(12), holding: false)
    #expect(v.shown)                                                              // the countdown restarted at the touch
}

@Test func somethingThatNeedsTheControlsHoldsThemAndRestartsTheCountdown() {
    let t0 = Date(timeIntervalSince1970: 0)
    var v = ControlsVisibility(hideAfter: 3, now: t0)
    for s in 1...10 { v.tick(now: t0.addingTimeInterval(Double(s)), holding: true) }   // paused, scrubbing, a sheet...
    #expect(v.shown)
    v.tick(now: t0.addingTimeInterval(12), holding: false)                        // released 2 s after the last hold
    #expect(v.shown)
    v.tick(now: t0.addingTimeInterval(13.1), holding: false)
    #expect(!v.shown)
}

@Test func aTapTogglesAndZeroMeansNeverHide() {
    let t0 = Date(timeIntervalSince1970: 0)
    var v = ControlsVisibility(hideAfter: 0, now: t0)
    v.tick(now: t0.addingTimeInterval(1000), holding: false)
    #expect(v.shown)
    v.toggle(now: t0)
    #expect(!v.shown)
    v.toggle(now: t0)
    #expect(v.shown)
    v.hide()
    #expect(!v.shown)
}
