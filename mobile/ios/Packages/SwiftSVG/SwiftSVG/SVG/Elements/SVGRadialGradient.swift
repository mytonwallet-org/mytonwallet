#if os(iOS) || os(tvOS)
    import UIKit
#elseif os(OSX)
    import AppKit
#endif

final class SVGRadialGradient: SVGGradientContainer, Transformable {
    static let elementName = "radialGradient"

    var delayedAttributes = [String: String]()
    var containerLayer = CALayer()
    var supportedAttributes = [String: (String) -> ()]()

    private let context: SVGRenderContext
    private var definition = SVGGradientDefinition()

    init(context: SVGRenderContext) {
        self.context = context
        definition.isRadial = true
        supportedAttributes = [
            "id": unown(self, SVGRadialGradient.identify),
            "cx": unown(self, SVGRadialGradient.parseX),
            "cy": unown(self, SVGRadialGradient.parseY),
            "r": unown(self, SVGRadialGradient.parseRadius),
            "gradientUnits": unown(self, SVGRadialGradient.parseUnits),
            "gradientTransform": unown(self, SVGRadialGradient.transform),
        ]
    }

    private func identify(_ value: String) { definition.id = value }
    private func parseX(_ value: String) { definition.cx = value }
    private func parseY(_ value: String) { definition.cy = value }
    private func parseRadius(_ value: String) { definition.radius = value }
    private func parseUnits(_ value: String) { definition.usesUserSpace = value == "userSpaceOnUse" }

    func addStop(_ stop: SVGGradientStop) {
        definition.stops.append(stop)
    }

    func didProcessElement(in container: SVGContainerElement?) {
        guard !definition.id.isEmpty else { return }
        definition.transform = containerLayer.affineTransform()
        context.gradients[definition.id] = definition
    }
}
