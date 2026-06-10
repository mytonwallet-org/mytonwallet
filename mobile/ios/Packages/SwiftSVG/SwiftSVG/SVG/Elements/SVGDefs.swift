#if os(iOS) || os(tvOS)
    import UIKit
#elseif os(OSX)
    import AppKit
#endif

final class SVGDefs: SVGContainerElement {
    internal static let elementName = "defs"

    internal var delayedAttributes = [String: String]()
    internal var containerLayer = CALayer()
    internal var supportedAttributes = [String: (String) -> ()]()

    internal func didProcessElement(in container: SVGContainerElement?) {}
}
