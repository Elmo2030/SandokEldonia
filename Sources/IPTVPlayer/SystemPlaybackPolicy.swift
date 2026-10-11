import Foundation
import MediaPlayer

// The decisions the iOS player takes about the system around it (calls and other apps, headphones, the lock screen, the background),
// as plain values: the app target maps AVAudioSession / UIApplication notifications onto these and does what they say.

/// Audio-session interruptions (a call, an alarm, Siri, another app taking the audio).
public enum InterruptionEvent: Equatable { case began, ended(shouldResume: Bool) }

public struct InterruptionPolicy: Equatable {
    public enum Action: Equatable { case none, pause, resume }
    private var pausedByInterruption = false
    public init() {}

    /// `isPlaying`: whether the player was playing when the event arrived. Playback is resumed after the interruption only when the
    /// interruption itself paused it and the system says resuming is appropriate (a call: yes once it ends; Siri/another music app: no).
    public mutating func handle(_ e: InterruptionEvent, isPlaying: Bool) -> Action {
        switch e {
        case .began:
            pausedByInterruption = isPlaying
            return isPlaying ? .pause : .none
        case .ended(let shouldResume):
            defer { pausedByInterruption = false }
            return pausedByInterruption && shouldResume ? .resume : .none
        }
    }

    /// The user pressed play or pause during the interruption: that choice wins over the automatic resume.
    public mutating func userChose() { pausedByInterruption = false }
}

public enum RoutePolicy {
    /// The output the audio went to disappeared: headphones unplugged, Bluetooth or AirPlay gone. A video must not start blaring from the
    /// speaker then (the system convention). The built-in speaker going away is not a thing to pause for.
    public static func shouldPause(oldDeviceUnavailable: Bool, previousOutputWasBuiltIn: Bool) -> Bool {
        oldDeviceUnavailable && !previousOutputWasBuiltIn
    }
}

/// libmpv draws through OpenGL ES, and an app that issues GLES commands in the background is terminated. While backgrounded the video
/// track is switched off (audio goes on, UIBackgroundModes audio) and nothing is drawn; in the foreground the track comes back.
public struct BackgroundVideoGate: Equatable {
    public enum Action: Equatable {
        case none
        /// Finish the GLES work in flight, then set mpv `vid` to `no`.
        case finishGLThenVideoOff
        /// Set mpv `vid` back to `auto`.
        case videoAuto
    }
    public private(set) var inBackground: Bool
    public init(inBackground: Bool = false) { self.inBackground = inBackground }

    /// Whether a frame may be drawn (any GLES call) right now.
    public var mayDraw: Bool { !inBackground }

    public mutating func didEnterBackground() -> Action {
        guard !inBackground else { return .none }
        inBackground = true
        return .finishGLThenVideoOff
    }

    public mutating func willEnterForeground() -> Action {
        guard inBackground else { return .none }
        inBackground = false
        return .videoAuto
    }
}

/// What the lock screen, Control Center and the car show: the values of `MPNowPlayingInfoCenter.nowPlayingInfo`.
public struct NowPlayingState: Equatable {
    public var title: String
    /// The programme now on (live) or the series; shown under the title.
    public var subtitle: String?
    public var isLive: Bool
    public var position: Double
    public var duration: Double
    public var speed: Double
    public var paused: Bool

    public init(title: String, subtitle: String? = nil, isLive: Bool, position: Double, duration: Double, speed: Double, paused: Bool) {
        self.title = title; self.subtitle = subtitle; self.isLive = isLive; self.position = position; self.duration = duration
        self.speed = speed; self.paused = paused
    }
}

public enum NowPlayingInfo {
    public static func dictionary(_ s: NowPlayingState) -> [String: Any] {
        var d: [String: Any] = [
            MPMediaItemPropertyTitle: s.title,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
            MPNowPlayingInfoPropertyIsLiveStream: s.isLive,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyPlaybackRate: s.paused ? 0.0 : s.speed,
        ]
        if let sub = s.subtitle, !sub.isEmpty { d[MPMediaItemPropertyArtist] = sub }
        if !s.isLive {   // a live stream has no timeline: no elapsed time and no duration, or the lock screen draws a scrubber
            d[MPNowPlayingInfoPropertyElapsedPlaybackTime] = max(s.position, 0)
            if s.duration > 0 { d[MPMediaItemPropertyPlaybackDuration] = s.duration }
        }
        return d
    }
}

/// The system extrapolates the elapsed time from the rate, so the info is only published when something it cannot extrapolate changes:
/// the title, pause/speed, the duration, or a jump of the position (a seek).
public struct NowPlayingThrottle {
    private var last: NowPlayingState?
    private var lastAt = Date.distantPast
    public init() {}

    public mutating func shouldPublish(_ s: NowPlayingState, now: Date) -> Bool {
        defer { if publishNeeded(s, now: now) { last = s; lastAt = now } }
        return publishNeeded(s, now: now)
    }

    public mutating func reset() { last = nil }

    private func publishNeeded(_ s: NowPlayingState, now: Date) -> Bool {
        guard let l = last else { return true }
        if l.title != s.title || l.subtitle != s.subtitle || l.isLive != s.isLive || l.paused != s.paused || l.speed != s.speed { return true }
        if abs(l.duration - s.duration) > 1 { return true }
        let expected = l.position + (l.paused ? 0 : now.timeIntervalSince(lastAt) * l.speed)
        return !s.isLive && abs(s.position - expected) > 2
    }
}
