import XCTest
import UIKit

/// UI tests of the touch player on a (headless) simulator: real taps, double taps, drags, pinch, long press, menus and rotation on the
/// generated test streams, with a screenshot of each state in /tmp/iptvplayer-ui. What happened inside the app is read from the JSON status
/// file the DEBUG build writes (`-statusFile`): position, speed, scale, controls, the frame counter of the video view.
///
/// Prerequisites (nothing is installed system-wide):
///   ios/UITests/Fixtures/make-media.sh /tmp/iptvplayer-media
///   python3 ios/UITests/Fixtures/fake_panel.py /tmp/iptvplayer-media 8765 &
///   cd ios && xcodebuild test -project IPTVPhone.xcodeproj -scheme IPTVPhone CODE_SIGNING_ALLOWED=NO \
///     -destination 'platform=iOS Simulator,name=<an iPhone or iPad simulator>'
/// Then `xcrun simctl shutdown all`.
final class PlayerUITests: XCTestCase {
    static let status = "/tmp/iptvplayer-ui-status.json"
    static let shots = "/tmp/iptvplayer-ui"
    var app: XCUIApplication!
    var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    override func setUp() {
        continueAfterFailure = true
        try? FileManager.default.createDirectory(atPath: Self.shots, withIntermediateDirectories: true)
    }

    // MARK: helpers

    func launch(_ state: String, _ extra: [String] = []) {
        try? FileManager.default.removeItem(atPath: Self.status)
        app = XCUIApplication()
        app.launchArguments = ["-uiState", state, "-statusFile", Self.status, "-barsHideSeconds", "3", "-videoScale", "fit", "-subScale", "1", "-subDelay", "0"] + extra
        app.launch()
        XCTAssertTrue(waitFor(timeout: 40) { ($0["frames"] as? Int ?? 0) > 10 || $0["error"] as? String != "" }, "the player did not start")
    }

    func status() -> [String: Any] {
        (try? Data(contentsOf: URL(fileURLWithPath: Self.status))).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
    }

    @discardableResult
    func waitFor(timeout: TimeInterval = 10, _ cond: ([String: Any]) -> Bool) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end { if cond(status()) { return true }; Thread.sleep(forTimeInterval: 0.25) }
        return cond(status())
    }

    func num(_ k: String) -> Double { (status()[k] as? NSNumber)?.doubleValue ?? .nan }
    func str(_ k: String) -> String { status()[k] as? String ?? "" }
    func flag(_ k: String) -> Bool { (status()[k] as? NSNumber)?.boolValue ?? false }

    /// XCUIScreen gives the screen in the device's own (portrait) orientation: a landscape app comes out turned by 90 degrees. Turn it back.
    func shot(_ name: String) {
        let s = XCUIScreen.main.screenshot()
        var image = s.image
        if str("orientation") == "landscape", image.size.height > image.size.width, let cg = image.cgImage {
            let turned = UIImage(cgImage: cg, scale: image.scale, orientation: .left)
            image = UIGraphicsImageRenderer(size: CGSize(width: image.size.height, height: image.size.width)).image { _ in
                turned.draw(in: CGRect(origin: .zero, size: CGSize(width: image.size.height, height: image.size.width)))
            }
        }
        try? image.pngData()?.write(to: URL(fileURLWithPath: "\(Self.shots)/\(name).png"))
        let a = XCTAttachment(image: image); a.name = name; a.lifetime = .keepAlways; add(a)
    }

    final class Flag: @unchecked Sendable { var value = false }

    /// A button by its label that is on screen (the title bar's Close hides behind a sheet; the sheet has its own).
    func tapHittable(_ label: String) {
        let b = app.buttons.matching(identifier: label).allElementsBoundByIndex.first { $0.isHittable }
        XCTAssertNotNil(b, "no tappable \(label) button")
        b?.tap()
    }

    func at(_ x: Double, _ y: Double) -> XCUICoordinate { app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)) }

    func rotate(_ o: UIDeviceOrientation) {
        XCUIDevice.shared.orientation = o
        Thread.sleep(forTimeInterval: 1.5)
    }

    // MARK: the movie, in landscape

    /// What the recognizers saw, from the status file: a quick probe that a tap, a double tap and a drag reach them.
    func testRecognizersSeeTheGestures() throws {
        try XCTSkipIf(isPad)
        launch("player-vod", ["-playerSeek", "40"])
        XCTAssertTrue(waitFor(timeout: 8) { $0["controlsVisible"] as? Bool == false })
        at(0.5, 0.3).tap()
        Thread.sleep(forTimeInterval: 1.5)
        print("PROBE after tap:", status()["gestures"] ?? "-", status()["controlsVisible"] ?? "-")
        at(0.85, 0.45).doubleTap()
        Thread.sleep(forTimeInterval: 1)
        print("PROBE after double tap:", status()["gestures"] ?? "-", status()["position"] ?? "-")
        at(0.3, 0.45).press(forDuration: 0.05, thenDragTo: at(0.7, 0.45))
        Thread.sleep(forTimeInterval: 1)
        print("PROBE after drag:", status()["gestures"] ?? "-", status()["position"] ?? "-")
        shot("probe")
    }

    /// Every XCUITest action waits for the app to go idle (a video never does), so one action takes seconds: the checks below must not race
    /// the clock. Tests that look at positions run paused; the auto-hide delay is long or off where a tap is checked.
    func testPlaysInLandscapeAndControlsAutoHide() throws {
        try XCTSkipIf(isPad)
        launch("player-vod", ["-barsHideSeconds", "5", "-playerSeek", "40"])
        XCTAssertTrue(waitFor { $0["orientation"] as? String == "landscape" }, "an iPhone starts a video in landscape")
        XCTAssertTrue(waitFor { ($0["position"] as? Double ?? 0) > 40 })
        XCTAssertTrue(flag("controlsVisible"))
        shot("g01-playing-controls-shown")

        // the picture moves: the frame counter and the clock advance between two looks 2 s apart (the Simulator draws in software,
        // so under test load playback may run slower than real time)
        let f0 = num("frames"), p0 = num("position")
        Thread.sleep(forTimeInterval: 2)
        XCTAssertGreaterThan(num("frames"), f0 + 10, "the video view draws new frames")
        XCTAssertGreaterThan(num("position"), p0 + 0.3)

        XCTAssertTrue(waitFor(timeout: 20) { $0["controlsVisible"] as? Bool == false }, "controls auto-hide after the delay")
        shot("g02-controls-hidden")
    }

    func testTapTogglesTheControls() throws {
        try XCTSkipIf(isPad)
        launch("player-vod", ["-barsHideSeconds", "0", "-playerSeek", "40"])
        XCTAssertTrue(waitFor { $0["controlsVisible"] as? Bool == true })
        at(0.5, 0.25).tap()
        XCTAssertTrue(waitFor(timeout: 3) { $0["controlsVisible"] as? Bool == false }, "a tap hides the controls")
        shot("g03-controls-hidden-by-tap")
        at(0.5, 0.25).tap()
        XCTAssertTrue(waitFor(timeout: 3) { $0["controlsVisible"] as? Bool == true }, "a second tap shows them")
        shot("g03-controls-shown-by-tap")
    }

    func testSkipScrubLevelsAndPinchOnAPausedMovie() throws {
        try XCTSkipIf(isPad)
        launch("player-vod", ["-playerSeek", "60", "-playerPaused", "YES", "-barsHideSeconds", "0"])
        XCTAssertTrue(waitFor { $0["paused"] as? Bool == true && ($0["position"] as? Double ?? 0) > 55 })
        let start = num("position")

        // double tap right / left = +/- 10 s (the skip step), with the ripple
        at(0.85, 0.4).doubleTap()
        XCTAssertTrue(waitFor(timeout: 4) { abs(($0["position"] as? Double ?? 0) - (start + 10)) < 3 }, "double tap right skips forward 10 s")
        shot("g04-skip-forward")
        at(0.15, 0.4).doubleTap()
        XCTAssertTrue(waitFor(timeout: 4) { abs(($0["position"] as? Double ?? 0) - start) < 3 }, "double tap left skips back 10 s")

        // horizontal drag = scrub: 40 % of the width on a 3 minute file (a 60 s span) is about 24 s
        let before = num("position")
        at(0.3, 0.4).press(forDuration: 0.05, thenDragTo: at(0.7, 0.4))
        XCTAssertTrue(waitFor(timeout: 4) { abs(($0["position"] as? Double ?? 0) - (before + 24)) < 8 }, "a drag to the right scrubs forward about 24 s (was \(before), now \(self.num("position")))")

        // vertical drag on the left half = brightness, on the right half = volume (the Simulator has no system slider: mpv's gain)
        let v0 = Double(str("volume")) ?? 100
        at(0.85, 0.3).press(forDuration: 0.05, thenDragTo: at(0.85, 0.8))
        XCTAssertTrue(waitFor(timeout: 3) { abs((Double($0["volume"] as? String ?? "") ?? 100) - v0) > 10 }, "a drag down on the right half lowers the volume")
        let b0 = num("brightness")
        at(0.15, 0.6).press(forDuration: 0.05, thenDragTo: at(0.15, 0.2))
        XCTAssertTrue(waitFor(timeout: 3) { (($0["gestures"] as? [String: Int]) ?? [:])["panBegan", default: 0] >= 3 }, "the left drag was recognised")
        print("BRIGHTNESS \(b0) -> \(num("brightness"))")

        // pinch = fit -> fill -> back
        XCTAssertEqual(str("scale"), "fit")
        app.pinch(withScale: 2.5, velocity: 3)
        XCTAssertTrue(waitFor(timeout: 4) { $0["scale"] as? String == "fill" }, "pinching out fills the screen")
        shot("g05-scale-fill")
        app.pinch(withScale: 0.4, velocity: -3)
        XCTAssertTrue(waitFor(timeout: 4) { $0["scale"] as? String == "fit" }, "pinching in goes back")
    }

    func testLongPressBoostAndFlickDismiss() throws {
        try XCTSkipIf(isPad)
        launch("player-vod", ["-barsHideSeconds", "0", "-playerSeek", "30"])
        // long press = 2x while held, 1x again on release
        let sawBoost = Flag()
        let polling = Flag(); polling.value = true
        DispatchQueue.global().async {                     // watches the status while the (slow to start) press is held
            while polling.value { if (self.status()["speed"] as? Double) == 2 { sawBoost.value = true }; Thread.sleep(forTimeInterval: 0.2) }
        }
        at(0.5, 0.3).press(forDuration: 5)
        polling.value = false
        XCTAssertTrue(sawBoost.value, "2x while the finger is held")
        XCTAssertTrue(waitFor(timeout: 4) { ($0["speed"] as? Double) == 1 }, "and back to 1x on release")

        // a long fast flick down closes the player
        at(0.85, 0.2).press(forDuration: 0.02, thenDragTo: at(0.85, 0.95), withVelocity: XCUIGestureVelocity(rawValue: 3500), thenHoldForDuration: 0)
        XCTAssertTrue(waitFor(timeout: 6) { $0["player"] as? String == "none" }, "a long fast swipe down closes the player")
    }

    func testMenusAndSheetsOnAMovie() throws {
        try XCTSkipIf(isPad)
        launch("player-vod", ["-barsHideSeconds", "0", "-playerSeek", "30", "-playerPaused", "YES"])
        XCTAssertTrue(waitFor { ($0["tracks"] as? Int ?? 0) >= 5 })

        app.buttons["Subtitles"].tap()
        Thread.sleep(forTimeInterval: 0.8)
        shot("m01-subtitle-menu")
        app.buttons["Hebrew"].firstMatch.tap()
        XCTAssertTrue(waitFor(timeout: 3) { ($0["sid"] as? String ?? "no") != "no" }, "choosing a subtitle track selects it")
        Thread.sleep(forTimeInterval: 1)
        shot("m02-subtitles-on")

        app.buttons["Audio"].tap()
        Thread.sleep(forTimeInterval: 0.8)
        shot("m03-audio-menu")
        XCTAssertTrue(app.buttons["English"].firstMatch.exists, "the audio menu lists the file's tracks")
        app.buttons["Hebrew"].firstMatch.tap()                 // the Simulator's libmpv has no audio output, so the choice cannot be heard or read back
        Thread.sleep(forTimeInterval: 0.5)

        app.buttons["Sleep timer"].tap()
        Thread.sleep(forTimeInterval: 0.8)
        shot("m04-sleep-menu")
        app.buttons["30 minutes"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 1)
        shot("m05-sleep-set")

        app.buttons["Video scale"].tap()
        Thread.sleep(forTimeInterval: 0.8)
        shot("m06-scale-menu")
        app.buttons["Fill"].firstMatch.tap()
        XCTAssertTrue(waitFor(timeout: 3) { $0["scale"] as? String == "fill" })

        app.buttons["Playback speed"].tap()
        Thread.sleep(forTimeInterval: 1)
        shot("m07-speed-sheet")
        app.buttons["2×"].firstMatch.tap()
        XCTAssertTrue(waitFor(timeout: 3) { ($0["speed"] as? Double) == 2 }, "a preset sets the speed")
        tapHittable("Close")
        Thread.sleep(forTimeInterval: 1)
        shot("m08-speed-2x")
    }

    // MARK: live

    func testLiveZappingAndFavorite() throws {
        launch("player-live", ["-barsHideSeconds", "0"])
        let first = str("title")
        XCTAssertTrue(flag("live"))
        shot("l01-live")
        app.buttons["Next channel"].tap()
        XCTAssertTrue(waitFor(timeout: 8) { ($0["title"] as? String ?? "") != first && ($0["frames"] as? Int ?? 0) > 0 }, "next channel")
        let second = str("title")
        Thread.sleep(forTimeInterval: 2)
        shot("l02-next-channel")
        app.buttons["Previous channel"].tap()
        XCTAssertTrue(waitFor(timeout: 8) { ($0["title"] as? String ?? "") == first }, "previous channel goes back (\(second) -> \(first))")
        app.buttons["player.favorite"].tap()
        XCTAssertTrue(app.buttons["player.favorite"].label == "Remove from favorites" || app.buttons["Remove from favorites"].waitForExistence(timeout: 3), "the star toggles")
        shot("l03-favorite")
    }

    func testErrorCardAndRetry() throws {
        launch("player-error", ["-barsHideSeconds", "0"])
        XCTAssertTrue(app.buttons["Retry"].waitForExistence(timeout: 10))
        shot("e01-error")
        app.buttons["Retry"].tap()
        XCTAssertTrue(app.buttons["Retry"].waitForExistence(timeout: 10), "a stream that still fails shows the card again")
        tapHittable("Close")
        XCTAssertTrue(waitFor(timeout: 5) { $0["player"] as? String == "none" || $0["title"] == nil })
    }

    // MARK: rotation (iPad and iPhone)

    func testRotationFollowsTheDevice() throws {
        launch("player-vod", ["-barsHideSeconds", "0", "-playerSeek", "20", "-playerOrientation", "portrait"])
        rotate(.portrait)
        XCTAssertTrue(waitFor { $0["orientation"] as? String == "portrait" })
        shot("r01-portrait")
        rotate(.landscapeLeft)
        XCTAssertTrue(waitFor(timeout: 6) { $0["orientation"] as? String == "landscape" }, "rotating the device rotates the player")
        shot("r02-landscape")
        rotate(.portrait)
        XCTAssertTrue(waitFor(timeout: 6) { $0["orientation"] as? String == "portrait" })
        XCTAssertGreaterThan(num("frames"), 20)
        shot("r03-portrait-again")
    }
}
