// Génère app/Resources/Classeur.icns : l'orbe Classeur sur fond indigo.
// Usage : swift app/Tools/make_icon.swift
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("Classeur.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(_ size: Int) -> Data {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let inset = s * 0.09
    let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let path = CGPath(roundedRect: rect, cornerWidth: rect.width * 0.23, cornerHeight: rect.width * 0.23, transform: nil)
    ctx.addPath(path)
    ctx.clip()
    let space = CGColorSpaceCreateDeviceRGB()
    let bg = CGGradient(colorsSpace: space, colors: [
        CGColor(red: 0.20, green: 0.13, blue: 0.88, alpha: 1),
        CGColor(red: 0.08, green: 0.04, blue: 0.45, alpha: 1),
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: s), end: CGPoint(x: s, y: 0), options: [])
    var seed: UInt64 = 7
    for _ in 0..<40 {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        let x = CGFloat(seed % 1000) / 1000 * s
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        let y = CGFloat(seed % 1000) / 1000 * s
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.35))
        ctx.fillEllipse(in: CGRect(x: x, y: y, width: s * 0.006, height: s * 0.006))
    }
    let center = CGPoint(x: s * 0.5, y: s * 0.5)
    let glow = CGGradient(colorsSpace: space, colors: [
        CGColor(red: 0.72, green: 0.64, blue: 1, alpha: 0.7),
        CGColor(red: 0.45, green: 0.3, blue: 1, alpha: 0),
    ] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: center, startRadius: s * 0.18, endCenter: center, endRadius: s * 0.42, options: [])
    let orb = CGGradient(colorsSpace: space, colors: [
        CGColor(red: 1, green: 1, blue: 1, alpha: 1),
        CGColor(red: 0.88, green: 0.84, blue: 1, alpha: 1),
        CGColor(red: 0.61, green: 0.51, blue: 1, alpha: 1),
        CGColor(red: 0.36, green: 0.24, blue: 0.94, alpha: 1),
    ] as CFArray, locations: [0, 0.3, 0.7, 1])!
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: center.x - s * 0.22, y: center.y - s * 0.22, width: s * 0.44, height: s * 0.44))
    ctx.clip()
    ctx.drawRadialGradient(orb, startCenter: CGPoint(x: center.x - s * 0.07, y: center.y + s * 0.08), startRadius: 0,
                           endCenter: center, endRadius: s * 0.24, options: [.drawsAfterEndLocation])
    ctx.restoreGState()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let out = root.appendingPathComponent("Resources/Classeur.icns")
try FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "Icône écrite : \(out.path)" : "iconutil a échoué")
