import Foundation

// Small state machines behind the playback controller, kept free of mpv and of the clock so they can be tested exactly.

/// A live stream that dropped is reloaded up to `maxRetries` times, `delay` seconds apart; a stream that plays again gets a fresh budget.
public struct LiveRecovery: Equatable {
    public static let maxRetries = 3
    public static let delay: TimeInterval = 2
    public private(set) var retries = 0
    private var lastPosition = 0.0
    public init() {}

    /// A tick while the stream plays: moving forward by more than half a second refreshes the retry budget.
    public mutating func observe(position: Double) {
        if position > lastPosition + 0.5 { retries = 0; lastPosition = position }
    }

    /// The stream failed. True = reload after `delay`; false = the budget is spent, show the error.
    public mutating func failed() -> Bool {
        guard retries < Self.maxRetries else { return false }
        retries += 1
        return true
    }

    /// After a reload time-pos restarts at 0: the position bookkeeping starts over, the retry count stays until playback moves again.
    public mutating func reloaded() { lastPosition = 0 }

    public mutating func reset() { self = LiveRecovery() }
}

/// "The movie reached its end" with hysteresis: only the real end of the file counts (a connection cut early also sets eof-reached),
/// and only a change is reported (true when it ends, false when it leaves the end again, e.g. after a seek back).
public struct EndOfMedia: Equatable {
    /// Within this many seconds of the duration counts as the end (credits, rounding of mpv's duration).
    public static let tail = 15.0
    public private(set) var atEnd = false
    public init() {}

    public mutating func observe(atEOF: Bool, position: Double, duration: Double) -> Bool? {
        let now = atEOF && duration > 0 && position >= duration - Self.tail
        guard now != atEnd else { return nil }
        atEnd = now
        return now
    }

    /// A new file starts: the old one may still report its end for a tick, so only a real false -> true change counts afterwards.
    public mutating func newFile() { atEnd = true }
}

/// A paused live stream goes stale (the provider cuts the connection, the cache holds old data): resuming after a while reloads it.
public struct PauseClock: Equatable {
    public static let staleAfter: TimeInterval = 20
    private var since: Date?
    public init() {}

    public mutating func paused(at now: Date) { if since == nil { since = now } }

    /// Playing again. True when a live stream was paused long enough to need a reload.
    public mutating func resumed(at now: Date, isLive: Bool) -> Bool {
        defer { since = nil }
        guard isLive, let s = since else { return false }
        return now.timeIntervalSince(s) >= Self.staleAfter
    }

    public mutating func reset() { since = nil }
}

/// The controls fade out `hideAfter` seconds after the last touch (0 = never). Something that needs them (paused, scrubbing, a sheet,
/// an error, VoiceOver) holds them on screen and restarts the countdown.
public struct ControlsVisibility: Equatable {
    public var hideAfter: TimeInterval
    public private(set) var shown = true
    private var touched: Date

    public init(hideAfter: TimeInterval = 3, now: Date = Date()) { self.hideAfter = hideAfter; touched = now }

    public mutating func touch(now: Date) { shown = true; touched = now }
    public mutating func toggle(now: Date) { if shown { shown = false } else { touch(now: now) } }
    public mutating func hide() { shown = false }

    public mutating func tick(now: Date, holding: Bool) {
        if holding { touched = now; return }
        if shown, hideAfter > 0, now.timeIntervalSince(touched) >= hideAfter { shown = false }
    }
}
