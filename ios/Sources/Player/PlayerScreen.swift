import SwiftUI
import IPTVPlayer

/// Full-screen video (libmpv through the OpenGL ES view) with the bare minimum of controls: tap the picture to show/hide them.
struct PlayerScreen: View {
    @Environment(PhoneModel.self) private var model
    let player: PhonePlayer
    @State private var controls = true

    var body: some View {
        ZStack {
            Color.black
            VideoSurface(view: player.view).ignoresSafeArea()
            Color.clear.contentShape(Rectangle()).onTapGesture { withAnimation(.easeOut(duration: 0.15)) { controls.toggle() } }
            if controls || player.error != nil { overlay }
        }
        .ignoresSafeArea()
        .statusBarHidden(!controls)
        .accessibilityAddTraits(.isModal)
    }

    private var overlay: some View {
        VStack {
            HStack(spacing: 12) {
                Button { model.stopPlayback() } label: { Image(systemName: "xmark").font(.title3.weight(.semibold)).frame(width: 44, height: 44) }
                    .accessibilityLabel(L("player.close"))
                Text(player.request.title).font(.headline).lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 8).padding(.top, 8)
            Spacer()
            if let e = player.error {
                Text(e).multilineTextAlignment(.center).padding().background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 10)).padding()
            }
            Button { player.togglePause() } label: {
                Image(systemName: player.paused ? "play.fill" : "pause.fill").font(.system(size: 34)).frame(width: 72, height: 72)
            }
            .accessibilityLabel(player.paused ? L("downloads.play") : L("downloads.pause"))
            Spacer()
        }
        .foregroundStyle(.white)
        .background(LinearGradient(colors: [.black.opacity(0.55), .clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom).allowsHitTesting(false))
    }
}

private struct VideoSurface: UIViewRepresentable {
    let view: MPVVideoView
    func makeUIView(context: Context) -> MPVVideoView { view }
    func updateUIView(_ uiView: MPVVideoView, context: Context) {}
}
