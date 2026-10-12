#if DEBUG
import UIKit
import AVFAudio
import MediaPlayer
import IPTVCore
import IPTVAppKit
import IPTVPlayer

/// Debug builds only: opens the player straight on a generated test stream, so screenshots and UI tests can reach every state without
/// typing (`xcrun simctl launch <device> <bundle id> -uiState player-live ...`). Needs the fake panel and the media of ios/UITests/Fixtures
/// (`make-media.sh`, `fake_panel.py`) on 127.0.0.1:8765 (`-panel http://host:port` to change it). Never compiled into a release build.
///
///   -uiState  player-url (-playerURL <url> [-playerLive YES] [-playerTitle <text>]) | player-live | player-vod | player-series | player-local | player-error
///   -playerControls hidden        start with the controls faded out
///   -playerOrientation portrait|landscape      force the interface orientation (default: iPhone starts landscape)
///   -playerSeek <seconds>         seek there after the start
///   -playerSpeed <x>              start at this speed
///   -playerHUD scrub|skip|brightness|volume|boost|toast   hold that feedback overlay on screen
///   -playerPaused YES             pause after the start
///   -playerSheet speed|subtitles  open that sheet 2.5 s after the player appears
///   -playerFile <path>            the movie for player-local (default /tmp/iptvplayer-media/vod.mkv)
///   -statusFile <path>            write a JSON status (position, frames drawn, app state, lock screen info...) every 0.5 s
///   -playerWindowShot YES         save the app window (without the GL video) as Documents/window.png after 6 s
///   -playerSnapshot YES           save the next GL frame as Documents/snapshot.png (what the video view really draws)
///   -hwdec <mode>                 set mpv hwdec after the start (videotoolbox | videotoolbox-copy | no)
///   -playerPiP YES                start Picture in Picture 1.5 s after the player appears (commandFile: pip-start | pip-stop)
///   -commandFile <path>           each line appended to this file is run once: interrupt-began | interrupt-ended | route-unplugged
///                                 (posts the real AVAudioSession notifications, so the app's own handlers answer them)
@MainActor enum PlayerDebug {
    private static var frames = 0
    private static var centre: (UInt8, UInt8, UInt8) = (0, 0, 0)
    private static var statusTask: Task<Void, Never>?
    private static var counters: [String: Int] = [:]

    /// Gesture counters for the status file (what the recognizers saw).
    static func count(_ name: String) { counters[name, default: 0] += 1 }

    /// A relative path (a device run: no /tmp) lives in the app's Documents folder.
    private static func resolved(_ path: String) -> String {
        path.hasPrefix("/") ? path : (FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(path).path)
    }

    static func runIfRequested(_ model: PhoneModel) async {
        let d = UserDefaults.standard
        guard let state = d.string(forKey: "uiState"), state.hasPrefix("player") else { return }
        if let o = d.string(forKey: "playerOrientation") { _ = o }          // read by PlayerOrientation.enter()
        if state == "player-url", let u = d.string(forKey: "playerURL").flatMap(URL.init(string:)) {          // a stream from the network
            model.startPlayback(PlayRequest(title: d.string(forKey: "playerTitle") ?? "Network test", url: u, isLive: d.bool(forKey: "playerLive"), item: nil))
        } else if state == "player-local" || state == "player-error" {
            let file = resolved(d.string(forKey: "playerFile") ?? "/tmp/iptvplayer-media/vod.mkv")
            let url = state == "player-error" ? URL(string: "http://127.0.0.1:9/none.mkv")! : URL(fileURLWithPath: file)
            model.startPlayback(PlayRequest(title: "Local test movie", url: url, isLive: false, item: nil))
        } else {
            let base = d.string(forKey: "panel") ?? "http://127.0.0.1:8765"
            if model.accounts.isEmpty { await model.addAccount(Account(name: "Test panel", kind: .xtream, server: base, username: "u"), password: "p") }
            switch state {
            case "player-live": await play(model, .live)
            case "player-vod": await play(model, .movie)
            default:
                model.tab = .series
                guard await waitForResults(model), let series = model.results.first, let a = model.playlist(id: series.accountId),
                      let eps = try? await SyncService(db: model.db).episodes(account: a, password: model.secrets.password(for: a.id ?? 0), seriesId: series.streamId),
                      let first = eps.min(by: { ($0.season, $0.number) < ($1.season, $1.number) }) else { return }
                model.playEpisode(first, of: series)
            }
        }
        guard let p = model.player else { return }
        p.view.onFrame = { r, g, b in MainActor.assumeIsolated { frames += 1; centre = (r, g, b) } }
        try? await Task.sleep(for: .seconds(1.5))
        if d.string(forKey: "playerControls") == "hidden" { p.controls.hide() }
        if d.bool(forKey: "playerPaused") { p.setPlaying(false) }
        switch d.string(forKey: "playerHUD") {            // a feedback overlay held on screen, for screenshots
        case "scrub": p.dragScrub = (95, 33); p.previewAt(95)
        case "skip": p.skipHUD = (.right, "+20", 1)
        case "brightness": p.levelHUD = (.brightness, 0.6, 1)
        case "volume": p.levelHUD = (.volume, 0.35, 1)
        case "boost": p.boosting = true
        case "toast": p.toast = ("arrow.up.left.and.arrow.down.right", p.scaleName(.fill), 1)
        default: break
        }
        if d.bool(forKey: "playerWindowShot") {          // the app's own window (UIKit + SwiftUI, not the GL video): what the app itself draws
            try? await Task.sleep(for: .seconds(6))
            if let w = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first?.keyWindow {
                let img = UIGraphicsImageRenderer(bounds: w.bounds).image { _ in w.drawHierarchy(in: w.bounds, afterScreenUpdates: true) }
                try? img.pngData()?.write(to: URL(fileURLWithPath: resolved("window.png")))
            }
        }
        if d.bool(forKey: "playerSnapshot") { try? await Task.sleep(for: .seconds(3)); p.view.snapshotPath = resolved("snapshot.png") }   // the GL framebuffer, to Documents
        if let h = d.string(forKey: "hwdec") { p.core.mpv.setProperty("hwdec", h) }       // experiment: which decoder path draws on this device
        if d.bool(forKey: "playerPiP") { p.startPiP() }
        if d.object(forKey: "playerSpeed") != nil { p.setSpeed(d.double(forKey: "playerSpeed")) }
        if d.object(forKey: "playerSeek") != nil { p.seek(to: d.double(forKey: "playerSeek")) }
        if let path = d.string(forKey: "statusFile") { startStatus(model, resolved(path)) }
    }

    private static func play(_ model: PhoneModel, _ type: ItemType) async {
        model.tab = type
        guard await waitForResults(model), let item = model.results.first else { return }
        model.play(item)
    }

    private static func waitForResults(_ model: PhoneModel) async -> Bool {
        for _ in 0..<100 where model.results.isEmpty { try? await Task.sleep(for: .milliseconds(100)) }
        return !model.results.isEmpty
    }

    private static var commandsDone = 0

    /// `-commandFile`: lines appended to it are acted on once, so a script can interrupt the audio session while the app runs.
    private static func runCommands() {
        guard let path = UserDefaults.standard.string(forKey: "commandFile"), let text = try? String(contentsOfFile: path, encoding: .utf8) else { return }
        let lines = text.split(separator: "\n").map(String.init)
        for line in lines.dropFirst(commandsDone) {
            switch line {
            case "interrupt-began":
                NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(),
                                                userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
            case "interrupt-ended":
                NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(),
                                                userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue,
                                                           AVAudioSessionInterruptionOptionKey: AVAudioSession.InterruptionOptions.shouldResume.rawValue])
            case "interrupt-ended-noresume":
                NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(),
                                                userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue])
            case "route-unplugged":
                NotificationCenter.default.post(name: AVAudioSession.routeChangeNotification, object: AVAudioSession.sharedInstance(),
                                                userInfo: [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue])
            case "play": model?.player?.setPlaying(true)
            case "pip-start": model?.player?.startPiP()
            case "pip-stop": model?.player?.view.stopPiP()
            default: break
            }
        }
        commandsDone = lines.count
    }

    private static weak var model: PhoneModel?

    private static func startStatus(_ model: PhoneModel, _ path: String) {
        Self.model = model
        statusTask?.cancel()
        statusTask = Task {
            while !Task.isCancelled {
                let app = UIApplication.shared.applicationState
                var s: [String: Any] = ["appState": app == .active ? "active" : app == .inactive ? "inactive" : "background",
                                        "frames": frames, "gestures": counters, "centre": [Int(centre.0), Int(centre.1), Int(centre.2)], "time": Date().timeIntervalSince1970]
                if let p = model.player {
                    let m = p.core.mpv
                    s["position"] = p.position; s["duration"] = p.duration; s["paused"] = p.paused; s["speed"] = p.speed
                    s["vid"] = m.string("vid") ?? "?"; s["aid"] = m.string("aid") ?? "?"; s["sid"] = m.string("sid") ?? "?"
                    s["tracks"] = p.tracks.count; s["controlsVisible"] = p.controlsVisible; s["error"] = p.error ?? ""
                    s["scale"] = p.videoScale.rawValue; s["title"] = p.request.title; s["hwdec"] = m.string("hwdec-current") ?? "?"
                    s["audioOut"] = m.string("current-ao") ?? "?"; s["aoDevices"] = m.string("audio-device-list") ?? "?"; s["audioCodec"] = m.string("audio-codec-name") ?? "?"; s["aoOpt"] = m.string("ao") ?? "?"; s["audioParams"] = m.string("audio-params/samplerate") ?? "?"; s["volume"] = m.string("volume") ?? "?"
                    s["pip"] = ["supported": MPVVideoView.pipSupported, "mode": p.view.pipMode, "active": p.view.pipActive, "frames": p.view.pipFrames, "auto": p.view.pipAutoFlag.map { $0 ? "yes" : "no" } ?? "n/a"] as [String: Any]
                    s["brightness"] = p.levels.brightness; s["buffering"] = p.buffering; s["atEnd"] = p.atEnd; s["live"] = p.isLive
                    s["videoParams"] = "\(m.string("video-params/w") ?? "?")x\(m.string("video-params/h") ?? "?")"
                } else { s["player"] = "none" }
                if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
                    s["orientation"] = scene.effectiveGeometry.interfaceOrientation.isLandscape ? "landscape" : "portrait"
                    s["bounds"] = "\(Int(scene.coordinateSpace.bounds.width))x\(Int(scene.coordinateSpace.bounds.height))"
                }
                let np = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                s["nowPlaying"] = ["title": np[MPMediaItemPropertyTitle] as? String ?? "", "rate": np[MPNowPlayingInfoPropertyPlaybackRate] as? Double ?? -1,
                                   "elapsed": np[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double ?? -1, "duration": np[MPMediaItemPropertyPlaybackDuration] as? Double ?? -1,
                                   "live": np[MPNowPlayingInfoPropertyIsLiveStream] as? Bool ?? false, "artist": np[MPMediaItemPropertyArtist] as? String ?? ""] as [String: Any]
                let rc = MPRemoteCommandCenter.shared()
                s["remote"] = ["play": rc.playCommand.isEnabled, "pause": rc.pauseCommand.isEnabled, "skip": rc.skipForwardCommand.isEnabled, "seek": rc.changePlaybackPositionCommand.isEnabled,
                               "next": rc.nextTrackCommand.isEnabled, "previous": rc.previousTrackCommand.isEnabled]
                runCommands()
                if let data = try? JSONSerialization.data(withJSONObject: s, options: [.sortedKeys]) { try? data.write(to: URL(fileURLWithPath: path)) }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }
}
#endif
