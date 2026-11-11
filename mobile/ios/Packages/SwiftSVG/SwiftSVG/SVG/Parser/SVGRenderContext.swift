#if os(iOS) || os(tvOS)
    import UIKit
    typealias SVGPlatformFont = UIFont
#elseif os(OSX)
    import AppKit
    typealias SVGPlatformFont = NSFont
#endif
import ImageIO

final class SVGRenderContext {
    var gradients = [String: SVGGradientDefinition]()
    var textStyle = SVGTextStyle()
    /// Shapes painted with `url(#id)`, keyed by layer so a later color replaces the reference.
    var shapeFills = [ObjectIdentifier: (CAShapeLayer, String)]()
    var shapeStrokes = [ObjectIdentifier: (CAShapeLayer, String)]()
    private var styleRules = [StyleRule]()
    private var embeddedImages = [String: SVGEmbeddedImage?]()
    private var gradientPixels = CGFloat(0)

    /// Embedded bitmaps decode once per document, and only so many distinct ones.
    private static let maximumEmbeddedImages = 16
    /// Gradient layers rasterize before compositing; this bounds their pixels across a document.
    private static let gradientPixelBudget = CGFloat(16_000_000)

    private struct StyleRule {
        var selectors: [String]
        var declarations: [(String, String)]
    }

    /// Handles `fill` and `stroke` values that are either a color or a paint server reference.
    func paintHandler(for layer: CAShapeLayer, isStroke: Bool, color: @escaping (String) -> Void) -> (String) -> Void {
        return { [weak self] value in
            self?.setPaint(value, on: layer, isStroke: isStroke, color: color)
        }
    }

    func setPaint(_ value: String, on layer: CAShapeLayer, isStroke: Bool, color: (String) -> Void) {
        let key = ObjectIdentifier(layer)
        guard let id = value.svgURLReferenceId else {
            if isStroke {
                shapeStrokes[key] = nil
            } else {
                shapeFills[key] = nil
            }
            color(value)
            return
        }
        // An opaque placeholder carries `fill-opacity` or `stroke-opacity` until the paint resolves.
        if isStroke {
            shapeStrokes[key] = (layer, id)
            layer.strokeColor = UIColor.black.cgColor
        } else {
            shapeFills[key] = (layer, id)
            layer.fillColor = UIColor.black.cgColor
        }
    }

    /// Decodes a PNG or JPEG `data:` URL of at most 16 megapixels into a bitmap of at most 512 pixels a side.
    func embeddedImage(_ href: String) -> SVGEmbeddedImage? {
        if let image = embeddedImages[href] {
            return image
        }
        guard embeddedImages.count < Self.maximumEmbeddedImages else {
            return nil
        }
        let image = Self.decodeEmbeddedImage(href)
        embeddedImages[href] = .some(image)
        return image
    }

    private static func decodeEmbeddedImage(_ href: String) -> SVGEmbeddedImage? {
        let href = href.trimmingCharacters(in: .whitespacesAndNewlines)
        guard href.hasPrefix("data:"), let comma = href.firstIndex(of: ","), href[..<comma].hasSuffix(";base64"),
              let data = Data(base64Encoded: String(href[href.index(after: comma)...]), options: .ignoreUnknownCharacters),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source) as String?, type == "public.png" || type == "public.jpeg",
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width * height <= 16_777_216,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: 512,
                  kCGImageSourceShouldCacheImmediately: true,
              ] as CFDictionary) else {
            return nil
        }
        return SVGEmbeddedImage(image: image, size: CGSize(width: width, height: height))
    }

    /// Paints the shape's fill, or its stroke outline, with a gradient drawn in a masked sublayer at `pixelsPerUnit`.
    func applyGradient(_ id: String, to shape: CAShapeLayer, isStroke: Bool, pixelsPerUnit: CGFloat) -> Bool {
        guard let definition = gradients[id] else {
            return false
        }
        guard var path = shape.path else {
            return true
        }
        if isStroke {
            path = path.copy(strokingWithWidth: shape.lineWidth, lineCap: shape.lineCap.cgLineCap,
                             lineJoin: shape.lineJoin.cgLineJoin, miterLimit: shape.miterLimit)
        }
        let bounds = path.boundingBoxOfPath
        // Each gradient gets at most 512 pixels a side, and less once the document budget runs low.
        let remainingPixels = max(Self.gradientPixelBudget - gradientPixels, 4096)
        let scale = min(pixelsPerUnit, 512 / max(bounds.width, bounds.height),
                        (remainingPixels / (bounds.width * bounds.height)).squareRoot())
        guard bounds.width > 0, bounds.height > 0, let gradient = definition.makeLayer(frame: bounds, scale: scale) else {
            return true
        }
        gradientPixels += bounds.width * bounds.height * scale * scale
        let mask = CAShapeLayer()
        mask.frame = CGRect(origin: .zero, size: bounds.size)
        var translation = CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY)
        mask.path = path.copy(using: &translation)
        mask.fillRule = isStroke ? .nonZero : shape.fillRule
        gradient.mask = mask
        if isStroke {
            gradient.opacity = Float(shape.strokeColor?.alpha ?? 1)
            shape.strokeColor = nil
            shape.addSublayer(gradient)
        } else {
            gradient.opacity = Float(shape.fillColor?.alpha ?? 1)
            shape.fillColor = UIColor.clear.cgColor
            liftStroke(of: shape)
            shape.insertSublayer(gradient, at: 0)
        }
        return true
    }

    /// Sublayers draw over the shape's own stroke, so a stroke moves above a fill drawn in a sublayer. Strokes resolve first.
    func liftStroke(of shape: CAShapeLayer) {
        guard let strokeColor = shape.strokeColor, shape.lineWidth > 0 else {
            return
        }
        let stroke = CAShapeLayer()
        stroke.path = shape.path
        stroke.fillColor = nil
        stroke.strokeColor = strokeColor
        stroke.lineWidth = shape.lineWidth
        stroke.lineCap = shape.lineCap
        stroke.lineJoin = shape.lineJoin
        stroke.miterLimit = shape.miterLimit
        shape.strokeColor = nil
        shape.addSublayer(stroke)
    }

    func applyStyleSheet(_ styleSheet: String) {
        let withoutComments = styleSheet.replacingOccurrences(of: "(?s)/\\*.*?\\*/", with: "", options: [.regularExpression])
        guard let regex = try? NSRegularExpression(pattern: "([^{}]+)\\{([^}]*)\\}") else {
            return
        }
        let range = NSRange(withoutComments.startIndex..<withoutComments.endIndex, in: withoutComments)
        for match in regex.matches(in: withoutComments, range: range) {
            guard let selectorRange = Range(match.range(at: 1), in: withoutComments),
                  let blockRange = Range(match.range(at: 2), in: withoutComments) else {
                continue
            }
            let selectors = withoutComments[selectorRange].split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            let declarations = Self.declarations(in: String(withoutComments[blockRange]))
            styleRules.append(StyleRule(selectors: selectors, declarations: declarations))
            if selectors.contains("text") {
                for (name, value) in declarations {
                    textStyle.apply(name: name, value: value)
                }
            }
        }
    }

    /// Declarations of every matching rule, from the least to the most specific and in source order among equals.
    func styleDeclarations(forElement name: String, classes: [String], id: String?) -> [(String, String)] {
        var matches = [(specificity: Int, order: Int, declarations: [(String, String)])]()
        for (order, rule) in styleRules.enumerated() {
            let specificity = rule.selectors.compactMap { Self.specificity(of: $0, name: name, classes: classes, id: id) }.max()
            if let specificity {
                matches.append((specificity, order, rule.declarations))
            }
        }
        return matches
            .sorted { ($0.specificity, $0.order) < ($1.specificity, $1.order) }
            .flatMap(\.declarations)
    }

    static func declarations(in block: String) -> [(String, String)] {
        block.split(separator: ";").compactMap { declaration in
            let parts = declaration.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else {
                return nil
            }
            let value = parts[1].replacingOccurrences(of: "!important", with: "")
            return (parts[0].trimmingCharacters(in: .whitespacesAndNewlines), value.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    /// Matches compound selectors such as `path`, `.a`, `#b`, `path.a.b` and `*`; other selectors never match.
    private static func specificity(of selector: String, name: String, classes: [String], id: String?) -> Int? {
        guard !selector.isEmpty, !selector.contains(where: { $0.isWhitespace || ">+~[:".contains($0) }) else {
            return nil
        }
        var specificity = 0
        var remainder = Substring(selector)
        let tagEnd = remainder.firstIndex(where: { $0 == "." || $0 == "#" }) ?? remainder.endIndex
        let tag = remainder[..<tagEnd]
        if !tag.isEmpty, tag != "*" {
            guard tag == name else {
                return nil
            }
            specificity += 1
        }
        remainder = remainder[tagEnd...]
        while let marker = remainder.first {
            remainder = remainder.dropFirst()
            let end = remainder.firstIndex(where: { $0 == "." || $0 == "#" }) ?? remainder.endIndex
            let value = String(remainder[..<end])
            remainder = remainder[end...]
            if marker == "." {
                guard classes.contains(value) else {
                    return nil
                }
                specificity += 10
            } else {
                guard value == id else {
                    return nil
                }
                specificity += 100
            }
        }
        return specificity
    }
}

struct SVGEmbeddedImage {
    var image: CGImage
    /// The size the encoded image declares, which a decoded thumbnail may be smaller than.
    var size: CGSize
}

struct SVGGradientStop {
    var offset: CGFloat
    var color: UIColor
}

struct SVGGradientDefinition {
    var id = ""
    var x1 = "0%"
    var y1 = "0%"
    var x2 = "100%"
    var y2 = "0%"
    var stops = [SVGGradientStop]()
    var usesUserSpace = false
    var isRadial = false
    var cx = "50%"
    var cy = "50%"
    var radius = "50%"
    var transform = CGAffineTransform.identity

    func makeLayer(frame: CGRect, scale: CGFloat) -> CALayer? {
        guard !stops.isEmpty else {
            return nil
        }
        let layer = SVGGradientLayer()
        layer.definition = self
        layer.frame = frame
        layer.contentsScale = scale
        layer.setNeedsDisplay()
        layer.displayIfNeeded()
        return layer
    }
}

/// Draws a gradient in the coordinates its definition uses, so `gradientTransform` applies exactly.
private final class SVGGradientLayer: CALayer {
    var definition = SVGGradientDefinition()

    override func draw(in context: CGContext) {
        let colors = definition.stops.map { $0.color.cgColor } as CFArray
        // Offsets never decrease; a smaller one takes the value of the largest before it.
        var offsets = [CGFloat]()
        for stop in definition.stops {
            offsets.append(min(1, max(stop.offset, offsets.last ?? 0, 0)))
        }
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors,
                                        locations: offsets) else { return }
        context.saveGState()
        defer { context.restoreGState() }
        if definition.usesUserSpace {
            context.translateBy(x: -frame.minX, y: -frame.minY)
        } else {
            context.scaleBy(x: bounds.width, y: bounds.height)
        }
        context.concatenate(definition.transform)
        let axis = definition.usesUserSpace ? max(bounds.width, bounds.height) : 1
        func coordinate(_ value: String) -> CGFloat {
            if value.hasSuffix("%") {
                return (SVGLengthParser.number(value) ?? 0) / 100 * axis
            }
            return SVGLengthParser.number(value) ?? 0
        }
        let options: CGGradientDrawingOptions = [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        if definition.isRadial {
            let center = CGPoint(x: coordinate(definition.cx), y: coordinate(definition.cy))
            context.drawRadialGradient(gradient, startCenter: center, startRadius: 0,
                                       endCenter: center, endRadius: coordinate(definition.radius), options: options)
        } else {
            context.drawLinearGradient(gradient, start: CGPoint(x: coordinate(definition.x1), y: coordinate(definition.y1)),
                                       end: CGPoint(x: coordinate(definition.x2), y: coordinate(definition.y2)), options: options)
        }
    }
}

struct SVGTextStyle {
    var fontSize = CGFloat(16)
    var fontWeight = SVGPlatformFont.Weight.regular
    var fillColor = UIColor.black

    mutating func apply(name: String, value: String) {
        switch name {
        case "font":
            applyFont(value)
        case "font-size":
            if let fontSize = SVGLengthParser.number(value) {
                self.fontSize = fontSize
            }
        case "font-weight":
            applyFontWeight(value)
        case "fill":
            if let color = UIColor(svgString: value) {
                fillColor = color
            }
        default:
            break
        }
    }

    mutating func applyFont(_ value: String) {
        for token in value.split(separator: " ") {
            let tokenString = String(token)
            if let fontSize = SVGLengthParser.number(tokenString), tokenString.contains("px") {
                self.fontSize = fontSize
            } else {
                applyFontWeight(tokenString)
            }
        }
    }

    mutating func applyFontWeight(_ value: String) {
        switch value {
        case "bold":
            fontWeight = .bold
        case "normal":
            fontWeight = .regular
        default:
            guard let weight = Int(value) else {
                return
            }
            if weight >= 700 {
                fontWeight = .bold
            } else if weight >= 600 {
                fontWeight = .semibold
            } else if weight >= 500 {
                fontWeight = .medium
            } else {
                fontWeight = .regular
            }
        }
    }

    var font: SVGPlatformFont {
        SVGPlatformFont.systemFont(ofSize: fontSize, weight: fontWeight)
    }
}

enum SVGLengthParser {
    static func number(_ value: String) -> CGFloat? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let number = CGFloat(lengthString: trimmed) {
            return number
        }

        if trimmed.hasSuffix("%") {
            return CGFloat(String(trimmed.dropLast()))
        }

        return nil
    }

    static func unitCoordinate(_ value: String, axisLength: CGFloat) -> CGFloat? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("%"), let number = CGFloat(String(trimmed.dropLast())) {
            return number / 100
        }

        guard let number = CGFloat(lengthString: trimmed) else {
            return nil
        }

        if number >= 0, number <= 1 {
            return number
        }

        guard axisLength > 0 else {
            return nil
        }

        return number / axisLength
    }
}

private extension CAShapeLayerLineCap {
    var cgLineCap: CGLineCap {
        switch self {
        case .round: return .round
        case .square: return .square
        default: return .butt
        }
    }
}

private extension CAShapeLayerLineJoin {
    var cgLineJoin: CGLineJoin {
        switch self {
        case .round: return .round
        case .bevel: return .bevel
        default: return .miter
        }
    }
}
