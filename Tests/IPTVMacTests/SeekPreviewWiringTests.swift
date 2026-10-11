import AppKit
import Testing
import Foundation
import IPTVPlayer
@testable import IPTVMac

private func image(_ gray: UInt8) -> CGImage {
    let ctx = CGContext(data: nil, width: 8, height: 4, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(gray: CGFloat(gray) / 255, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 4))
    return ctx.makeImage()!
}

// MARK: wiring in the player

private func request(_ url: String, live: Bool = false) -> PlayRequest {
    PlayRequest(title: "t", url: URL(string: url) ?? URL(fileURLWithPath: url), isLive: live, item: nil)
}

@MainActor @Test func aNetworkItemGetsNoPreviewUnlessTheSettingIsOn() async throws {
    let d = UserDefaults.standard
    defer { d.removeObject(forKey: "seekPreview") }
    d.removeObject(forKey: "seekPreview")
    let pm = PlayerModel(request: request("http://127.0.0.1:9/movie/u/p/1.mkv"))   // nothing listens on port 9
    defer { pm.close() }
    pm.duration = 100
    pm.previewHover(10)
    #expect(pm.preview.look == .none, "the setting is off by default: no second connection")
    d.set(true, forKey: "seekPreview")
    pm.previewHover(10)
    #expect(pm.preview.look == .loading, "switched on while watching: the next hover starts the preview")
    for _ in 0..<150 where pm.preview.look == .loading { try await Task.sleep(for: .milliseconds(40)) }
    #expect(pm.preview.look == .none, "a connection that cannot be opened silently turns the preview off for this item")
}

@MainActor @Test func aLocalFileGetsPreviewsWithoutAnySetting() {
    UserDefaults.standard.removeObject(forKey: "seekPreview")
    let pm = PlayerModel(request: PlayRequest(title: "t", url: URL(fileURLWithPath: "/nonexistent/download.mkv"), isLive: false, item: nil))
    defer { pm.close() }
    pm.duration = 100
    pm.previewHover(10)
    #expect(pm.preview.look == .loading)
}

@MainActor @Test func aLiveStreamNeverGetsAPreviewEvenWithTheSettingOn() {
    let d = UserDefaults.standard
    defer { d.removeObject(forKey: "seekPreview") }
    d.set(true, forKey: "seekPreview")
    let pm = PlayerModel(request: request("http://127.0.0.1:9/live/u/p/1.ts", live: true))
    defer { pm.close() }
    pm.duration = 100
    pm.previewHover(10)
    #expect(pm.preview.look == .none)
}

@MainActor @Test func changingTheItemDropsTheOldPreviewAndClosingStopsItForGood() {
    let pm = PlayerModel(request: PlayRequest(title: "a", url: URL(fileURLWithPath: "/nonexistent/a.mkv"), isLive: false, item: nil))
    pm.duration = 100
    pm.previewHover(10)
    pm.preview.received(time: 10, image: image(9), duration: 100)
    #expect(pm.preview.look != .none)
    pm.replace(with: PlayRequest(title: "b", url: URL(fileURLWithPath: "/nonexistent/b.mkv"), isLive: false, item: nil))
    #expect(pm.preview.look == .none, "the next episode must not show the last one's frames")
    pm.duration = 100
    pm.previewHover(10)
    #expect(pm.preview.look == .loading, "and gets its own previewer")
    pm.close()
    #expect(pm.preview.look == .none)
    pm.previewHover(10)
    pm.replace(with: PlayRequest(title: "c", url: URL(fileURLWithPath: "/nonexistent/c.mkv"), isLive: false, item: nil))
    pm.duration = 100
    pm.previewHover(10)
    #expect(pm.preview.look == .none, "a closed player never starts a previewer again")
}
