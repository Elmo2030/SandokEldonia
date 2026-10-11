#if DEBUG
import UIKit
import IPTVCore
import IPTVAppKit
import IPTVPlayer

/// Debug builds only: opens the player straight on a generated test stream, so screenshots and UI tests can reach every state without
/// typing (`xcrun simctl launch <device> <bundle id> -uiState player-live ...`). Needs the fake panel and the media of ios/UITests/Fixtures
/// (`make-media.sh`, `fake_panel.py`) on 127.0.0.1:8765 (`-panel http://host:port` to change it). Never compiled into a release build.
///
///   -uiState  player-live | player-vod | player-series | player-local | player-error
///   -playerControls hidden        start with the controls faded out
///   -playerOrientation portrait|landscape      force the interface orientation (default: iPhone starts landscape)
///   -playerSeek <seconds>         seek there after the start
///   -playerSpeed <x>              start at this speed
///   -playerFile <path>            the movie for player-local (default /tmp/iptvplayer-media/vod.mkv)
///   -statusFile <path>            write a JSON status (position, frames drawn, app state...) every 0.5 s
@MainActor enum PlayerDebug {
    private static var frames = 0
    private static var centre: (UInt8, UInt8, UInt8) = (0, 0, 0)
    private static var statusTask: Task<Void, Never>?

    static func runIfRequested(_ model: PhoneModel) async {
        let d = UserDefaults.standard
        guard let state = d.string(forKey: "uiState"), state.hasPrefix("player") else { return }
        if let o = d.string(forKey: "playerOrientation") { _ = o }          // read by PlayerOrientation.enter()
        if state == "player-local" || state == "player-error" {
            let file = d.string(forKey: "playerFile") ?? "/tmp/iptvplayer-media/vod.mkv"
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
        if d.object(forKey: "playerSpeed") != nil { p.setSpeed(d.double(forKey: "playerSpeed")) }
        if d.object(forKey: "playerSeek") != nil { p.seek(to: d.double(forKey: "playerSeek")) }
        if let path = d.string(forKey: "statusFile") { startStatus(model, path) }
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

    private static func startStatus(_ model: PhoneModel, _ path: String) {
        statusTask?.cancel()
        statusTask = Task {
            while !Task.isCancelled {
                let app = UIApplication.shared.applicationState
                var s: [String: Any] = ["appState": app == .active ? "active" : app == .inactive ? "inactive" : "background",
                                        "frames": frames, "centre": [Int(centre.0), Int(centre.1), Int(centre.2)], "time": Date().timeIntervalSince1970]
                if let p = model.player {
                    let m = p.core.mpv
                    s["position"] = p.position; s["duration"] = p.duration; s["paused"] = p.paused; s["speed"] = p.speed
                    s["vid"] = m.string("vid") ?? "?"; s["aid"] = m.string("aid") ?? "?"; s["sid"] = m.string("sid") ?? "?"
                    s["tracks"] = p.tracks.count; s["controlsVisible"] = p.controlsVisible; s["error"] = p.error ?? ""
                    s["scale"] = p.videoScale.rawValue; s["title"] = p.request.title; s["hwdec"] = m.string("hwdec-current") ?? "?"
                    s["audioOut"] = m.string("current-ao") ?? "?"; s["aoDevices"] = m.string("audio-device-list") ?? "?"; s["audioCodec"] = m.string("audio-codec-name") ?? "?"; s["aoOpt"] = m.string("ao") ?? "?"; s["audioParams"] = m.string("audio-params/samplerate") ?? "?"; s["volume"] = m.string("volume") ?? "?"
                    s["buffering"] = p.buffering; s["atEnd"] = p.atEnd; s["live"] = p.isLive
                    s["videoParams"] = "\(m.string("video-params/w") ?? "?")x\(m.string("video-params/h") ?? "?")"
                } else { s["player"] = "none" }
                if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
                    s["orientation"] = scene.effectiveGeometry.interfaceOrientation.isLandscape ? "landscape" : "portrait"
                    s["bounds"] = "\(Int(scene.coordinateSpace.bounds.width))x\(Int(scene.coordinateSpace.bounds.height))"
                }
                if let data = try? JSONSerialization.data(withJSONObject: s, options: [.sortedKeys]) { try? data.write(to: URL(fileURLWithPath: path)) }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }
}
#endif
