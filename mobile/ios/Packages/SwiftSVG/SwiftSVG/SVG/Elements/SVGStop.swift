#if os(iOS) || os(tvOS)
    import UIKit
#elseif os(OSX)
    import AppKit
#endif

final class SVGStop: SVGElement, Stylable {
    internal static let elementName = "stop"

    internal var supportedAttributes = [String: (String) -> ()]()

    private var offset = CGFloat(0)
    private var color = UIColor.black

    internal func parseOffset(_ value: String) {
        if value.hasSuffix("%"), let percent = CGFloat(String(value.dropLast())) {
            offset = percent / 100
        } else if let number = CGFloat(lengthString: value) {
            offset = number
        }
    }

    internal func parseColor(_ value: String) {
        if let color = UIColor(svgString: value) {
            self.color = color
        }
    }

    internal func parseOpacity(_ value: String) {
        guard let opacity = CGFloat(lengthString: value) else {
            return
        }
        color = color.withAlphaComponent(opacity)
    }

    internal func didProcessElement(in container: SVGContainerElement?) {
        guard let gradient = container as? SVGLinearGradient else {
            return
        }

        gradient.addStop(SVGGradientStop(offset: offset, color: color))
    }
}
