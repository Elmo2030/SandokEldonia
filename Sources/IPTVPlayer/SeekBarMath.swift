import Foundation
import CoreGraphics

/// The numbers behind the seek bar and its hover bubble, kept out of the views so they can be tested.
public enum SeekBarMath {
    /// 0...1 for a pointer at `x` on a bar `width` wide; garbage (NaN, infinity, a bar without width) is 0.
    public static func fraction(x: CGFloat, width: CGFloat) -> Double {
        guard x.isFinite, width.isFinite, width > 0 else { return 0 }
        return min(max(Double(x / width), 0), 1)
    }

    public static func fraction(of value: Double, in total: Double) -> Double {
        guard value.isFinite, total.isFinite, total > 0 else { return 0 }
        return min(max(value / total, 0), 1)
    }

    public static func time(x: CGFloat, width: CGFloat, duration: Double) -> Double {
        duration.isFinite && duration > 0 ? fraction(x: x, width: width) * duration : 0
    }

    /// Left edge of the bubble in the player's coordinates: centred on the marker, `margin` away from both edges of the player.
    /// A bubble wider than the player sticks to the left margin.
    public static func bubbleLeft(center: CGFloat, width: CGFloat, container: CGFloat, margin: CGFloat) -> CGFloat {
        max(margin, min(center - width / 2, container - width - margin))
    }

    /// Where the bubble's little pointer sits inside the bubble: under the marker, but `inset` away from the rounded corners.
    public static func pointerX(center: CGFloat, left: CGFloat, width: CGFloat, inset: CGFloat) -> CGFloat {
        max(inset, min(center - left, width - inset))
    }

    /// "1:05", or "1:02:05" from one hour on.
    public static func format(_ seconds: Double) -> String {
        let t = seconds.isFinite ? Int(max(seconds, 0)) : 0
        return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, t % 3600 / 60, t % 60) : String(format: "%d:%02d", t / 60, t % 60)
    }
}
