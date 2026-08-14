// Draws the Live Clip Envelopes app icon: a dark squircle (echoing Ableton Live's own
// icon proportions and palette, without reproducing its actual wordmark/logo) with an
// original teal step-envelope curve across the middle — the same shape as the
// breakpoint curves the app itself edits.
//
// Emits a complete AppIcon.iconset and, if iconutil is available, AppIcon.icns.
//
//   swiftc -O -o icongen main.swift && ./icongen [output.icns]
//
// Geometry follows Apple's macOS app-icon grid, and matches the working reference at
// ~/work/apple/phonemirror/make-icon.swift:
//
//   margin  M = S * 0.0977      (100 of 1024)
//   body    A = S - 2M          (824 of 1024)
//   corner    = A * 0.2248      (185.4 at 1024, i.e. 22.5% of the BODY, not the canvas)
//
// Two mistakes this file used to make, both visible in the Dock:
//   - it filled the WHOLE canvas, so the icon rendered noticeably larger than every
//     other app's, and at 16x16 the corner radius rounded away to a hard square;
//   - it rendered one 1024 master and let the caller downscale, which on a Retina
//     display silently produced a 2048 image and mushy small sizes.
// Each size is now drawn natively at its own pixel size, and carries the soft contact
// shadow Apple's own icons have.

import AppKit
import Foundation

func drawIcon(size S: CGFloat) -> NSBitmapImageRep {
    let px = Int(S)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let context = NSGraphicsContext.current!.cgContext
    context.setShouldAntialias(true)

    let margin = S * 0.0977
    let body = NSRect(x: margin, y: margin, width: S - 2 * margin, height: S - 2 * margin)
    let side = body.width
    let corner = side * 0.2248

    //--------------------------------------------------------------------------------
    // Soft contact shadow, which is what makes an icon sit on the Dock rather than
    // float above it. The transparent margin above exists partly to hold it.
    //--------------------------------------------------------------------------------
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -side * 0.012), blur: side * 0.045,
                      color: NSColor(calibratedWhite: 0, alpha: 0.35).cgColor)
    let silhouette = NSBezierPath(roundedRect: body, xRadius: corner, yRadius: corner)
    NSColor(calibratedWhite: 0.10, alpha: 1).setFill()
    silhouette.fill()
    context.restoreGState()

    //--------------------------------------------------------------------------------
    // Background: a subtle vertical gradient so it doesn't read as flat.
    //--------------------------------------------------------------------------------
    context.saveGState()
    let background = NSBezierPath(roundedRect: body, xRadius: corner, yRadius: corner)
    background.addClip()
    NSGradient(colors: [
        NSColor(calibratedWhite: 0.13, alpha: 1.0),
        NSColor(calibratedWhite: 0.06, alpha: 1.0),
    ])?.draw(in: body, angle: -90)

    //--------------------------------------------------------------------------------
    // The step-envelope curve: flat segments joined by short verticals, the shape Live
    // draws for a stepped clip envelope. Teal on near-black, the app's own curve colour.
    //--------------------------------------------------------------------------------
    let inset = side * 0.18
    let curveRect = body.insetBy(dx: inset, dy: inset * 1.35)
    let steps: [CGFloat] = [0.35, 0.72, 0.5, 0.2, 0.6, 0.42, 0.8]
    let stepWidth = curveRect.width / CGFloat(steps.count)

    let curve = NSBezierPath()
    curve.lineWidth = side * 0.045
    curve.lineCapStyle = .round
    curve.lineJoinStyle = .round

    func level(_ index: Int) -> CGFloat {
        curveRect.minY + steps[index] * curveRect.height
    }

    curve.move(to: NSPoint(x: curveRect.minX, y: level(0)))
    for i in 0..<steps.count {
        let x = curveRect.minX + CGFloat(i + 1) * stepWidth
        curve.line(to: NSPoint(x: x, y: level(i)))
        if i + 1 < steps.count {
            curve.line(to: NSPoint(x: x, y: level(i + 1)))
        }
    }

    //--------------------------------------------------------------------------------
    // A glow behind the stroke, then the crisp stroke on top. The glow is skipped at
    // small sizes, where it only muddies the shape.
    //--------------------------------------------------------------------------------
    context.saveGState()
    if S >= 128 {
        context.setShadow(offset: .zero, blur: side * 0.05,
                          color: NSColor(calibratedRed: 0.25, green: 0.95, blue: 0.85, alpha: 0.55).cgColor)
    }
    NSColor(calibratedRed: 0.30, green: 0.95, blue: 0.85, alpha: 1.0).setStroke()
    curve.stroke()
    context.restoreGState()
    context.restoreGState()

    return rep
}

// The exact set iconutil expects.
let specs: [(name: String, px: CGFloat)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.icns"
let workDir = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("LiveClipEnvelopes-AppIcon.iconset")
let fileManager = FileManager.default
try? fileManager.removeItem(at: workDir)
try! fileManager.createDirectory(at: workDir, withIntermediateDirectories: true)

for spec in specs {
    let rep = drawIcon(size: spec.px)
    guard let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("could not encode \(spec.name)")
    }
    try! png.write(to: workDir.appendingPathComponent(spec.name))
}
print("drew \(specs.count) sizes natively (16 … 1024)")

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["--convert", "icns", "--output", output, workDir.path]
try! iconutil.run()
iconutil.waitUntilExit()
if iconutil.terminationStatus == 0 {
    print("wrote \(output)")
} else {
    fatalError("iconutil failed (\(iconutil.terminationStatus))")
}
