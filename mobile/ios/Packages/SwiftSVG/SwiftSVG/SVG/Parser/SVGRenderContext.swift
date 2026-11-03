#if os(iOS) || os(tvOS)
    import UIKit
    typealias SVGPlatformFont = UIFont
#elseif os(OSX)
    import AppKit
    typealias SVGPlatformFont = NSFont
#endif

final class SVGRenderContext {
    var gradients = [String: SVGGradientDefinition]()
    var textStyle = SVGTextStyle()
    var shapeFills = [(CAShapeLayer, String)]()
    private var styleSheets = [String]()

    func applyClasses(_ classes: String, to element: SVGElement) {
        for styleSheet in styleSheets {
            for name in classes.split(whereSeparator: { $0.isWhitespace }) {
                guard let block = declarationBlock(for: "." + name, in: styleSheet) else { continue }
                for declaration in block.split(separator: ";") {
                    let parts = declaration.split(separator: ":", maxSplits: 1)
                    guard parts.count == 2 else { continue }
                    let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                    let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                    element.supportedAttributes[key]?(value)
                }
            }
        }
    }

    func applyShapeFills() {
        for (shape, id) in shapeFills {
            guard let path = shape.path else { continue }
            let bounds = path.boundingBoxOfPath
            guard bounds.width > 0, bounds.height > 0,
                  let gradient = gradients[id]?.makeLayer(frame: bounds) else { continue }
            let mask = CAShapeLayer()
            mask.frame = CGRect(origin: .zero, size: bounds.size)
            var translation = CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY)
            mask.path = path.copy(using: &translation)
            mask.fillRule = shape.fillRule
            gradient.mask = mask
            gradient.opacity = Float(shape.fillColor?.alpha ?? 1)
            shape.fillColor = UIColor.clear.cgColor
            shape.addSublayer(gradient)
        }
        shapeFills.removeAll()
    }

    func applyStyleSheet(_ styleSheet: String) {
        styleSheets.append(styleSheet)
        guard let textBlock = declarationBlock(for: "text", in: styleSheet) else {
            return
        }

        for declaration in textBlock.split(separator: ";") {
            let parts = declaration.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else {
                continue
            }

            let name = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            textStyle.apply(name: name, value: value)
        }
    }

    private func declarationBlock(for selector: String, in styleSheet: String) -> String? {
        let pattern = "\(NSRegularExpression.escapedPattern(for: selector))\\s*\\{([^}]*)\\}"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }

        let range = NSRange(styleSheet.startIndex..<styleSheet.endIndex, in: styleSheet)
        guard let match = regex.firstMatch(in: styleSheet, range: range),
              let blockRange = Range(match.range(at: 1), in: styleSheet) else {
            return nil
        }

        return String(styleSheet[blockRange])
    }
}

struct SVGGradientStop {
    var offset: CGFloat
    var color: UIColor
}

struct SVGGradientDefinition {
    var id = ""
    var x1 = "0%"
    var y1 = "0%"
    var x2 = "0%"
    var y2 = "100%"
    var stops = [SVGGradientStop]()
    var usesUserSpace = false
    var isRadial = false
    var cx = "50%"
    var cy = "50%"
    var radius = "50%"
    var transform = CGAffineTransform.identity

    func makeLayer(frame: CGRect) -> CALayer? {
        guard !stops.isEmpty else {
            return nil
        }
        if isRadial {
            let layer = SVGRadialGradientLayer()
            layer.definition = self
            layer.frame = frame
            layer.contentsScale = min(2, 512 / max(frame.width, frame.height))
            layer.setNeedsDisplay()
            layer.displayIfNeeded()
            return layer
        }

        let layer = CAGradientLayer()
        layer.frame = frame
        layer.colors = stops.map { $0.color.cgColor }
        layer.locations = stops.map { NSNumber(value: Double($0.offset)) }
        if usesUserSpace {
            layer.startPoint = CGPoint(
                x: ((SVGLengthParser.number(x1) ?? 0) - frame.minX) / frame.width,
                y: ((SVGLengthParser.number(y1) ?? 0) - frame.minY) / frame.height
            )
            layer.endPoint = CGPoint(
                x: ((SVGLengthParser.number(x2) ?? 0) - frame.minX) / frame.width,
                y: ((SVGLengthParser.number(y2) ?? 0) - frame.minY) / frame.height
            )
            return layer
        }
        layer.startPoint = CGPoint(
            x: SVGLengthParser.unitCoordinate(x1, axisLength: frame.width) ?? 0,
            y: SVGLengthParser.unitCoordinate(y1, axisLength: frame.height) ?? 0
        )
        layer.endPoint = CGPoint(
            x: SVGLengthParser.unitCoordinate(x2, axisLength: frame.width) ?? 0,
            y: SVGLengthParser.unitCoordinate(y2, axisLength: frame.height) ?? 1
        )
        return layer
    }
}

private final class SVGRadialGradientLayer: CALayer {
    var definition = SVGGradientDefinition()

    override func draw(in context: CGContext) {
        let colors = definition.stops.map { $0.color.cgColor } as CFArray
        let locations = definition.stops.map { $0.offset }
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors,
                                        locations: locations) else { return }
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
        let center = CGPoint(x: coordinate(definition.cx), y: coordinate(definition.cy))
        context.drawRadialGradient(gradient, startCenter: center, startRadius: 0,
                                   endCenter: center, endRadius: coordinate(definition.radius),
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
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
