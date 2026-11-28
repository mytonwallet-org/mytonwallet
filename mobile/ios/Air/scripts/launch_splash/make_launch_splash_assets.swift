// Cuts the launch ribbon pieces out of AppIcon.icon and renders the static launch screen.
// Compiled together with LaunchSplashGeometry.swift by make_launch_splash_assets.sh.
//
// Colors come from the rendered icon (AppIcon.png), so the glass sheen and tints match.
// Shapes come from the icon layers: strips are the alpha of "Foreground 1", folds are the
// outlines in "Foreground 3.svg". Folds are kept whole under the strips, so when a strip
// is trimmed away the fold continues right under it.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

typealias Geometry = LaunchSplashGeometry

let iconAssets = URL(fileURLWithPath: CommandLine.arguments[1])
let catalog = URL(fileURLWithPath: CommandLine.arguments[2])
let colorSpace = CGColorSpace(name: CGColorSpace.displayP3)!
let px = Geometry.pieceImagePixelsPerUnit

func loadImage(_ name: String) -> CGImage {
    let source = CGImageSourceCreateWithURL(iconAssets.appendingPathComponent(name) as CFURL, nil)!
    return CGImageSourceCreateImageAtIndex(source, 0, nil)!
}

func writePNG(_ image: CGImage, to url: URL) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    precondition(CGImageDestinationFinalize(dest), "failed to write \(url.path)")
}

func makeContext(width: Int, height: Int) -> CGContext {
    CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
              space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

/// Draws an image in a y-down context without flipping it.
func draw(_ image: CGImage, in rect: CGRect, ctx: CGContext) {
    ctx.saveGState()
    ctx.translateBy(x: rect.minX, y: rect.maxY)
    ctx.scaleBy(x: 1, y: -1)
    ctx.draw(image, in: CGRect(origin: .zero, size: rect.size))
    ctx.restoreGState()
}

let renderedIcon: CGImage = {
    let url = catalog.appendingPathComponent("AppIcon.appiconset/AppIcon.png")
    let source = CGImageSourceCreateWithURL(url as CFURL, nil)!
    return CGImageSourceCreateImageAtIndex(source, 0, nil)!
}()
let foldOutlines = Geometry.foldOutlines
let iconRect = CGRect(x: 0, y: 0, width: 512, height: 512)

/// Strip shape mask: "Foreground 1" alpha, normalized (the layer itself is 90% opaque).
let stripMask: CGImage = {
    let strips = loadImage("Foreground 1@2x.png")
    let width = strips.width, height = strips.height
    let rgba = makeContext(width: width, height: height)
    rgba.draw(strips, in: CGRect(x: 0, y: 0, width: width, height: height))
    let src = rgba.data!.assumingMemoryBound(to: UInt8.self)
    let gray = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                         space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
    let dst = gray.data!.assumingMemoryBound(to: UInt8.self)
    var peak = 1
    for y in 0..<height { for x in 0..<width { peak = max(peak, Int(src[y * rgba.bytesPerRow + x * 4 + 3])) } }
    for y in 0..<height {
        for x in 0..<width {
            dst[y * width + x] = UInt8(min(255, Int(src[y * rgba.bytesPerRow + x * 4 + 3]) * 255 / peak))
        }
    }
    return gray.makeImage()!
}()

/// Clips a y-down context (icon units) to the strip shapes.
func clipToStrips(_ ctx: CGContext) {
    ctx.translateBy(x: 0, y: 512)
    ctx.scaleBy(x: 1, y: -1)
    ctx.clip(to: iconRect, mask: stripMask)
    ctx.scaleBy(x: 1, y: -1)
    ctx.translateBy(x: 0, y: -512)
}

/// In the rendered icon the fold ends are covered by the strips, so those pixels show the
/// strip, not the fold. Rebuild them by carrying the fold's own visible colors along the
/// fold direction (toward its middle), which keeps its cross-ribbon shading.
func restoreHiddenFold(_ ctx: CGContext, piece: Geometry.Piece) {
    let width = ctx.width, height = ctx.height
    // Strip coverage in the same piece pixel space.
    let cover = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
    cover.translateBy(x: 0, y: CGFloat(height))
    cover.scaleBy(x: px, y: -px)
    cover.translateBy(x: -piece.rect.minX, y: -piece.rect.minY)
    clipToStrips(cover)
    cover.setFillColor(gray: 1, alpha: 1)
    cover.fill(iconRect)
    // Grow the coverage a few pixels: the strip's antialiased edge (and its glow) in the
    // rendered icon reaches slightly past the layer alpha.
    let raw = cover.data!.assumingMemoryBound(to: UInt8.self)
    let grow = 4
    var covered = [UInt8](repeating: 0, count: width * height)
    for y in 0..<height {
        for x in 0..<width where raw[y * width + x] > 0 {
            for dy in -grow...grow {
                for dx in -grow...grow where dx * dx + dy * dy <= grow * grow {
                    let qx = x + dx, qy = y + dy
                    if qx >= 0, qy >= 0, qx < width, qy < height { covered[qy * width + qx] = 255 }
                }
            }
        }
    }
    let pixels = ctx.data!.assumingMemoryBound(to: UInt8.self)
    let row = ctx.bytesPerRow
    let source = [UInt8](UnsafeBufferPointer(start: pixels, count: row * height))
    let ux = piece.direction.dx, uy = piece.direction.dy
    let cx = CGFloat(width) / 2, cy = CGFloat(height) / 2

    for y in 0..<height {
        for x in 0..<width {
            let m = covered[y * width + x]
            let i = y * row + x * 4
            guard m > 0, source[i + 3] > 0 else { continue }
            let t = (CGFloat(x) - cx) * ux + (CGFloat(y) - cy) * uy
            // Walk along the fold toward its middle; near the outline that can leave the
            // fold, so fall back to walking straight to the piece center.
            func walk(_ sx: CGFloat, _ sy: CGFloat) -> Int? {
                var px = CGFloat(x), py = CGFloat(y)
                for _ in 0..<600 {
                    px += sx
                    py += sy
                    let qx = Int(px.rounded()), qy = Int(py.rounded())
                    guard qx >= 0, qy >= 0, qx < width, qy < height else { return nil }
                    let j = qy * row + qx * 4
                    if covered[qy * width + qx] == 0, source[j + 3] > 250 { return j }
                }
                return nil
            }
            let toCenter = hypot(cx - CGFloat(x), cy - CGFloat(y))
            guard let j = walk(t > 0 ? -ux : ux, t > 0 ? -uy : uy)
                    ?? walk((cx - CGFloat(x)) / toCenter, (cy - CGFloat(y)) / toCenter) else { continue }
            let weight = Int(m), keep = 255 - weight
            let alpha = Int(source[i + 3])
            for c in 0..<3 {
                let fold = Int(source[j + c]) * alpha / 255
                pixels[i + c] = UInt8((Int(source[i + c]) * keep + fold * weight) / 255)
            }
        }
    }
}

/// Edge pixels cut from the rendered icon still carry the icon's blue background, which
/// darkens the outline when drawn over the splash background. Give every semi-transparent
/// pixel the color of the nearest opaque ribbon pixel, keeping its alpha.
func bleedEdges(_ ctx: CGContext) {
    let width = ctx.width, height = ctx.height, row = ctx.bytesPerRow
    let pixels = ctx.data!.assumingMemoryBound(to: UInt8.self)
    let source = [UInt8](UnsafeBufferPointer(start: pixels, count: row * height))
    let radius = 6
    for y in 0..<height {
        for x in 0..<width {
            let i = y * row + x * 4
            let alpha = Int(source[i + 3])
            guard alpha > 0, alpha < 250 else { continue }
            var best: Int?
            var bestDistance = Int.max
            for dy in -radius...radius {
                for dx in -radius...radius {
                    let d = dx * dx + dy * dy
                    guard d < bestDistance, d <= radius * radius else { continue }
                    let qx = x + dx, qy = y + dy
                    guard qx >= 0, qy >= 0, qx < width, qy < height else { continue }
                    let j = qy * row + qx * 4
                    if source[j + 3] >= 250 { best = j; bestDistance = d }
                }
            }
            guard let j = best else { continue }
            for c in 0..<3 {
                // Premultiplied: opaque color scaled by this pixel's alpha.
                pixels[i + c] = UInt8(Int(source[j + c]) * 255 / max(Int(source[j + 3]), 1) * alpha / 255)
            }
        }
    }
}

// MARK: Pieces

var pieceImages: [CGImage] = []
var foldIndex = 0
for piece in Geometry.pieces {
    let width = Int(piece.rect.width * px), height = Int(piece.rect.height * px)
    let ctx = makeContext(width: width, height: height)
    // y-down icon units
    ctx.translateBy(x: 0, y: CGFloat(height))
    ctx.scaleBy(x: px, y: -px)
    ctx.translateBy(x: -piece.rect.minX, y: -piece.rect.minY)
    if piece.direction.dx == 0 {
        clipToStrips(ctx)
        draw(renderedIcon, in: iconRect, ctx: ctx)
    } else {
        ctx.saveGState()
        ctx.addPath(foldOutlines[foldIndex])
        ctx.clip()
        foldIndex += 1
        draw(renderedIcon, in: iconRect, ctx: ctx)
        ctx.restoreGState()
        restoreHiddenFold(ctx, piece: piece)
    }
    bleedEdges(ctx)
    let image = ctx.makeImage()!
    pieceImages.append(image)

    let set = catalog.appendingPathComponent("\(piece.imageName).imageset")
    try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
    writePNG(image, to: set.appendingPathComponent("\(piece.imageName).png"))
    try """
    {
      "images" : [
        {
          "filename" : "\(piece.imageName).png",
          "idiom" : "universal"
        }
      ],
      "info" : {
        "author" : "xcode",
        "version" : 1
      }
    }

    """.write(to: set.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

    // Measure the art along the trim direction, relative to the rect center (units).
    let data = ctx.data!.assumingMemoryBound(to: UInt8.self)
    let bytesPerRow = ctx.bytesPerRow
    var low = CGFloat.infinity, high = -CGFloat.infinity
    for y in 0..<height {
        // Bitmap memory rows run top-down, same as our y-down drawing.
        for x in 0..<width where data[y * bytesPerRow + x * 4 + 3] > 8 {
            let ux = (CGFloat(x) + 0.5) / px - piece.rect.width / 2
            let uy = (CGFloat(y) + 0.5) / px - piece.rect.height / 2
            let t = ux * piece.direction.dx + uy * piece.direction.dy
            low = min(low, t)
            high = max(high, t)
        }
    }
    print(String(format: "%@ trimStart: %.1f, trimEnd: %.1f", piece.imageName, low, high))
}

func writeImageSet(_ name: String, _ image: CGImage) throws {
    let set = catalog.appendingPathComponent("\(name).imageset")
    try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
    writePNG(image, to: set.appendingPathComponent("\(name).png"))
    try """
    {
      "images" : [
        {
          "filename" : "\(name).png",
          "idiom" : "universal"
        }
      ],
      "info" : {
        "author" : "xcode",
        "version" : 1
      }
    }

    """.write(to: set.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
}

// MARK: Trim tip

do {
    let rect = Geometry.tipRect
    let width = Int(rect.width * px), height = Int(rect.height * px)
    let ctx = makeContext(width: width, height: height)
    ctx.translateBy(x: 0, y: CGFloat(height))
    ctx.scaleBy(x: px, y: -px)
    ctx.translateBy(x: -rect.minX, y: -rect.minY)
    clipToStrips(ctx)
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.fill(rect)
    let set = catalog.appendingPathComponent("\(Geometry.tipImageName).imageset")
    try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
    writePNG(ctx.makeImage()!, to: set.appendingPathComponent("\(Geometry.tipImageName).png"))
    try """
    {
      "images" : [
        {
          "filename" : "\(Geometry.tipImageName).png",
          "idiom" : "universal"
        }
      ],
      "info" : {
        "author" : "xcode",
        "version" : 1
      }
    }

    """.write(to: set.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
}

// MARK: Launch storyboard images


// Logo: all pieces inside the icon square, outer strips stretched to the square's edges.
do {
    let size = Int(512 * px)
    let ctx = makeContext(width: size, height: size)
    ctx.interpolationQuality = .high
    ctx.translateBy(x: 0, y: CGFloat(size))
    ctx.scaleBy(x: px, y: -px)
    var layout = Geometry.Layout(screenSize: CGSize(width: 512, height: 512))
    layout.scale = 1
    for index in Geometry.drawOrder {
        let piece = Geometry.pieces[index]
        let image = pieceImages[index]
        let rect = Geometry.screenRect(of: piece, layout: layout)
        let natural = piece.rect.height
        switch piece.extends {
        case .none:
            draw(image, in: rect, ctx: ctx)
        case .down:
            draw(image, in: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: natural), ctx: ctx)
            let row = image.cropping(to: CGRect(x: 0, y: image.height - 1, width: image.width, height: 1))!
            draw(row, in: CGRect(x: rect.minX, y: rect.minY + natural, width: rect.width, height: rect.height - natural), ctx: ctx)
        case .up:
            draw(image, in: CGRect(x: rect.minX, y: rect.maxY - natural, width: rect.width, height: natural), ctx: ctx)
            let row = image.cropping(to: CGRect(x: 0, y: 0, width: image.width, height: 1))!
            draw(row, in: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - natural), ctx: ctx)
        }
    }
    try writeImageSet(Geometry.logoImageName, ctx.makeImage()!)

    let v1 = pieceImages[0]
    try writeImageSet(Geometry.stripExtensionImageName, v1.cropping(to: CGRect(x: 0, y: v1.height - 1, width: v1.width, height: 1))!)
    let v3 = pieceImages[4]
    try writeImageSet(Geometry.stripExtensionTopImageName, v3.cropping(to: CGRect(x: 0, y: 0, width: v3.width, height: 1))!)
}

// Background gradient, stretched over the screen by both the storyboard and the splash.
do {
    let ctx = makeContext(width: 4, height: 1024)
    let top = Geometry.backgroundTopP3, bottom = Geometry.backgroundBottomP3
    let gradient = CGGradient(colorsSpace: colorSpace, colors: [
        CGColor(colorSpace: colorSpace, components: [bottom.r, bottom.g, bottom.b, 1])!,
        CGColor(colorSpace: colorSpace, components: [top.r, top.g, top.b, 1])!,
    ] as CFArray, locations: [0, 1])!
    // Context y is up: bottom color at y = 0.
    ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: 1024), options: [])
    try writeImageSet(Geometry.backgroundImageName, ctx.makeImage()!)
}
print("Wrote launch splash assets to \(catalog.path)")
