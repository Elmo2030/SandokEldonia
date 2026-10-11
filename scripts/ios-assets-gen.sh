#!/bin/bash
# Redraws the pixel assets of ios/Resources/Assets.xcassets from code (same artwork as scripts/icon/icon.swift, adapted for iOS):
#   AppIcon-1024.png  full-bleed 1024x1024 square, opaque RGB, no rounded corners, no shadow (iOS applies its own mask)
#   LogoMark*.png     the TV glyph alone on transparency, 160 pt at 1x/2x/3x (launch screen, onboarding, About)
# Headless: no window is opened. Output is deterministic; re-running rewrites the same bytes' worth of pixels.
set -euo pipefail
cd "$(dirname "$0")/.."
SET=ios/Resources/Assets.xcassets
mkdir -p "$SET/AppIcon.appiconset" "$SET/LogoMark.imageset"
SRC="$(mktemp -d)/draw.swift"; trap 'rm -rf "$(dirname "$SRC")"' EXIT
cat > "$SRC" <<'SWIFT'
import AppKit

func color(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: a)
}

/// Draws into a px x px bitmap (opaque RGB when `opaque`), calling `draw` in a 1024-unit coordinate space.
func render(px: Int, opaque: Bool, to path: String, _ draw: () -> Void) {
    let info = opaque ? CGImageAlphaInfo.noneSkipLast.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info)!
    ctx.scaleBy(x: CGFloat(px) / 1024, y: CGFloat(px) / 1024)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

/// White TV with a violet play triangle (the macOS icon's foreground), centred on (512, 549) in the 1024 space.
func tv() {
    let screen = NSRect(x: 222, y: 400, width: 580, height: 380)
    color(0x0B1020, 0.28).setFill()
    NSBezierPath(roundedRect: screen.offsetBy(dx: 0, dy: -10), xRadius: 78, yRadius: 78).fill()
    NSColor.white.setFill()
    NSBezierPath(roundedRect: screen, xRadius: 78, yRadius: 78).fill()
    NSBezierPath(roundedRect: NSRect(x: 452, y: 352, width: 120, height: 56), xRadius: 14, yRadius: 14).fill()
    NSBezierPath(roundedRect: NSRect(x: 352, y: 318, width: 320, height: 46), xRadius: 23, yRadius: 23).fill()
    let tri = NSBezierPath()
    tri.move(to: NSPoint(x: 458, y: 484)); tri.line(to: NSPoint(x: 458, y: 696)); tri.line(to: NSPoint(x: 650, y: 590)); tri.close()
    tri.lineJoinStyle = .round; tri.lineWidth = 34
    color(0x5B3DE0).setFill(); tri.fill()
    color(0x5B3DE0).setStroke(); tri.stroke()
}

let dir = CommandLine.arguments[1]

// App icon: the gradient fills the whole square; the TV is scaled 1.2x and centred because the macOS body was 824 of 1024.
render(px: 1024, opaque: true, to: "\(dir)/AppIcon.appiconset/AppIcon-1024.png") {
    let full = NSRect(x: 0, y: 0, width: 1024, height: 1024)
    NSGradient(colors: [color(0x2563EB), color(0x6D28D9)])!.draw(in: full, angle: -55)
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.22), NSColor.white.withAlphaComponent(0)])!
        .draw(in: NSRect(x: 0, y: 512, width: 1024, height: 512), angle: -90)
    let c = NSGraphicsContext.current!.cgContext
    c.translateBy(x: 512, y: 512); c.scaleBy(x: 1.2, y: 1.2); c.translateBy(x: -512, y: -549)   // glyph centre (512, 549) -> canvas centre
    tv()
}

// Logo mark: the glyph alone, centred in a 640-unit square (so the shadow is not clipped), 160 pt at 1x, 2x, 3x.
for (scale, suffix) in [(1, ""), (2, "@2x"), (3, "@3x")] {
    render(px: 160 * scale, opaque: false, to: "\(dir)/LogoMark.imageset/LogoMark\(suffix).png") {
        let c = NSGraphicsContext.current!.cgContext
        c.scaleBy(x: 1024.0 / 640, y: 1024.0 / 640)      // 640-unit canvas
        c.translateBy(x: 320 - 512, y: 320 - 549)        // glyph centre -> canvas centre
        tv()
    }
}
SWIFT
swift "$SRC" "$SET"
echo "wrote $SET/AppIcon.appiconset/AppIcon-1024.png and $SET/LogoMark.imageset/LogoMark{,@2x,@3x}.png"
