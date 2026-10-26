// SPDX-License-Identifier: GPL-3.0-or-later
// Original NotchCraft community artwork; no upstream logo assets are used.
import AppKit

let output = CommandLine.arguments[1]
let directory = URL(fileURLWithPath: output)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
func png(_ pixels: Int, glyph: Bool) -> Data {
    let height = glyph ? pixels * 20 / 26 : pixels
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let n = CGFloat(height)
    if glyph { NSGraphicsContext.current?.cgContext.translateBy(x: CGFloat(pixels - height) / 2, y: 0) }
    if !glyph {
        NSColor(calibratedRed: 0.08, green: 0.15, blue: 0.23, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: n * 0.07, y: n * 0.07, width: n * 0.86, height: n * 0.86),
                     xRadius: n * 0.2, yRadius: n * 0.2).fill()
    }
    (glyph ? NSColor.black : NSColor(calibratedRed: 0.25, green: 0.87, blue: 0.75, alpha: 1)).setStroke()
    let path = NSBezierPath()
    path.lineWidth = n * 0.065
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.move(to: NSPoint(x: n * 0.26, y: n * 0.32))
    path.line(to: NSPoint(x: n * 0.26, y: n * 0.68))
    path.line(to: NSPoint(x: n * 0.40, y: n * 0.68))
    path.line(to: NSPoint(x: n * 0.40, y: n * 0.55))
    path.line(to: NSPoint(x: n * 0.60, y: n * 0.55))
    path.line(to: NSPoint(x: n * 0.60, y: n * 0.68))
    path.line(to: NSPoint(x: n * 0.74, y: n * 0.68))
    path.line(to: NSPoint(x: n * 0.74, y: n * 0.32))
    path.stroke()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 2 ? "@2x" : ""
        try png(size * scale, glyph: false).write(to: directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
let parent = directory.deletingLastPathComponent()
try png(26, glyph: true).write(to: parent.appendingPathComponent("MenuBarIcon.png"))
try png(52, glyph: true).write(to: parent.appendingPathComponent("MenuBarIcon@2x.png"))
try png(256, glyph: false).write(to: parent.appendingPathComponent("BrandMark.png"))
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", output, "-o", parent.appendingPathComponent("AppIcon.icns").path]
try process.run()
process.waitUntilExit()
exit(process.terminationStatus)
