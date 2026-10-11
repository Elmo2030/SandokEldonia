import SwiftUI
import IPTVPlayer

/// The progress bar: touch or drag to seek, with a bubble above the thumb (a frame from the movie when the source allows previews,
/// else only the time). It runs left to right in every language, like the bar of any video player. The maths are SeekBarMath (shared, tested).
struct PlayerSeekBar: View {
    let position: Double
    let duration: Double
    let preview: SeekPreview
    /// Width of the player the bubble has to stay inside.
    let containerWidth: CGFloat
    @Binding var scrubbing: Bool
    let onSeek: (Double) -> Void
    /// The time under the finger, for the thumbnail.
    let onScrub: (Double) -> Void
    /// Accessibility: +1 / -1 skip step.
    let onSkip: (Double) -> Void

    @State private var dragFraction: Double?
    @State private var settling: Double?            // the fraction just seeked to, shown until the player catches up
    @State private var size = CGSize(width: 1, height: 44)
    @State private var frame = CGRect.zero          // in the "player" coordinate space
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let height: CGFloat = 44
    private static let margin: CGFloat = 8

    private var width: CGFloat { max(size.width, 1) }
    private var fraction: Double { dragFraction ?? settling ?? SeekBarMath.fraction(of: position, in: duration) }

    var body: some View {
        let dragging = dragFraction != nil
        let h: CGFloat = dragging ? 8 : 4
        let thumb: CGFloat = dragging ? 20 : 12
        ZStack(alignment: .leading) {
            Capsule().fill(.white.opacity(0.28)).frame(height: h)
            Capsule().fill(.white).frame(width: width * fraction, height: h)
            Circle().fill(.white).frame(width: thumb, height: thumb).offset(x: width * fraction - thumb / 2)
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: dragging)
        .frame(height: Self.height)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { v in
                guard duration > 0 else { return }
                scrubbing = true
                let f = SeekBarMath.fraction(x: v.location.x, width: width)
                dragFraction = f
                onScrub(f * duration)
            }
            .onEnded { v in
                guard duration > 0 else { scrubbing = false; return }
                let f = SeekBarMath.fraction(x: v.location.x, width: width)
                onSeek(f * duration)
                settling = f
                dragFraction = nil
                scrubbing = false
            })
        .onChange(of: position) { if let f = settling, abs(position - f * duration) < 2 { settling = nil } }
        .task(id: settling) {   // or give up waiting for the player
            guard settling != nil else { return }
            try? await Task.sleep(for: .seconds(2))
            settling = nil
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("player")) } action: { frame = $0 }
        .overlay(alignment: .bottomLeading) { bubble }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("player.seekBar"))
        .accessibilityValue(String(format: L("player.seekValue"), SeekBarMath.format(position), SeekBarMath.format(duration)))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onSkip(1)
            case .decrement: onSkip(-1)
            @unknown default: break
            }
        }
        .environment(\.layoutDirection, .leftToRight)
    }

    @ViewBuilder private var bubble: some View {
        let look = preview.look
        let w = SeekBubble.width(for: look)
        let x = width * (dragFraction ?? 0)
        let center = frame.minX + x
        let left = containerWidth > 0 ? SeekBarMath.bubbleLeft(center: center, width: w, container: containerWidth, margin: Self.margin) : center - w / 2
        SeekBubble(time: SeekBarMath.format((dragFraction ?? 0) * duration), look: look,
                   pointerX: SeekBarMath.pointerX(center: center, left: left, width: w, inset: SeekBubble.cornerInset))
            .opacity(dragFraction != nil ? 1 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: dragFraction != nil)
            .offset(x: left - frame.minX, y: -(Self.height + 4))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The floating card above the bar: thumbnail (or a neutral placeholder) and the time, with a pointer toward the thumb.
/// With `pointerX` nil it is a plain card (the drag-to-scrub overlay in the middle of the picture, which also shows the change).
struct SeekBubble: View {
    let time: String
    var delta: String?
    let look: SeekPreview.Look
    var pointerX: CGFloat?

    static let thumb = CGSize(width: 176, height: 99)
    static let pad: CGFloat = 6
    static let radius: CGFloat = 12
    static let pointer = CGSize(width: 12, height: 5)
    static let cornerInset = radius + pointer.width / 2
    /// Fixed sizes, so the bubble neither jumps when the frame arrives nor needs measuring to stay inside the player.
    static func width(for look: SeekPreview.Look) -> CGFloat { look == .none ? 76 : thumb.width + 2 * pad }

    var body: some View {
        let tip = pointerX != nil ? Self.pointer.height : 0
        VStack(spacing: 5) {
            switch look {
            case .none: EmptyView()
            case .loading: RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.white.opacity(0.08)).frame(width: Self.thumb.width, height: Self.thumb.height)
            case .image(let cg):
                Image(decorative: cg, scale: 1).resizable().interpolation(.medium).aspectRatio(contentMode: .fit)
                    .frame(width: Self.thumb.width, height: Self.thumb.height).background(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            HStack(spacing: 6) {
                Text(time).font(.footnote.weight(.semibold).monospacedDigit())
                if let delta { Text(delta).font(.footnote.monospacedDigit()).foregroundStyle(.white.opacity(0.65)) }
            }
            .foregroundStyle(.white)
            .environment(\.layoutDirection, .leftToRight)
        }
        .padding(look == .none ? EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8) : EdgeInsets(top: Self.pad, leading: Self.pad, bottom: Self.pad + 1, trailing: Self.pad))
        .padding(.bottom, tip)
        .frame(minWidth: Self.width(for: look))
        .background { BubbleShape(radius: Self.radius, pointerX: pointerX, pointer: Self.pointer).fill(.black.opacity(0.82)) }
        .overlay { BubbleShape(radius: Self.radius, pointerX: pointerX, pointer: Self.pointer).stroke(.white.opacity(0.14), lineWidth: 1) }
        .shadow(color: .black.opacity(0.35), radius: 8, y: 2)
    }
}

/// A rounded rectangle, with a small triangle under its bottom edge when `pointerX` is set, drawn as one outline so the stroke has no seam.
private struct BubbleShape: Shape {
    let radius: CGFloat
    let pointerX: CGFloat?
    let pointer: CGSize

    func path(in r: CGRect) -> Path {
        let tip = pointerX != nil ? pointer.height : 0
        let b = CGRect(x: r.minX, y: r.minY, width: r.width, height: max(r.height - tip, 0))
        var p = Path()
        p.move(to: CGPoint(x: b.minX + radius, y: b.minY))
        p.addArc(tangent1End: CGPoint(x: b.maxX, y: b.minY), tangent2End: CGPoint(x: b.maxX, y: b.maxY), radius: radius)
        p.addArc(tangent1End: CGPoint(x: b.maxX, y: b.maxY), tangent2End: CGPoint(x: b.minX, y: b.maxY), radius: radius)
        if let pointerX {
            let px = max(b.minX + radius + pointer.width / 2, min(r.minX + pointerX, b.maxX - radius - pointer.width / 2))
            p.addLine(to: CGPoint(x: px + pointer.width / 2, y: b.maxY))
            p.addLine(to: CGPoint(x: px, y: b.maxY + pointer.height))
            p.addLine(to: CGPoint(x: px - pointer.width / 2, y: b.maxY))
        }
        p.addArc(tangent1End: CGPoint(x: b.minX, y: b.maxY), tangent2End: CGPoint(x: b.minX, y: b.minY), radius: radius)
        p.addArc(tangent1End: CGPoint(x: b.minX, y: b.minY), tangent2End: CGPoint(x: b.maxX, y: b.minY), radius: radius)
        p.closeSubpath()
        return p
    }
}
