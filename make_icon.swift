#!/usr/bin/swift
// Draws the MDView app icon: an amber ".md" in Figtree Black on an espresso
// squircle.
// Run from the repo root: swift make_icon.swift
// Writes AppIcon.iconset, AppIcon.icns (used by install.sh) and the Xcode
// asset catalog's AppIcon.appiconset.
import AppKit
import CoreText

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

/// Apple's icon shape on its 1024 grid (824 body, 100 margin), approximated
/// by a superellipse, scaled to `s`.
func squircle(size s: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let center = s / 2, radius = s * 412 / 1024, n: CGFloat = 5
    let steps = 360
    for i in 0..<steps {
        let t = 2 * CGFloat.pi * CGFloat(i) / CGFloat(steps)
        let c = cos(t), sn = sin(t)
        let x = center + radius * copysign(pow(abs(c), 2 / n), c)
        let y = center + radius * copysign(pow(abs(sn), 2 / n), sn)
        i == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
    }
    path.closeSubpath()
    return path
}

/// Figtree (SIL Open Font License, in IconSource/) at its Black weight, 900.
func figtreeBlack(size: CGFloat) -> CTFont {
    let url = URL(fileURLWithPath: "IconSource/Figtree[wght].ttf") as CFURL
    guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url) as? [CTFontDescriptor],
          let base = descriptors.first else {
        fatalError("Can't load IconSource/Figtree[wght].ttf. Run this script from the repo root.")
    }
    let weightAxis = 0x77676874 // 'wght'
    let black = CTFontDescriptorCreateCopyWithAttributes(base, [
        kCTFontVariationAttribute: [weightAxis: 900],
    ] as CFDictionary)
    return CTFontCreateWithFontDescriptor(black, size, nil)
}

/// ".md" as a path, horizontally centered, with its baseline at `baseline`.
func textPath(size s: CGFloat, baseline: CGFloat) -> CGPath {
    let font = figtreeBlack(size: s * 330 / 1024)
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: ".md", attributes: [
        .font: font,
        .kern: -s * 6 / 1024,
    ]))
    let width = CTLineGetTypographicBounds(line, nil, nil, nil)
    let origin = CGPoint(x: (s - width) / 2, y: baseline)

    let path = CGMutablePath()
    for run in CTLineGetGlyphRuns(line) as! [CTRun] {
        let runFont = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] as! CTFont
        let count = CTRunGetGlyphCount(run)
        var glyphs = [CGGlyph](repeating: 0, count: count)
        var positions = [CGPoint](repeating: .zero, count: count)
        CTRunGetGlyphs(run, CFRange(), &glyphs)
        CTRunGetPositions(run, CFRange(), &positions)
        for (glyph, position) in zip(glyphs, positions) {
            guard let outline = CTFontCreatePathForGlyph(runFont, glyph, nil) else { continue }
            let t = CGAffineTransform(translationX: origin.x + position.x, y: origin.y + position.y)
            path.addPath(outline, transform: t)
        }
    }
    return path
}

func verticalGradient(_ ctx: CGContext, _ colors: [CGColor], _ locations: [CGFloat], top: CGFloat, bottom: CGFloat) {
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: locations)!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: top), end: CGPoint(x: 0, y: bottom), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

func makeIcon(pixels: Int) -> CGImage {
    let s = CGFloat(pixels)
    let ctx = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    let shape = squircle(size: s)
    let top = s * 924 / 1024, bottom = s * 100 / 1024

    // Drop shadow, as in Apple's macOS icon template.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 10 / 1024), blur: s * 20 / 1024, color: rgb(0x000000, 0.3))
    ctx.addPath(shape)
    ctx.setFillColor(rgb(0x1C140E))
    ctx.fillPath()
    ctx.restoreGState()

    // Espresso background.
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    verticalGradient(ctx, [rgb(0x46321F), rgb(0x1C140E)], [0, 1], top: top, bottom: bottom)
    ctx.restoreGState()

    // Amber ".md". Baseline sits 628/1024 down from the top.
    ctx.saveGState()
    let text = textPath(size: s, baseline: s * (1024 - 628) / 1024)
    ctx.addPath(text)
    ctx.clip()
    let box = text.boundingBoxOfPath
    verticalGradient(ctx, [rgb(0xFFC56A), rgb(0xEE8A25)], [0, 1], top: box.maxY, bottom: box.minY)
    ctx.restoreGState()

    // Rim: light along the top edge, a little shade along the bottom.
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    ctx.addPath(shape)
    ctx.setLineWidth(s * 12 / 1024)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    verticalGradient(
        ctx,
        [rgb(0xFFFFFF, 0.5), rgb(0xFFFFFF, 0), rgb(0x000000, 0), rgb(0x000000, 0.18)],
        [0, 0.3, 0.85, 1],
        top: top, bottom: bottom
    )
    ctx.restoreGState()

    return ctx.makeImage()!
}

let sizes: [(Int, String)] = [
    (16, "icon_16x16"), (32, "icon_16x16@2x"),
    (32, "icon_32x32"), (64, "icon_32x32@2x"),
    (128, "icon_128x128"), (256, "icon_128x128@2x"),
    (256, "icon_256x256"), (512, "icon_256x256@2x"),
    (512, "icon_512x512"), (1024, "icon_512x512@2x"),
]
let folders = ["AppIcon.iconset", "Support/Assets.xcassets/AppIcon.appiconset"]
let fm = FileManager.default
try fm.createDirectory(atPath: folders[0], withIntermediateDirectories: true)

for (pixels, name) in sizes {
    let rep = NSBitmapImageRep(cgImage: makeIcon(pixels: pixels))
    let png = rep.representation(using: .png, properties: [:])!
    for folder in folders {
        try png.write(to: URL(fileURLWithPath: "\(folder)/\(name).png"))
    }
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", folders[0], "-o", "AppIcon.icns"]
try iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "Wrote the icon set, AppIcon.icns and the asset catalog." : "iconutil failed.")
