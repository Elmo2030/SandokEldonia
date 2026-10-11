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
    private var backgrounded = false
    private var observers: [NSObjectProtocol] = []
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
        guard ok, let render else { return }
        mpv_render_context_set_update_callback(render, { ctx in
            let v = Unmanaged<MPVVideoView>.fromOpaque(ctx!).takeUnretainedValue()
            DispatchQueue.main.async { v.drawFrame() }
        }, Unmanaged.passUnretained(self).toOpaque())
        player.onTeardown = { [weak self] in self?.shutdown() }

        // An app that issues OpenGL ES commands in the background is terminated by iOS. The video track is switched off
        // while backgrounded (audio keeps playing, UIBackgroundModes audio) and back on in the foreground.
        let nc = NotificationCenter.default
        observers = [
            nc.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                self.backgrounded = true
                EAGLContext.setCurrent(self.gl); glFinish()
                self.player.setProperty("vid", "no")
            },
            nc.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                self.backgrounded = false
                self.player.setProperty("vid", "auto")
                self.setNeedsLayout()
            },
        ]
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    public override func layoutSubviews() { super.layoutSubviews(); drawFrame() }

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
        guard let render, !backgrounded, window != nil || superview != nil else { return }
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
        if let onFrame {
            var px = [UInt8](repeating: 0, count: 4)
            glReadPixels(GLint(bufferSize.width / 2), GLint(bufferSize.height / 2), 1, 1, GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), &px)
            onFrame(px[0], px[1], px[2])
        }
        glBindRenderbuffer(GLenum(GL_RENDERBUFFER), rbo)
        gl.presentRenderbuffer(Int(GL_RENDERBUFFER))
    }

    public func shutdown() {
        guard let r = render else { return }
        render = nil
        EAGLContext.setCurrent(gl)
        mpv_render_context_set_update_callback(r, nil, nil)
        mpv_render_context_free(r)
        if fbo != 0 { glDeleteFramebuffers(1, &fbo); glDeleteRenderbuffers(1, &rbo); fbo = 0; rbo = 0 }
    }
}
#endif
