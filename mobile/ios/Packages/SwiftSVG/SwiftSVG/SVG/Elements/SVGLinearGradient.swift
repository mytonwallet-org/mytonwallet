#if os(iOS) || os(tvOS)
    import UIKit
#elseif os(OSX)
    import AppKit
#endif

protocol SVGGradientContainer: SVGContainerElement {
    func addStop(_ stop: SVGGradientStop)
}

final class SVGLinearGradient: SVGGradientContainer, Transformable {
    internal static let elementName = "linearGradient"

    internal var delayedAttributes = [String: String]()
    internal var containerLayer = CALayer()
    internal var supportedAttributes = [String: (String) -> ()]()

    private let context: SVGRenderContext
    private var definition = SVGGradientDefinition()

    init(context: SVGRenderContext) {
        self.context = context
    }

    internal func identify(identifier: String) {
        definition.id = identifier
    }

    internal func parseX1(_ value: String) {
        definition.x1 = value
    }

    internal func parseY1(_ value: String) {
        definition.y1 = value
    }

    internal func parseX2(_ value: String) {
        definition.x2 = value
    }

    internal func parseY2(_ value: String) {
        definition.y2 = value
    }

    internal func parseUnits(_ value: String) {
        definition.usesUserSpace = value == "userSpaceOnUse"
    }

    internal func addStop(_ stop: SVGGradientStop) {
        definition.stops.append(stop)
    }

    internal func didProcessElement(in container: SVGContainerElement?) {
        guard !definition.id.isEmpty else {
            return
        }

        definition.transform = containerLayer.affineTransform()
        context.gradients[definition.id] = definition
    }
}
