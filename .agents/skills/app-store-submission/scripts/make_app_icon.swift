import AppKit

let px = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/AppIcon-1024.png"
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
  colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
let S = CGFloat(px)
let full = NSRect(x: 0, y: 0, width: S, height: S)

// Deep navy -> vivid blue diagonal gradient.
let navy = NSColor(srgbRed: 0.05, green: 0.12, blue: 0.32, alpha: 1)
let blue = NSColor(srgbRed: 0.16, green: 0.45, blue: 0.96, alpha: 1)
NSGradient(starting: navy, ending: blue)!.draw(in: full, angle: -55)
// Soft highlight, top-left, for depth.
let hi = NSGradient(colors: [NSColor(white: 1, alpha: 0.18), NSColor(white: 1, alpha: 0)])!
hi.draw(in: full, relativeCenterPosition: NSPoint(x: -0.45, y: 0.5))

// White notepad card (rounded), slight rotation for character.
ctx.saveGState()
ctx.translateBy(x: S/2, y: S/2)
ctx.rotate(by: -6 * .pi/180)
let cardW: CGFloat = S*0.46, cardH: CGFloat = S*0.56
let card = NSRect(x: -cardW/2, y: -cardH/2, width: cardW, height: cardH)
ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 40, color: NSColor(white: 0, alpha: 0.28).cgColor)
let cardPath = NSBezierPath(roundedRect: card, xRadius: 46, yRadius: 46)
NSColor.white.setFill(); cardPath.fill()
ctx.setShadow(offset: .zero, blur: 0, color: nil)
// Top binding bar (brand gold).
let gold = NSColor(srgbRed: 0.98, green: 0.74, blue: 0.16, alpha: 1)
let bar = NSBezierPath(roundedRect: NSRect(x: card.minX, y: card.maxY - S*0.085, width: cardW, height: S*0.085), xRadius: 46, yRadius: 46)
gold.setFill(); bar.fill()
NSColor.white.setFill(); NSRect(x: card.minX, y: card.maxY - S*0.085, width: cardW, height: S*0.04).fill()
// Note lines.
let lineColor = NSColor(srgbRed: 0.78, green: 0.83, blue: 0.92, alpha: 1)
lineColor.setStroke()
let lineX0 = card.minX + S*0.05, lineX1 = card.maxX - S*0.05
for i in 0..<4 {
    let y = card.maxY - S*0.17 - CGFloat(i) * S*0.075
    let p = NSBezierPath(); p.lineWidth = 14; p.lineCapStyle = .round
    p.move(to: NSPoint(x: lineX0, y: y)); p.line(to: NSPoint(x: i == 3 ? (lineX0+lineX1)/2 : lineX1, y: y))
    p.stroke()
}
ctx.restoreGState()

// Blue pencil over the card (body + tip), bottom-left to top-right.
ctx.saveGState()
ctx.translateBy(x: S*0.30, y: S*0.30)
ctx.rotate(by: 48 * .pi/180)
let pw: CGFloat = S*0.11, pl: CGFloat = S*0.46
let body = NSBezierPath(roundedRect: NSRect(x: -pw/2, y: 0, width: pw, height: pl), xRadius: 10, yRadius: 10)
NSColor(srgbRed: 0.12, green: 0.40, blue: 0.92, alpha: 1).setFill(); body.fill()
// Tip
let tip = NSBezierPath()
tip.move(to: NSPoint(x: -pw/2, y: pl)); tip.line(to: NSPoint(x: pw/2, y: pl)); tip.line(to: NSPoint(x: 0, y: pl + pw*0.9)); tip.close()
NSColor(srgbRed: 0.99, green: 0.84, blue: 0.45, alpha: 1).setFill(); tip.fill()
let lead = NSBezierPath()
lead.move(to: NSPoint(x: -pw*0.16, y: pl + pw*0.55)); lead.line(to: NSPoint(x: pw*0.16, y: pl + pw*0.55)); lead.line(to: NSPoint(x: 0, y: pl + pw*0.9)); lead.close()
NSColor(white: 0.15, alpha: 1).setFill(); lead.fill()
// Eraser end
NSColor(srgbRed: 0.96, green: 0.45, blue: 0.45, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: -pw/2, y: -pw*0.5, width: pw, height: pw*0.5), xRadius: 8, yRadius: 8).fill()
ctx.restoreGState()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
