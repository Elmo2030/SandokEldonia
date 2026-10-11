import Testing
import Foundation
import MediaPlayer
@testable import IPTVPlayer

// MARK: interruptions

@Test func aCallPausesAndResumesWhenItEndsIfTheSystemSaysSo() {
    var p = InterruptionPolicy()
    let v1 = p.handle(.began, isPlaying: true)
    #expect(v1 == .pause)
    let v2 = p.handle(.ended(shouldResume: true), isPlaying: false)
    #expect(v2 == .resume)
}

@Test func nothingResumesWithoutTheSystemsShouldResume() {
    var p = InterruptionPolicy()
    _ = p.handle(.began, isPlaying: true)
    let v3 = p.handle(.ended(shouldResume: false), isPlaying: false)
    #expect(v3 == .none)      // another app took the audio for good
    let v4 = p.handle(.ended(shouldResume: true), isPlaying: false)
    #expect(v4 == .none)       // and the flag does not stay armed
}

@Test func aPlayerThatWasPausedBeforeTheInterruptionStaysPaused() {
    var p = InterruptionPolicy()
    let v5 = p.handle(.began, isPlaying: false)
    #expect(v5 == .none)
    let v6 = p.handle(.ended(shouldResume: true), isPlaying: false)
    #expect(v6 == .none)
}

@Test func aChoiceOfTheUserDuringTheInterruptionWins() {
    var p = InterruptionPolicy()
    _ = p.handle(.began, isPlaying: true)
    p.userChose()
    let v7 = p.handle(.ended(shouldResume: true), isPlaying: false)
    #expect(v7 == .none)
}

// MARK: route changes

@Test func unpluggingHeadphonesPausesButTheBuiltInSpeakerDoesNot() {
    #expect(RoutePolicy.shouldPause(oldDeviceUnavailable: true, previousOutputWasBuiltIn: false))
    #expect(!RoutePolicy.shouldPause(oldDeviceUnavailable: true, previousOutputWasBuiltIn: true))
    #expect(!RoutePolicy.shouldPause(oldDeviceUnavailable: false, previousOutputWasBuiltIn: false))   // a new device appeared
}

// MARK: background video

@Test func theVideoGoesOffInTheBackgroundAndComesBackInTheForeground() {
    var g = BackgroundVideoGate()
    #expect(g.mayDraw)
    let v8 = g.willEnterForeground()
    #expect(v8 == .none)                                       // never left: nothing to undo
    let v9 = g.didEnterBackground()
    #expect(v9 == .finishGLThenVideoOff)
    #expect(!g.mayDraw)
    let v10 = g.didEnterBackground()
    #expect(v10 == .none)                                        // a second notification does not repeat it
    let v11 = g.willEnterForeground()
    #expect(v11 == .videoAuto)
    #expect(g.mayDraw)
    let v12 = g.willEnterForeground()
    #expect(v12 == .none)
}

@Test func aViewCreatedWhileBackgroundedDrawsNothingUntilTheForeground() {
    var g = BackgroundVideoGate(inBackground: true)
    #expect(!g.mayDraw)
    let v13 = g.didEnterBackground()
    #expect(v13 == .none)
    let v14 = g.willEnterForeground()
    #expect(v14 == .videoAuto)
}

// MARK: lock screen

@Test func aMovieShowsItsTimelineOnTheLockScreen() {
    let d = NowPlayingInfo.dictionary(NowPlayingState(title: "Movie", subtitle: "Series", isLive: false, position: 61.5, duration: 5400, speed: 1.5, paused: false))
    #expect(d[MPMediaItemPropertyTitle] as? String == "Movie")
    #expect(d[MPMediaItemPropertyArtist] as? String == "Series")
    #expect(d[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double == 61.5)
    #expect(d[MPMediaItemPropertyPlaybackDuration] as? Double == 5400)
    #expect(d[MPNowPlayingInfoPropertyPlaybackRate] as? Double == 1.5)
    #expect(d[MPNowPlayingInfoPropertyIsLiveStream] as? Bool == false)
}

@Test func aLiveChannelHasNoTimelineAndAPausedOneHasRateZero() {
    let d = NowPlayingInfo.dictionary(NowPlayingState(title: "Channel", subtitle: nil, isLive: true, position: 900, duration: 0, speed: 1, paused: true))
    #expect(d[MPNowPlayingInfoPropertyIsLiveStream] as? Bool == true)
    #expect(d[MPNowPlayingInfoPropertyElapsedPlaybackTime] == nil && d[MPMediaItemPropertyPlaybackDuration] == nil)
    #expect(d[MPNowPlayingInfoPropertyPlaybackRate] as? Double == 0)
    #expect(d[MPMediaItemPropertyArtist] == nil)
}

@Test func theLockScreenIsOnlyToldWhatItCannotExtrapolate() {
    let t0 = Date(timeIntervalSince1970: 0)
    var th = NowPlayingThrottle()
    func s(_ pos: Double, paused: Bool = false, speed: Double = 1, title: String = "A") -> NowPlayingState {
        NowPlayingState(title: title, isLive: false, position: pos, duration: 600, speed: speed, paused: paused)
    }
    let v15 = th.shouldPublish(s(0), now: t0)
    #expect(v15)                                          // first time
    let v16 = th.shouldPublish(s(1.0), now: t0.addingTimeInterval(1))
    #expect(!v16)                 // playing on as expected
    let v17 = th.shouldPublish(s(10.4), now: t0.addingTimeInterval(10))
    #expect(!v17)
    let v18 = th.shouldPublish(s(10.4, paused: true), now: t0.addingTimeInterval(10))
    #expect(v18)  // pause
    let v19 = th.shouldPublish(s(10.4, paused: true), now: t0.addingTimeInterval(20))
    #expect(!v19)
    let v20 = th.shouldPublish(s(10.4, speed: 2), now: t0.addingTimeInterval(21))
    #expect(v20)      // resume at another speed
    let v21 = th.shouldPublish(s(300, speed: 2), now: t0.addingTimeInterval(22))
    #expect(v21)       // a seek
    let v22 = th.shouldPublish(s(302, speed: 2, title: "B"), now: t0.addingTimeInterval(23))
    #expect(v22)   // next episode
    th.reset()
    let v23 = th.shouldPublish(s(302, speed: 2, title: "B"), now: t0.addingTimeInterval(24))
    #expect(v23)
}
