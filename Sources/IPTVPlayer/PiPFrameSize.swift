import Foundation

/// Size of the frames rendered for the Picture in Picture window. The window is small, so the video is scaled down on the CPU
/// (mpv's software renderer) instead of rendering at full size: same aspect ratio, at most `maxWidth` wide, even numbers (video).
public enum PiPFrameSize {
    public static let maxWidth = 960
    public static let fallback = (width: 640, height: 360)

    public static func fit(videoWidth: Double, videoHeight: Double, maxWidth: Int = PiPFrameSize.maxWidth) -> (width: Int, height: Int) {
        guard videoWidth >= 2, videoHeight >= 2, videoWidth.isFinite, videoHeight.isFinite else { return fallback }
        let w = min(Double(maxWidth), videoWidth)
        let h = w * videoHeight / videoWidth
        return (max(2, Int(w) & ~1), max(2, Int(h.rounded()) & ~1))
    }
}
