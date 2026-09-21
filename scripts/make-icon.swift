#!/usr/bin/env swift

import AppKit

// Renders the app icon into resources/CapsAwake.icns. The result is checked in, so
// this only needs running when the artwork changes.
//
// The Caps Lock glyph is drawn from paths instead of taken from SF Symbols, whose
// licence does not allow symbols in an app icon.

/// `iconutil` names each variant by its point size and scale.
let variants: [(pixels: Int, name: String)] = [
    (16, "icon_16x16"), (32, "icon_16x16@2x"),
    (32, "icon_32x32"), (64, "icon_32x32@2x"),
    (128, "icon_128x128"), (256, "icon_128x128@2x"),
    (256, "icon_256x256"), (512, "icon_256x256@2x"),
    (512, "icon_512x512"), (1024, "icon_512x512@2x"),
]

/// The arrow over a bar that is printed on the key itself.
func capsLockGlyph() -> NSBezierPath {
    let path = NSBezierPath()
    path.move(to: NSPoint(x: 512, y: 782))
    path.line(to: NSPoint(x: 300, y: 520))
    path.line(to: NSPoint(x: 724, y: 520))
    path.close()
    path.appendRect(NSRect(x: 386, y: 350, width: 252, height: 170))
    path.append(
        NSBezierPath(
            roundedRect: NSRect(x: 386, y: 242, width: 252, height: 72),
            xRadius: 14,
            yRadius: 14
        )
    )
    return path
}

/// Everything is laid out on a 1024-point canvas and scaled to the variant.
func drawIcon(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let scale = NSAffineTransform()
    scale.scale(by: CGFloat(pixels) / 1024)
    scale.concat()

    // A macOS icon leaves a margin inside its canvas rather than filling it.
    let plate = NSBezierPath(
        roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824),
        xRadius: 185,
        yRadius: 185
    )
    NSGradient(
        starting: NSColor(srgbRed: 0.13, green: 0.16, blue: 0.24, alpha: 1),
        ending: NSColor(srgbRed: 0.30, green: 0.38, blue: 0.52, alpha: 1)
    )!.draw(in: plate, angle: 90)

    NSColor.white.setFill()
    capsLockGlyph().fill()

    return rep.representation(using: .png, properties: [:])!
}

func makeIcon() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let iconset = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "CapsAwake.iconset")
    try? FileManager.default.removeItem(at: iconset)
    try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: iconset) }

    for variant in variants {
        try drawIcon(pixels: variant.pixels)
            .write(to: iconset.appending(path: "\(variant.name).png"))
    }

    let output = root.appending(path: "resources/CapsAwake.icns")
    let iconutil = Process()
    iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    iconutil.arguments = ["--convert", "icns", "--output", output.path, iconset.path]
    try iconutil.run()
    iconutil.waitUntilExit()
    guard iconutil.terminationStatus == 0 else { exit(iconutil.terminationStatus) }
    print(output.path)
}

do {
    try makeIcon()
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}
