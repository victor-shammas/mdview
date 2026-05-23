#!/usr/bin/swift
import AppKit

func makeIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext

    let s = size
    let pad = s * 0.08
    let cornerRadius = s * 0.18
    let rect = CGRect(x: pad, y: pad, width: s - pad * 2, height: s - pad * 2)

    // Background: rounded rect with gradient
    let bgPath = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()
    let colors = [
        CGColor(red: 0.15, green: 0.15, blue: 0.18, alpha: 1.0),
        CGColor(red: 0.10, green: 0.10, blue: 0.13, alpha: 1.0),
    ]
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0.0, 1.0])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: s/2, y: rect.maxY), end: CGPoint(x: s/2, y: rect.minY), options: [])
    ctx.restoreGState()

    // Subtle inner border
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.08))
    ctx.setLineWidth(s * 0.01)
    ctx.strokePath()
    ctx.restoreGState()

    // Draw "MD" text
    let fontSize = s * 0.26
    let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
    let mdAttrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1.0),
    ]
    let mdStr = NSAttributedString(string: "MD", attributes: mdAttrs)
    let mdSize = mdStr.size()
    let mdX = (s - mdSize.width) / 2
    let mdY = (s - mdSize.height) / 2 + s * 0.06
    mdStr.draw(at: NSPoint(x: mdX, y: mdY))

    // Draw a small down-arrow / view indicator below
    let arrowSize = s * 0.06
    let arrowY = mdY - s * 0.04
    let arrowCenterX = s / 2
    ctx.saveGState()
    ctx.setFillColor(CGColor(red: 0.45, green: 0.70, blue: 1.0, alpha: 0.9))
    ctx.move(to: CGPoint(x: arrowCenterX - arrowSize, y: arrowY))
    ctx.addLine(to: CGPoint(x: arrowCenterX + arrowSize, y: arrowY))
    ctx.addLine(to: CGPoint(x: arrowCenterX, y: arrowY - arrowSize * 0.8))
    ctx.closePath()
    ctx.fillPath()
    ctx.restoreGState()

    // Three horizontal lines (text lines motif) above MD
    let lineWidth = s * 0.28
    let lineHeight = s * 0.018
    let lineStartY = mdY + mdSize.height + s * 0.04
    let lineSpacing = s * 0.04
    ctx.saveGState()
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.15))
    for i in 0..<3 {
        let w = i == 2 ? lineWidth * 0.6 : lineWidth
        let y = lineStartY + CGFloat(i) * lineSpacing
        let lineRect = CGRect(x: (s - w) / 2, y: y, width: w, height: lineHeight)
        let linePath = CGPath(roundedRect: lineRect, cornerWidth: lineHeight/2, cornerHeight: lineHeight/2, transform: nil)
        ctx.addPath(linePath)
        ctx.fillPath()
    }
    ctx.restoreGState()

    image.unlockFocus()
    return image
}

let sizes: [(CGFloat, String)] = [
    (1024, "icon_512x512@2x"),
    (512, "icon_512x512"),
    (512, "icon_256x256@2x"),
    (256, "icon_256x256"),
    (256, "icon_128x128@2x"),
    (128, "icon_128x128"),
    (64, "icon_32x32@2x"),
    (32, "icon_32x32"),
    (32, "icon_16x16@2x"),
    (16, "icon_16x16"),
]

let iconsetPath = "/Users/vashammas/Desktop/mdview/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

for (size, name) in sizes {
    let image = makeIcon(size: size)
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        continue
    }
    let path = "\(iconsetPath)/\(name).png"
    try! png.write(to: URL(fileURLWithPath: path))
}

print("Iconset created. Run: iconutil -c icns AppIcon.iconset -o MDView.app/Contents/Resources/AppIcon.icns")
