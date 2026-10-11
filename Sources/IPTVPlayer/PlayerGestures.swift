import Foundation
import CoreGraphics

/// The numbers behind the touch gestures of the iOS player (drag to scrub, drag for brightness/volume, pinch for the video scale,
/// double tap to skip), kept out of the views so they can be tested. Garbage input (NaN, a view without size) changes nothing.
public enum PlayerGestures {
    public enum Side: Equatable { case left, right }
    public enum Axis: Equatable { case horizontal, vertical }
    public enum VerticalEnd: Equatable { case commit, dismiss }

    /// The half of the screen a touch started in (physical left/right, whatever the layout direction).
    public static func side(x: CGFloat, width: CGFloat) -> Side { x < width / 2 ? .left : .right }

    /// Which way a drag goes, decided once it moved `slop` points; nil until then. Diagonal drags go to the stronger axis.
    public static func axis(dx: CGFloat, dy: CGFloat, slop: CGFloat = 10) -> Axis? {
        guard dx.isFinite, dy.isFinite, max(abs(dx), abs(dy)) >= slop else { return nil }
        return abs(dx) >= abs(dy) ? .horizontal : .vertical
    }

    /// Seconds a drag across the whole width covers: a quarter of the duration, between a minute and ten minutes.
    public static func scrubSpan(duration: Double) -> Double {
        guard duration.isFinite, duration > 0 else { return 60 }
        return min(max(duration * 0.25, 60), 600)
    }

    /// Where a horizontal drag of `translation` points leads, from `start`, clamped to the file.
    public static func scrubTarget(start: Double, translation: CGFloat, width: CGFloat, duration: Double) -> Double {
        guard start.isFinite, translation.isFinite, width.isFinite, width > 0, duration.isFinite, duration > 0 else { return start.isFinite ? start : 0 }
        return min(max(start + Double(translation / width) * scrubSpan(duration: duration), 0), duration)
    }

    /// Brightness or volume (0...1) after a vertical drag: up raises it, three quarters of the height cover the whole range.
    public static func level(start: Double, translationY: CGFloat, height: CGFloat) -> Double {
        guard start.isFinite, translationY.isFinite, height.isFinite, height > 0 else { return min(max(start.isFinite ? start : 0, 0), 1) }
        return min(max(start - Double(translationY / (height * 0.75)), 0), 1)
    }

    /// A long, fast flick downwards closes the player; anything slower was a level adjustment (which is then kept).
    public static func verticalEnd(translationY: CGFloat, velocityY: CGFloat) -> VerticalEnd {
        translationY > 120 && velocityY > 1500 ? .dismiss : .commit
    }

    /// Pinching out steps fit -> fill -> stretch, pinching in steps back; a small pinch changes nothing.
    public static func scale(after pinch: CGFloat, from s: VideoScale) -> VideoScale {
        guard pinch.isFinite else { return s }
        if pinch >= 1.15 { return s == .fit ? .fill : .stretch }
        if pinch <= 0.87 { return s == .stretch ? .fill : .fit }
        return s
    }
}

/// Repeated double taps on one side keep adding to one skip ("+10", "+20", "+30"); another side or a pause of a second starts over.
public struct SkipAccumulator: Equatable {
    public static let window: TimeInterval = 1
    public private(set) var side: PlayerGestures.Side?
    public private(set) var count = 0
    private var last = Date.distantPast
    public init() {}

    /// True while a further tap on the same side counts as another skip instead of toggling the controls.
    public func isChaining(now: Date) -> Bool { side != nil && now.timeIntervalSince(last) < Self.window }

    /// Registers one skip of `step` seconds on `side`; returns the signed total of the chain so far (negative = backwards).
    public mutating func skip(_ s: PlayerGestures.Side, step: Int, now: Date) -> Int {
        if s == side, isChaining(now: now) { count += 1 } else { side = s; count = 1 }
        last = now
        return (s == .left ? -1 : 1) * count * step
    }

    public mutating func reset() { self = SkipAccumulator() }

    /// "+30" / "−10": numbers with a real minus sign, no unit, the same in every language.
    public static func label(_ total: Int) -> String { (total < 0 ? "\u{2212}" : "+") + String(abs(total)) }
}
