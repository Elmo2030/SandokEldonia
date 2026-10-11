import AVFAudio
import UIKit
import Observation
import IPTVAppKit
import IPTVPlayer

/// One playing stream: libmpv + its OpenGL ES view, and the few values the controls show. Wave 2 replaces the controls, not this.
@MainActor @Observable
final class PhonePlayer {
    let request: PlayRequest
    let view: MPVVideoView            // one view for the player's lifetime
    var paused = false
    var position = 0.0
    var duration = 0.0
    var error: String?
    var onSaveProgress: ((_ position: Double, _ duration: Double) -> Void)?
    @ObservationIgnored private let mpv: MPVPlayer
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var ticks = 0
    @ObservationIgnored private var closed = false

    init(request: PlayRequest) {
        self.request = request
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback)   // plays with the silent switch on, and with the screen locked (UIBackgroundModes audio)
        try? session.setActive(true)
        let mpv = MPVPlayer(subLang: nil, audioLang: nil)
        self.mpv = mpv
        view = MPVVideoView(player: mpv)
        mpv.onEndFile = { [weak self] isError in
            guard isError else { return }
            Task { @MainActor in
                guard let self else { return }
                self.error = [L("player.error"), self.mpv.lastError].compactMap { $0 }.joined(separator: ": ")
            }
        }
        mpv.load(request.url, start: request.start)
        UIApplication.shared.isIdleTimerDisabled = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
    }

    private func tick() {
        guard !closed else { return }
        position = mpv.double("time-pos") ?? position
        duration = mpv.double("duration") ?? 0
        paused = mpv.flag("pause")
        ticks += 1
        if ticks % 20 == 0 { save() }
    }

    func togglePause() { mpv.togglePause() }
    func seek(by seconds: Double) { mpv.seek(by: seconds) }

    /// A position of 0 means nothing played yet: saving it would erase the resume point.
    private func save() { if !request.isLive, position > 0 { onSaveProgress?(position, duration) } }

    func close() {
        guard !closed else { return }
        closed = true
        save()
        timer?.invalidate(); timer = nil
        UIApplication.shared.isIdleTimerDisabled = false
        mpv.shutdown()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
