import AVFAudio
import MediaPlayer
import UIKit
import IPTVPlayer

/// The player's seat in the system: the audio session (plays with the silent switch on and with the screen locked), its interruptions
/// and route changes, the lock-screen / Control Center / headset commands, "now playing", and the idle timer. The decisions are in
/// IPTVPlayer (InterruptionPolicy, RoutePolicy, NowPlayingInfo, NowPlayingThrottle: tested); this maps UIKit/AVFoundation events onto them.
@MainActor
final class PlayerSystem {
    struct Commands {
        var play: () -> Void = {}
        var pause: () -> Void = {}
        var toggle: () -> Void = {}
        var skip: (Double) -> Void = { _ in }
        var seek: (Double) -> Void = { _ in }
        var next: (() -> Void)?
        var previous: (() -> Void)?
        /// True while the player is playing (read when an interruption begins).
        var isPlaying: () -> Bool = { false }
    }

    private var commands = Commands()
    private var interruptions = InterruptionPolicy()
    private var throttle = NowPlayingThrottle()
    private var observers: [NSObjectProtocol] = []
    private var targets: [(MPRemoteCommand, Any)] = []
    private var artworkTask: Task<Void, Never>?
    private var artwork: MPMediaItemArtwork?
    private var artworkFor: URL?
    private(set) var active = false

    func activate(_ commands: Commands, seekStep: Int) {
        self.commands = commands
        guard !active else { return }
        active = true
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback)   // silent switch does not mute; UIBackgroundModes audio keeps it going locked
        try? session.setActive(true)
        let nc = NotificationCenter.default
        observers = [
            nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] n in
                let type = (n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
                let options = (n.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt).map(AVAudioSession.InterruptionOptions.init) ?? []
                MainActor.assumeIsolated { self?.interruption(type, options) }
            },
            nc.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] n in
                let reason = (n.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt).flatMap(AVAudioSession.RouteChangeReason.init)
                let previous = n.userInfo?[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription
                MainActor.assumeIsolated { self?.routeChange(reason, previous) }
            },
        ]
        configureRemoteCommands(seekStep: seekStep)
    }

    func deactivate() {
        guard active else { return }
        active = false
        observers.forEach(NotificationCenter.default.removeObserver); observers = []
        targets.forEach { $0.0.removeTarget($0.1) }; targets = []
        let center = MPRemoteCommandCenter.shared()
        for c in [center.playCommand, center.pauseCommand, center.togglePlayPauseCommand, center.skipForwardCommand, center.skipBackwardCommand,
                  center.changePlaybackPositionCommand, center.nextTrackCommand, center.previousTrackCommand] { c.isEnabled = false }
        artworkTask?.cancel(); artwork = nil; artworkFor = nil
        throttle.reset()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        UIApplication.shared.isIdleTimerDisabled = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// The user's own play/pause cancels an automatic resume after an interruption.
    func userChose() { interruptions.userChose() }

    // MARK: Interruptions and routes

    private func interruption(_ type: AVAudioSession.InterruptionType?, _ options: AVAudioSession.InterruptionOptions) {
        guard let type else { return }
        let event: InterruptionEvent = type == .began ? .began : .ended(shouldResume: options.contains(.shouldResume))
        switch interruptions.handle(event, isPlaying: commands.isPlaying()) {
        case .pause: commands.pause()
        case .resume:
            try? AVAudioSession.sharedInstance().setActive(true)
            commands.play()
        case .none: break
        }
    }

    private func routeChange(_ reason: AVAudioSession.RouteChangeReason?, _ previous: AVAudioSessionRouteDescription?) {
        let builtIn: Set<AVAudioSession.Port> = [.builtInSpeaker, .builtInReceiver]
        let wasBuiltIn = previous?.outputs.allSatisfy { builtIn.contains($0.portType) } ?? true
        if RoutePolicy.shouldPause(oldDeviceUnavailable: reason == .oldDeviceUnavailable, previousOutputWasBuiltIn: wasBuiltIn) { commands.pause() }
    }

    // MARK: Lock screen

    /// What the lock screen can do depends on what is playing: a live channel has no timeline, next/previous exist when there is something to go to.
    func configureRemoteCommands(seekStep: Int, live: Bool = false, canGoNext: Bool = false, canGoPrevious: Bool = false) {
        let c = MPRemoteCommandCenter.shared()
        if targets.isEmpty {
            func add(_ command: MPRemoteCommand, _ handler: @escaping (MPRemoteCommandEvent) -> Void) {
                let t = command.addTarget { event in DispatchQueue.main.async { handler(event) }; return .success }
                targets.append((command, t))
            }
            add(c.playCommand) { [weak self] _ in self?.userChose(); self?.commands.play() }
            add(c.pauseCommand) { [weak self] _ in self?.userChose(); self?.commands.pause() }
            add(c.togglePlayPauseCommand) { [weak self] _ in self?.userChose(); self?.commands.toggle() }
            add(c.skipForwardCommand) { [weak self] e in self?.commands.skip((e as? MPSkipIntervalCommandEvent)?.interval ?? 10) }
            add(c.skipBackwardCommand) { [weak self] e in self?.commands.skip(-((e as? MPSkipIntervalCommandEvent)?.interval ?? 10)) }
            add(c.changePlaybackPositionCommand) { [weak self] e in
                if let e = e as? MPChangePlaybackPositionCommandEvent { self?.commands.seek(e.positionTime) }
            }
            add(c.nextTrackCommand) { [weak self] _ in self?.commands.next?() }
            add(c.previousTrackCommand) { [weak self] _ in self?.commands.previous?() }
        }
        c.playCommand.isEnabled = true; c.pauseCommand.isEnabled = true; c.togglePlayPauseCommand.isEnabled = true
        c.skipForwardCommand.preferredIntervals = [NSNumber(value: seekStep)]
        c.skipBackwardCommand.preferredIntervals = [NSNumber(value: seekStep)]
        c.skipForwardCommand.isEnabled = !live; c.skipBackwardCommand.isEnabled = !live
        c.changePlaybackPositionCommand.isEnabled = !live
        c.nextTrackCommand.isEnabled = canGoNext; c.previousTrackCommand.isEnabled = canGoPrevious
        c.seekForwardCommand.isEnabled = false; c.seekBackwardCommand.isEnabled = false      // press-and-hold scanning: not offered
        c.changePlaybackRateCommand.isEnabled = false
    }

    func updateNowPlaying(_ s: NowPlayingState, now: Date = Date(), force: Bool = false) {
        guard active else { return }
        if force { throttle.reset() }
        guard throttle.shouldPublish(s, now: now) else { return }
        var d = NowPlayingInfo.dictionary(s)
        if let artwork { d[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = d
        MPNowPlayingInfoCenter.default().playbackState = s.paused ? .paused : .playing
    }

    /// The channel logo / poster for the lock screen, fetched once per item (nil = none).
    func setArtwork(url: URL?, state: @escaping () -> NowPlayingState) {
        guard url != artworkFor else { return }
        artworkFor = url; artwork = nil
        artworkTask?.cancel()
        guard let url else { return }
        artworkTask = Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url), !Task.isCancelled, let image = UIImage(data: data) else { return }
            let art = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            await MainActor.run {
                guard let self, self.artworkFor == url else { return }
                self.artwork = art
                self.updateNowPlaying(state(), force: true)
            }
        }
    }

    /// The screen stays on while a video plays and may go to sleep while it is paused.
    func setScreenAwake(_ on: Bool) { UIApplication.shared.isIdleTimerDisabled = on }
}

/// Brightness and volume for the vertical drags. The volume is the system's output volume: iOS only lets an app change it through the
/// slider of an MPVolumeView (kept in the hierarchy, invisible). Where there is none (the Simulator) the gesture falls back to mpv's own gain.
@MainActor
final class SystemLevels {
    let volumeView = MPVolumeView(frame: CGRect(x: -2000, y: -2000, width: 10, height: 10))
    private var originalBrightness: CGFloat?
    private var slider: UISlider? { volumeView.subviews.compactMap { $0 as? UISlider }.first }

    var brightness: Double { Double(UIScreen.main.brightness) }

    func setBrightness(_ v: Double) {
        if originalBrightness == nil { originalBrightness = UIScreen.main.brightness }
        UIScreen.main.brightness = CGFloat(min(max(v, 0), 1))
    }

    /// Back to what the user had before the gesture changed it (not touched if the user never used the gesture).
    func restoreBrightness() { if let b = originalBrightness { UIScreen.main.brightness = b; originalBrightness = nil } }

    /// The output volume, 0...1.
    var volume: Double { Double(AVAudioSession.sharedInstance().outputVolume) }
    var canSetVolume: Bool { slider != nil }

    func setVolume(_ v: Double) { slider?.setValue(Float(min(max(v, 0), 1)), animated: false) }
}
