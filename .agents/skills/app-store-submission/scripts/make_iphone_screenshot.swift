import AppKit

// args: <source iPad png> <output png> <headline>
let args = CommandLine.arguments
guard args.count >= 4 else { fatalError("need src out headline") }
let srcPath = args[1], outPath = args[2], headline = args[3]

let W = 1242, H = 2688
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H,
  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
  colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
let S = CGFloat(W), HT = CGFloat(H)
let full = NSRect(x: 0, y: 0, width: S, height: HT)

// Brand gradient background (matches app icon: navy -> vivid blue).
let navy = NSColor(srgbRed: 0.06, green: 0.14, blue: 0.34, alpha: 1)
let blue = NSColor(srgbRed: 0.16, green: 0.45, blue: 0.96, alpha: 1)
NSGradient(starting: navy, ending: blue)!.draw(in: full, angle: -65)

// Headline near the top.
let para = NSMutableParagraphStyle(); para.alignment = .center
let title = NSAttributedString(string: headline, attributes: [
  .font: NSFont.systemFont(ofSize: 78, weight: .bold),
  .foregroundColor: NSColor.white,
  .paragraphStyle: para])
let titleRect = NSRect(x: 80, y: HT - 360, width: S - 160, height: 260)
title.draw(in: titleRect)

// Load source screenshot.
guard let img = NSImage(contentsOfFile: srcPath),
      let tiff = img.tiffRepresentation,
      let src = NSBitmapImageRep(data: tiff) else { fatalError("bad src") }
let sw = CGFloat(src.pixelsWide), sh = CGFloat(src.pixelsHigh)

// Fit the screenshot into a centered card.
let cardW = S * 0.86
let cardH = cardW * (sh / sw)
let cardX = (S - cardW) / 2
let cardY = (HT - 420 - cardH) / 2 + 40
let card = NSRect(x: cardX, y: cardY, width: cardW, height: cardH)

// Shadow + rounded clip.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -22), blur: 50,
              color: NSColor(white: 0, alpha: 0.35).cgColor)
let radius: CGFloat = 38
let clip = NSBezierPath(roundedRect: card, xRadius: radius, yRadius: radius)
NSColor.white.setFill(); clip.fill()   // white backing so shadow renders
ctx.restoreGState()

ctx.saveGState()
clip.addClip()
src.draw(in: card)
ctx.restoreGState()

// Thin light border on the card.
NSColor(white: 1, alpha: 0.25).setStroke()
let border = NSBezierPath(roundedRect: card, xRadius: radius, yRadius: radius)
border.lineWidth = 3; border.stroke()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)  (\(W)x\(H))")
