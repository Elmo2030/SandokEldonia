#if os(iOS)
import UIKit
import OpenGLES
import CLibMPViOS

// iOS twin of MPVVideoView.swift (NSOpenGLView): same public API, drawn through the libmpv OpenGL render API on an OpenGL ES 3
// context (the only render path of the media-kit iOS build: mpv built with -Dgl -Dios-gl, no Vulkan, no Metal).
// OpenGL ES is deprecated since iOS 12 but still in the SDK; the app target sets GLES_SILENCE_DEPRECATION.

private func getProcAddress(_ ctx: UnsafeMutableRawPointer?, _ name: UnsafePointer<CChar>?) -> UnsafeMutableRawPointer? {
    guard let name else { return nil }
    let bundle = CFBundleGetBundleWithIdentifier("com.apple.opengles" as CFString)
    return CFBundleGetFunctionPointerForName(bundle, String(cString: name) as CFString)
}

public final class MPVVideoView: UIView {
    public override class var layerClass: AnyClass { CAEAGLLayer.self }

    private let player: MPVPlayer
    private var render: OpaquePointer?
    private let gl: EAGLContext
    private var fbo: GLuint = 0
    private var rbo: GLuint = 0
    private var bufferSize = CGSize.zero
    private var gate = BackgroundVideoGate()   // the tested state machine behind the two notifications below
    private var observers: [NSObjectProtocol] = []
    /// Which render context mpv has: OpenGL ES (on screen), software (Picture in Picture window), or none (backgrounded without PiP).
    private enum Output { case gl, pip, off }
    private var output = Output.gl
    private var pipOutput: MPVPiPOutput?
    /// Picture in Picture started (true) or ended (false). Ending in the background pauses (the window's close button).
    public var onPiPChange: ((Bool) -> Void)?
    public var pipCommands: (setPlaying: (Bool) -> Void, skip: (Double) -> Void, restore: () -> Void) = ({ _ in }, { _ in }, {}) {
        didSet { pipOutput?.commands = .init(setPlaying: pipCommands.setPlaying, skip: pipCommands.skip, restore: pipCommands.restore) }
    }
    /// Test seam kept for parity with the macOS view: centre pixel (r, g, b) of every frame right after mpv draws it.
    public var onFrame: ((UInt8, UInt8, UInt8) -> Void)?

    public init(player: MPVPlayer) {
        self.player = player
        guard let ctx = EAGLContext(api: .openGLES3) else { fatalError("OpenGL ES 3 is not available") }
        gl = ctx
        super.init(frame: .zero)
        isOpaque = true
        backgroundColor = .black
        contentScaleFactor = UIScreen.main.scale
        (layer as! CAEAGLLayer).drawableProperties = [kEAGLDrawablePropertyRetainedBacking: false,
                                                      kEAGLDrawablePropertyColorFormat: kEAGLColorFormatRGBA8]
        EAGLContext.setCurrent(gl)

        guard makeGLContext() else { return }
        player.onTeardown = { [weak self] in self?.shutdown() }

        // An app that issues OpenGL ES commands in the background is terminated by iOS. The video track is switched off
        // while backgrounded (audio keeps playing, UIBackgroundModes audio) and back on in the foreground (BackgroundVideoGate).
        gate = BackgroundVideoGate(inBackground: UIApplication.shared.applicationState == .background)
        let nc = NotificationCenter.default
        observers = [
            nc.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
                guard let self, self.gate.didEnterBackground() == .finishGLThenVideoOff, self.output == .gl else { return }   // PiP keeps drawing without GLES
                EAGLContext.setCurrent(self.gl); glFinish()
                self.player.setProperty("vid", "no")
            },
            nc.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
                guard let self, self.gate.willEnterForeground() == .videoAuto else { return }
                switch self.output {
                case .pip: break                                   // the window is still up; it switches back when it ends
                case .off: self.switchTo(.gl)
                case .gl: self.player.setProperty("vid", "auto"); self.setNeedsLayout()
                }
            },
        ]
    }


    /// Creates mpv's OpenGL render context on this view's EAGL context (the software one must be gone).
    private func makeGLContext() -> Bool {
        EAGLContext.setCurrent(gl)
        let ok: Bool = "opengl".withCString { api in
            var initParams = mpv_opengl_init_params(get_proc_address: getProcAddress, get_proc_address_ctx: nil)
            return withUnsafeMutablePointer(to: &initParams) { ip in
                var params = [
                    mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: UnsafeMutableRawPointer(mutating: api)),
                    mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, data: ip),
                    mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
                ]
                return mpv_render_context_create(&render, player.handle, &params) >= 0
            }
        }
        guard ok, let render else { return false }
        mpv_render_context_set_update_callback(render, { ctx in
            let v = Unmanaged<MPVVideoView>.fromOpaque(ctx!).takeUnretainedValue()
            DispatchQueue.main.async { v.drawFrame() }
        }, Unmanaged.passUnretained(self).toOpaque())
        return true
    }

    private func freeGLContext() {
        guard let r = render else { return }
        render = nil
        EAGLContext.setCurrent(gl)
        glFinish()
        mpv_render_context_set_update_callback(r, nil, nil)
        mpv_render_context_free(r)
        if fbo != 0 { glDeleteFramebuffers(1, &fbo); glDeleteRenderbuffers(1, &rbo); fbo = 0; rbo = 0; bufferSize = .zero }
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    public override func layoutSubviews() {
        super.layoutSubviews()
        pipOutput?.layer.frame = bounds
        drawFrame()
    }

    /// (Re)creates the renderbuffer-backed framebuffer when the layer size changes.
    private func ensureBuffers() {
        let px = CGSize(width: bounds.width * contentScaleFactor, height: bounds.height * contentScaleFactor)
        guard px.width > 0, px.height > 0, px != bufferSize else { return }
        if fbo == 0 { glGenFramebuffers(1, &fbo); glGenRenderbuffers(1, &rbo) }
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), fbo)
        glBindRenderbuffer(GLenum(GL_RENDERBUFFER), rbo)
        gl.renderbufferStorage(Int(GL_RENDERBUFFER), from: layer as? EAGLDrawable)
        glFramebufferRenderbuffer(GLenum(GL_FRAMEBUFFER), GLenum(GL_COLOR_ATTACHMENT0), GLenum(GL_RENDERBUFFER), rbo)
        bufferSize = px
    }

    private func drawFrame() {
        guard let render, output == .gl, gate.mayDraw, window != nil || superview != nil else { return }
        EAGLContext.setCurrent(gl)
        ensureBuffers()
        guard bufferSize.width > 0 else { return }
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), fbo)
        var data = mpv_opengl_fbo(fbo: Int32(fbo), w: Int32(bufferSize.width), h: Int32(bufferSize.height), internal_format: 0)
        var flip: Int32 = 1
        withUnsafeMutablePointer(to: &data) { d in
            withUnsafeMutablePointer(to: &flip) { f in
                var params = [
                    mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_FBO, data: d),
                    mpv_render_param(type: MPV_RENDER_PARAM_FLIP_Y, data: f),
                    mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
                ]
                mpv_render_context_render(render, &params)
            }
        }
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), fbo)      // mpv leaves its own framebuffer bound; read (and present) ours
        if let onFrame {
            var px = [UInt8](repeating: 0, count: 4)
            glReadPixels(GLint(bufferSize.width / 2), GLint(bufferSize.height / 2), 1, 1, GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), &px)
            onFrame(px[0], px[1], px[2])
        }
        if let path = snapshotPath { snapshotPath = nil; writeSnapshot(to: path) }
        glBindRenderbuffer(GLenum(GL_RENDERBUFFER), rbo)
        gl.presentRenderbuffer(Int(GL_RENDERBUFFER))
    }

    /// Debug: the next drawn frame is saved as a PNG (what the GL framebuffer holds, before it is presented).
    public var snapshotPath: String?

    private func writeSnapshot(to path: String) {
        let w = Int(bufferSize.width), h = Int(bufferSize.height)
        var px = [UInt8](repeating: 0, count: w * h * 4)
        glReadPixels(0, 0, GLsizei(w), GLsizei(h), GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), &px)
        var rows = [UInt8](); rows.reserveCapacity(px.count)
        for y in stride(from: h - 1, through: 0, by: -1) { rows += px[(y * w * 4)..<((y + 1) * w * 4)] }       // GL rows start at the bottom
        guard let provider = CGDataProvider(data: Data(rows) as CFData),
              let img = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider, decode: nil,
                                shouldInterpolate: false, intent: .defaultIntent) else { return }
        try? UIImage(cgImage: img).pngData()?.write(to: URL(fileURLWithPath: path))
    }

    public func shutdown() {
        pipOutput?.stop()
        pipOutput?.onActiveChange = nil
        pipOutput?.stopRendering()
        pipOutput?.layer.removeFromSuperlayer()
        pipOutput = nil
        freeGLContext()
    }

    // MARK: Picture in Picture

    public static var pipSupported: Bool { MPVPiPOutput.supported }
    public var pipActive: Bool { pipOutput?.active ?? false }
    /// Frames the software renderer has delivered to the PiP layer (debug status, tests).
    public var pipFrames: Int { pipOutput?.frames ?? 0 }
    public var pipAutoFlag: Bool? { pipOutput?.autoStartFlag }
    public var pipMode: String { switch output { case .gl: "gl"; case .pip: "pip"; case .off: "off" } }

    /// Switches mpv to the software renderer and opens the PiP window over the app. False when the device cannot do it.
    @discardableResult
    public func startPiP() -> Bool {
        guard MPVPiPOutput.supported, UIApplication.shared.applicationState == .active else { return false }
        if pipOutput == nil {
            let o = MPVPiPOutput(player: player)
            o.commands = .init(setPlaying: pipCommands.setPlaying, skip: pipCommands.skip, restore: pipCommands.restore)
            o.layer.frame = bounds
            o.onActiveChange = { [weak self] active, restored in self?.pipChanged(active, restored: restored) }
            pipOutput = o
        }
        guard let o = pipOutput else { return false }
        layer.addSublayer(o.layer)                               // only on screen while PiP mode is on: otherwise iOS may start it by itself
        guard switchTo(.pip) else { o.layer.removeFromSuperlayer(); return false }
        o.start()
        return true
    }

    public func stopPiP() { pipOutput?.stop() }

    /// Position, rate and length for the PiP window's controls; the video size for its frames.
    public func syncPiP(position: Double, duration: Double, paused: Bool, speed: Double, live: Bool) {
        guard let o = pipOutput else { return }
        o.videoSize = (player.double("video-params/dw") ?? 0, player.double("video-params/dh") ?? 0)
        o.sync(position: position, duration: duration, paused: paused, speed: speed, live: live)
    }

    private func pipChanged(_ active: Bool, restored: Bool) {
        if !active {
            pipOutput?.layer.removeFromSuperlayer()
            if UIApplication.shared.applicationState == .background {
                switchTo(.off)                                     // closed with its X while the app is away: no video, and stop the sound too
                if !restored { pipCommands.setPlaying(false) }
            } else {
                switchTo(.gl)
            }
        }
        onPiPChange?(active)
    }

    /// Swaps mpv's render context. The video track goes off while no context exists, then back on with the new one;
    /// the software path needs frames in system memory (`videotoolbox-copy`) and `sw-fast` to keep up.
    @discardableResult
    private func switchTo(_ target: Output) -> Bool {
        guard target != output else { return true }
        player.setProperty("vid", "no")
        switch output {
        case .gl: freeGLContext()
        case .pip: pipOutput?.stopRendering()
        case .off: break
        }
        var ok = true
        switch target {
        case .gl:
            player.setProperty("hwdec", "videotoolbox"); player.setProperty("sw-fast", "no")
            ok = makeGLContext()
            if ok { player.setProperty("vid", "auto"); setNeedsLayout() }
        case .pip:
            player.setProperty("hwdec", "videotoolbox-copy"); player.setProperty("sw-fast", "yes")
            ok = pipOutput?.startRendering() ?? false
            if ok { player.setProperty("vid", "auto") }
        case .off: break
        }
        if ok { output = target } else {                         // could not set the new one up: go back to the picture that worked
            output = .off
            if target != .gl { switchTo(.gl) }
        }
        return ok
    }
}
#endif
