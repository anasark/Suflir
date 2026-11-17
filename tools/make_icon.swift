// Draws the Suflir app icon. Usage: swift tools/make_icon.swift <output.png>
import AppKit

let size = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Rounded square body, on the standard macOS icon grid.
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
shape.addClip()
NSGradient(colors: [NSColor(srgbRed: 0.42, green: 0.36, blue: 1.00, alpha: 1),
                    NSColor(srgbRed: 0.10, green: 0.08, blue: 0.30, alpha: 1)])!
    .draw(in: body, angle: -90)

// The notch, hanging from the top edge.
NSColor.black.setFill()
NSBezierPath(roundedRect: NSRect(x: 352, y: 824, width: 320, height: 200), xRadius: 44, yRadius: 44).fill()

// Script lines under the notch: the line being read is brightest.
let lines: [(width: CGFloat, y: CGFloat, alpha: CGFloat)] = [
    (540, 650, 1.00), (430, 520, 0.60), (310, 390, 0.32), (190, 260, 0.14),
]
for line in lines {
    NSColor(white: 1, alpha: line.alpha).setFill()
    let rect = NSRect(x: 512 - line.width / 2, y: line.y - 30, width: line.width, height: 60)
    NSBezierPath(roundedRect: rect, xRadius: 30, yRadius: 30).fill()
}

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
