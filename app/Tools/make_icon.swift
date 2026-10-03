// Génère app/Resources/Classeur.icns et plugins/classeur/assets/icon.png :
// une enveloppe blanche, dans l'esprit d'Apple Mail, sur le fond indigo de Classeur.
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
        CGColor(red: 0.62, green: 0.54, blue: 1, alpha: 0.45),
        CGColor(red: 0.45, green: 0.3, blue: 1, alpha: 0),
    ] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: center, startRadius: s * 0.1, endCenter: center, endRadius: s * 0.44, options: [])
    drawEnvelope(ctx, s)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

// Enveloppe blanche à rabat, coins arrondis et plis gris clair, posée avec une ombre douce.
func drawEnvelope(_ ctx: CGContext, _ s: CGFloat) {
    let space = CGColorSpaceCreateDeviceRGB()
    let body = CGRect(x: s * 0.215, y: s * 0.305, width: s * 0.57, height: s * 0.39)
    let radius = s * 0.04
    let bodyPath = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.018), blur: s * 0.045,
                  color: CGColor(red: 0.03, green: 0.01, blue: 0.2, alpha: 0.55))
    ctx.addPath(bodyPath)
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()
    let paper = CGGradient(colorsSpace: space, colors: [
        CGColor(red: 1, green: 1, blue: 1, alpha: 1),
        CGColor(red: 0.9, green: 0.91, blue: 0.94, alpha: 1),
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(paper, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY), options: [])

    let fold = CGColor(red: 0.74, green: 0.76, blue: 0.82, alpha: 1)
    let line = max(1, s * 0.009)
    ctx.setStrokeColor(fold)
    ctx.setLineWidth(line)
    ctx.setLineCap(.round)
    let apex = CGPoint(x: body.midX, y: body.minY + body.height * 0.4)
    ctx.move(to: CGPoint(x: body.minX, y: body.minY))
    ctx.addLine(to: CGPoint(x: body.midX - body.width * 0.12, y: apex.y + body.height * 0.06))
    ctx.move(to: CGPoint(x: body.maxX, y: body.minY))
    ctx.addLine(to: CGPoint(x: body.midX + body.width * 0.12, y: apex.y + body.height * 0.06))
    ctx.strokePath()

    let flap = CGMutablePath()
    flap.move(to: CGPoint(x: body.minX - line, y: body.maxY + line))
    flap.addLine(to: CGPoint(x: apex.x - body.width * 0.05, y: apex.y + body.height * 0.035))
    flap.addQuadCurve(to: CGPoint(x: apex.x + body.width * 0.05, y: apex.y + body.height * 0.035), control: apex)
    flap.addLine(to: CGPoint(x: body.maxX + line, y: body.maxY + line))
    flap.closeSubpath()
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.006), blur: s * 0.018,
                  color: CGColor(red: 0.1, green: 0.1, blue: 0.3, alpha: 0.28))
    ctx.addPath(flap)
    ctx.setFillColor(CGColor(red: 0.99, green: 0.99, blue: 1, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.addPath(flap)
    ctx.setStrokeColor(fold)
    ctx.setLineWidth(line)
    ctx.setLineJoin(.round)
    ctx.strokePath()
    ctx.restoreGState()
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
guard task.terminationStatus == 0 else {
    FileHandle.standardError.write("iconutil a échoué (code \(task.terminationStatus)) : vérifiez \(iconset.path)\n".data(using: .utf8)!)
    exit(1)
}
print("Icône écrite : \(out.path)")
let pluginIcon = root.deletingLastPathComponent().appendingPathComponent("plugins/classeur/assets/icon.png")
try render(512).write(to: pluginIcon)
print("Icône du plugin écrite : \(pluginIcon.path)")
