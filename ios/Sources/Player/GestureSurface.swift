import SwiftUI
import UIKit
import IPTVPlayer

/// The touch layer over the picture: tap, double tap, drag, pinch and long press, as UIKit recognizers (SwiftUI cannot make a double
/// tap wait for the single tap, or tell a drag's axis, as cleanly). It is transparent and sits under the controls, so buttons win.
struct GestureSurface: UIViewRepresentable {
    struct Handlers {
        var singleTap: (PlayerGestures.Side) -> Void
        var doubleTap: (PlayerGestures.Side) -> Void
        var scrubBegan: () -> Void
        var scrubChanged: (_ translation: CGFloat, _ width: CGFloat) -> Void
        var scrubEnded: (_ commit: Bool) -> Void
        var levelBegan: (PlayerGestures.Side) -> Void
        var levelChanged: (PlayerGestures.Side, _ translationY: CGFloat, _ height: CGFloat) -> Void
        var levelEnded: (PlayerGestures.Side, _ translationY: CGFloat, _ velocityY: CGFloat) -> Void
        var pinchEnded: (CGFloat) -> Void
        var hold: (Bool) -> Void
    }

    let handlers: Handlers
    /// Live streams have no timeline: no scrubbing, no skipping.
    let live: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .clear
        let c = context.coordinator
        let single = UITapGestureRecognizer(target: c, action: #selector(Coordinator.single(_:)))
        let double = UITapGestureRecognizer(target: c, action: #selector(Coordinator.double(_:)))
        double.numberOfTapsRequired = 2
        single.require(toFail: double)
        let pan = UIPanGestureRecognizer(target: c, action: #selector(Coordinator.pan(_:)))
        pan.maximumNumberOfTouches = 1
        let pinch = UIPinchGestureRecognizer(target: c, action: #selector(Coordinator.pinch(_:)))
        let hold = UILongPressGestureRecognizer(target: c, action: #selector(Coordinator.hold(_:)))
        hold.minimumPressDuration = 0.5
        hold.allowableMovement = 12
        for g in [single, double, pan, pinch, hold] as [UIGestureRecognizer] { g.delegate = c; v.addGestureRecognizer(g) }
        c.pan = pan; c.hold = hold
        // VoiceOver users use the controls, which stay on screen for them.
        v.isAccessibilityElement = false
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.handlers = handlers
        context.coordinator.live = live
    }

    @MainActor final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var handlers: Handlers?
        var live = false
        weak var pan: UIPanGestureRecognizer?
        weak var hold: UILongPressGestureRecognizer?
        private var axis: PlayerGestures.Axis?
        private var side = PlayerGestures.Side.left
        private var holding = false

        private func side(of g: UIGestureRecognizer) -> PlayerGestures.Side {
            guard let v = g.view else { return .left }
            return PlayerGestures.side(x: g.location(in: v).x, width: v.bounds.width)
        }

        @objc func single(_ g: UITapGestureRecognizer) { if g.state == .ended { handlers?.singleTap(side(of: g)) } }
        @objc func double(_ g: UITapGestureRecognizer) { if g.state == .ended { handlers?.doubleTap(side(of: g)) } }

        @objc func pan(_ g: UIPanGestureRecognizer) {
            guard let v = g.view, let h = handlers else { return }
            let t = g.translation(in: v)
            switch g.state {
            case .began:
                axis = nil
                side = PlayerGestures.side(x: g.location(in: v).x - t.x, width: v.bounds.width)   // where the finger went down
            case .changed:
                if axis == nil {
                    axis = PlayerGestures.axis(dx: t.x, dy: t.y)
                    switch axis {
                    case .horizontal: if !live { h.scrubBegan() }
                    case .vertical: h.levelBegan(side)
                    case nil: break
                    }
                }
                switch axis {
                case .horizontal: if !live { h.scrubChanged(t.x, v.bounds.width) }
                case .vertical: h.levelChanged(side, t.y, v.bounds.height)
                case nil: break
                }
            case .ended, .cancelled, .failed:
                switch axis {
                case .horizontal: if !live { h.scrubEnded(g.state == .ended) }
                case .vertical: h.levelEnded(side, t.y, g.velocity(in: v).y)
                case nil: break
                }
                axis = nil
            default: break
            }
        }

        @objc func pinch(_ g: UIPinchGestureRecognizer) { if g.state == .ended { handlers?.pinchEnded(g.scale) } }

        @objc func hold(_ g: UILongPressGestureRecognizer) {
            switch g.state {
            case .began: holding = true; handlers?.hold(true)
            case .ended, .cancelled, .failed: if holding { holding = false; handlers?.hold(false) }
            default: break
            }
        }

        // A drag does not start while the long press is held (2x playback), and the pinch is its own thing.
        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool { g === pan ? !holding : true }
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { false }
    }
}
