#if os(iOS)
import UIKit
import AVKit
import CoreMedia
import CoreVideo
import CLibMPViOS

/// Picture in Picture for the iOS player (Apple's custom renderer route, WWDC21 10290).
///
/// libmpv's OpenGL ES output cannot feed `AVPictureInPictureController`, and an app that issues GLES commands in the background is
/// terminated. So while PiP is on, `MPVVideoView` swaps mpv's render context for a *software* one (`MPV_RENDER_API_TYPE_SW`, CPU only,
/// legal in the background): every frame is rendered, scaled down to the PiP size, into a BGRA `CVPixelBuffer`, wrapped in a
/// `CMSampleBuffer` and enqueued on `layer`. mpv keeps playing the audio. Frames are shown immediately; the layer's control timebase only
/// feeds the position/duration of the PiP window's own controls.
final class MPVPiPOutput: NSObject {
    /// The commands of the PiP window's buttons, answered by the player.
    struct Commands {
        var setPlaying: (Bool) -> Void = { _ in }
        var skip: (Double) -> Void = { _ in }
        /// The user tapped "back to app" in the PiP window.
        var restore: () -> Void = {}
    }

    let layer = AVSampleBufferDisplayLayer()
    var commands = Commands()
    /// PiP started (true) or ended (false, by the user's close button, restoring, or a failure).
    var onActiveChange: ((_ active: Bool, _ restored: Bool) -> Void)?

    private let player: MPVPlayer
    private let queue = DispatchQueue(label: "iptvmac.pip.render", qos: .userInitiated)
    private var render: OpaquePointer?                 // touched on `queue` once created
    private var pool: CVPixelBufferPool?
    private var poolSize = (width: 0, height: 0)
    private var pip: AVPictureInPictureController?
    private var wantsStart = false
    private var restoring = false
    private var timebase: CMTimebase?
    private var state = (position: 0.0, duration: 0.0, paused: false, speed: 1.0, live: false)
    private let lock = NSLock()
    private var _videoSize = (width: 0.0, height: 0.0)
    private var _frames = 0

    /// The video's display size, set from the main thread (mpv's properties must not be read on the render queue).
    var videoSize: (width: Double, height: Double) {
        get { lock.withLock { _videoSize } }
        set { lock.withLock { _videoSize = newValue } }
    }
    /// Frames enqueued so far (tests and the debug status).
    var frames: Int { lock.withLock { _frames } }
    private(set) var active = false

    var autoStartFlag: Bool? { pip?.canStartPictureInPictureAutomaticallyFromInline }

    static var supported: Bool { AVPictureInPictureController.isPictureInPictureSupported() }

    init(player: MPVPlayer) {
        self.player = player
        super.init()
        layer.videoGravity = .resizeAspect
        layer.backgroundColor = UIColor.black.cgColor
        var tb: CMTimebase?
        CMTimebaseCreateWithSourceClock(allocator: nil, sourceClock: CMClockGetHostTimeClock(), timebaseOut: &tb)
        if let tb { CMTimebaseSetTime(tb, time: .zero); CMTimebaseSetRate(tb, rate: 0); layer.controlTimebase = tb; timebase = tb }
        let source = AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer: layer, playbackDelegate: self)
        let c = AVPictureInPictureController(contentSource: source)
        c.delegate = self
        c.canStartPictureInPictureAutomaticallyFromInline = false   // only the button: automatic start needs the software renderer already running
        pip = c
    }

    // MARK: software render context

    /// Creates mpv's software render context (the OpenGL one must be gone). Returns false when mpv refuses.
    func startRendering() -> Bool {
        guard render == nil else { return true }
        var ctx: OpaquePointer?
        let ok: Bool = "sw".withCString { api in
            var params = [mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: UnsafeMutableRawPointer(mutating: api)),
                          mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil)]
            return mpv_render_context_create(&ctx, player.handle, &params) >= 0
        }
        guard ok, let ctx else { return false }
        queue.sync { render = ctx }
        mpv_render_context_set_update_callback(ctx, { raw in
            let o = Unmanaged<MPVPiPOutput>.fromOpaque(raw!).takeUnretainedValue()
            o.queue.async { o.renderFrame() }
        }, Unmanaged.passUnretained(self).toOpaque())
        return true
    }

    /// Frees the software render context (call after setting mpv `vid` to `no`).
    func stopRendering() {
        queue.sync {
            guard let r = render else { return }
            render = nil
            mpv_render_context_set_update_callback(r, nil, nil)
            mpv_render_context_free(r)
            pool = nil; poolSize = (0, 0)
        }
    }

    private func renderFrame() {
        guard let render else { return }
        let flags = mpv_render_context_update(render)
        guard flags & UInt64(MPV_RENDER_UPDATE_FRAME.rawValue) != 0 else { return }
        let vs = videoSize
        let size = PiPFrameSize.fit(videoWidth: vs.width, videoHeight: vs.height)
        if pool == nil || poolSize != size {
            let attrs: [CFString: Any] = [kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey: size.width,
                                          kCVPixelBufferHeightKey: size.height, kCVPixelBufferIOSurfacePropertiesKey: [String: Any]()]
            var p: CVPixelBufferPool?
            CVPixelBufferPoolCreate(nil, nil, attrs as CFDictionary, &p)
            pool = p; poolSize = size
        }
        guard let pool else { return }
        var pb: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb)
        guard let pb else { return }
        CVPixelBufferLockBaseAddress(pb, [])
        var dims: [Int32] = [Int32(size.width), Int32(size.height)]
        var stride = CVPixelBufferGetBytesPerRow(pb)
        let base = CVPixelBufferGetBaseAddress(pb)
        "bgr0".withCString { fmt in
            dims.withUnsafeMutableBufferPointer { d in
                withUnsafeMutablePointer(to: &stride) { s in
                    var params = [mpv_render_param(type: MPV_RENDER_PARAM_SW_SIZE, data: UnsafeMutableRawPointer(d.baseAddress)),
                                  mpv_render_param(type: MPV_RENDER_PARAM_SW_FORMAT, data: UnsafeMutableRawPointer(mutating: fmt)),
                                  mpv_render_param(type: MPV_RENDER_PARAM_SW_STRIDE, data: UnsafeMutableRawPointer(s)),
                                  mpv_render_param(type: MPV_RENDER_PARAM_SW_POINTER, data: base),
                                  mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil)]
                    mpv_render_context_render(render, &params)
                }
            }
        }
        CVPixelBufferUnlockBaseAddress(pb, [])
        enqueue(pb)
    }

    private func enqueue(_ pb: CVPixelBuffer) {
        var format: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: pb, formatDescriptionOut: &format)
        guard let format else { return }
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()), decodeTimeStamp: .invalid)
        var sb: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: pb, formatDescription: format, sampleTiming: &timing, sampleBufferOut: &sb)
        guard let sb else { return }
        if let a = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: true), CFArrayGetCount(a) > 0 {
            let d = unsafeBitCast(CFArrayGetValueAtIndex(a, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(d, Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        let r = layer.sampleBufferRenderer
        if r.status == .failed { r.flush() }
        guard r.isReadyForMoreMediaData else { return }      // the window is not keeping up: drop the frame
        r.enqueue(sb)
        lock.withLock { _frames += 1 }
    }

    // MARK: Picture in Picture window

    /// Starts the window once frames flow into `layer` and the system says it is possible. `startPictureInPicture()` called too early
    /// fails silently ("status = 0"), so it is retried every 0.4 s (at most 25 times) until the window is up.
    func start() {
        wantsStart = true
        startAttempts = 0
        attemptStart()
    }

    private var startAttempts = 0

    private func attemptStart() {
        guard wantsStart, let pip, !pip.isPictureInPictureActive else { return }
        startAttempts += 1
        if startAttempts > 25 { wantsStart = false; onActiveChange?(false, false); return }
        if pip.isPictureInPicturePossible && frames > 2 { pip.startPictureInPicture() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.attemptStart() }
    }

    func stop() {
        wantsStart = false
        pip?.stopPictureInPicture()
    }

    /// The player's position, rate and length for the window's own controls (called about four times a second).
    func sync(position: Double, duration: Double, paused: Bool, speed: Double, live: Bool) {
        let changed = state.paused != paused || state.live != live || abs(state.duration - duration) > 0.5 || state.speed != speed
        let drifted: Bool = {
            guard let tb = timebase else { return false }
            return abs(CMTimeGetSeconds(CMTimebaseGetTime(tb)) - position) > 0.75
        }()
        state = (position, duration, paused, speed, live)
        if let tb = timebase, changed || drifted {
            CMTimebaseSetTime(tb, time: CMTime(seconds: max(0, position), preferredTimescale: 600))
            CMTimebaseSetRate(tb, rate: paused ? 0 : speed)
        }
        if changed && active { pip?.invalidatePlaybackState() }
    }

}

extension MPVPiPOutput: AVPictureInPictureSampleBufferPlaybackDelegate {
    func pictureInPictureController(_ c: AVPictureInPictureController, setPlaying playing: Bool) {
        commands.setPlaying(playing)
    }

    func pictureInPictureControllerTimeRangeForPlayback(_ c: AVPictureInPictureController) -> CMTimeRange {
        if state.live || state.duration <= 0 { return CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity) }   // no timeline
        return CMTimeRange(start: .zero, duration: CMTime(seconds: state.duration, preferredTimescale: 600))
    }

    func pictureInPictureControllerIsPlaybackPaused(_ c: AVPictureInPictureController) -> Bool { state.paused }

    func pictureInPictureController(_ c: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}

    func pictureInPictureController(_ c: AVPictureInPictureController, skipByInterval skipInterval: CMTime, completion completionHandler: @escaping () -> Void) {
        commands.skip(CMTimeGetSeconds(skipInterval))
        completionHandler()
    }
}

extension MPVPiPOutput: AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerDidStartPictureInPicture(_ c: AVPictureInPictureController) {
        active = true
        wantsStart = false
        onActiveChange?(true, false)
    }

    func pictureInPictureController(_ c: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        wantsStart = false
        active = false
        onActiveChange?(false, false)
    }

    func pictureInPictureController(_ c: AVPictureInPictureController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        restoring = true
        commands.restore()
        completionHandler(true)
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ c: AVPictureInPictureController) {
        let restored = restoring
        restoring = false
        active = false
        onActiveChange?(false, restored)
    }
}
#endif
