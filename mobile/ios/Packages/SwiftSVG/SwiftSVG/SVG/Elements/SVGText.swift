#if os(iOS) || os(tvOS)
    import UIKit
#elseif os(OSX)
    import AppKit
#endif

final class SVGText: SVGElement, SVGCharacterDataElement, Stylable {
    internal static let elementName = "text"

    internal var supportedAttributes = [String: (String) -> ()]()

    private let context: SVGRenderContext
    private var localStyle = SVGTextStyle()
    private var hasLocalFontSize = false
    private var hasLocalFontWeight = false
    private var hasLocalFill = false
    private var x = CGFloat(0)
    private var y = CGFloat(0)
    private var anchor = "start"
    private var contents = ""

    init(context: SVGRenderContext) {
        self.context = context
    }

    internal func parseX(_ value: String) {
        if let x = SVGLengthParser.number(value) {
            self.x = x
        }
    }

    internal func parseY(_ value: String) {
        if let y = SVGLengthParser.number(value) {
            self.y = y
        }
    }

    internal func parseAnchor(_ value: String) {
        anchor = value
    }

    internal func parseFill(_ value: String) {
        guard let color = UIColor(svgString: value) else {
            return
        }

        localStyle.fillColor = color
        hasLocalFill = true
    }

    internal func parseFontSize(_ value: String) {
        guard let fontSize = SVGLengthParser.number(value) else {
            return
        }

        localStyle.fontSize = fontSize
        hasLocalFontSize = true
    }

    internal func parseFontWeight(_ value: String) {
        localStyle.applyFontWeight(value)
        hasLocalFontWeight = true
    }

    internal func parseFont(_ value: String) {
        localStyle.applyFont(value)
        hasLocalFontSize = true
        hasLocalFontWeight = true
    }

    internal func appendCharacters(_ string: String) {
        contents.append(string)
    }

    internal func didProcessElement(in container: SVGContainerElement?) {
        guard let container else {
            return
        }

        let text = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return
        }

        let style = resolvedStyle()
        let font = style.font
        let layer = CATextLayer()
        layer.contentsScale = 3
        layer.alignmentMode = alignmentMode

        let containerFrame = container.containerLayer.frame.standardized
        let width = max(containerFrame.width, x * 2, style.fontSize * CGFloat(max(text.count, 1)))
        let height = max(style.fontSize * 1.25, font.ascender - font.descender + font.leading)
        let originX = frameX(width: width)
        let originY = y - font.ascender
        layer.frame = CGRect(x: originX, y: originY, width: width, height: height)
        layer.string = attributedString(text, style: style)
        layer.setNeedsDisplay()
        layer.display()

        container.containerLayer.addSublayer(layer)
    }

    private func resolvedStyle() -> SVGTextStyle {
        var style = context.textStyle
        if hasLocalFontSize {
            style.fontSize = localStyle.fontSize
        }
        if hasLocalFontWeight {
            style.fontWeight = localStyle.fontWeight
        }
        if hasLocalFill {
            style.fillColor = localStyle.fillColor
        }
        return style
    }

    private var alignmentMode: CATextLayerAlignmentMode {
        switch anchor {
        case "middle":
            return .center
        case "end":
            return .right
        default:
            return .left
        }
    }

    private var textAlignment: NSTextAlignment {
        switch anchor {
        case "middle":
            return .center
        case "end":
            return .right
        default:
            return .left
        }
    }

    private func attributedString(_ text: String, style: SVGTextStyle) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = textAlignment
        return NSAttributedString(
            string: text,
            attributes: [
                .font: style.font,
                .foregroundColor: style.fillColor,
                .paragraphStyle: paragraphStyle,
            ]
        )
    }

    private func frameX(width: CGFloat) -> CGFloat {
        switch anchor {
        case "middle":
            return x - width / 2
        case "end":
            return x - width
        default:
            return x
        }
    }
}
