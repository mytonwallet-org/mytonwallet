#if os(iOS) || os(tvOS)
    import UIKit
#elseif os(OSX)
    import AppKit
#endif

/// An `<image>` whose PNG or JPEG bitmap is embedded as a `data:` URL. Other URLs are never loaded.
final class SVGImage: SVGContainerElement {

    internal static let elementName = "image"

    internal var delayedAttributes = [String : String]()

    internal var containerLayer = CALayer()

    internal var supportedAttributes = [String : (String) -> ()]()

    /// Decodes embedded bitmaps within the document's limits.
    internal var renderContext: SVGRenderContext?

    private var frame = CGRect.zero
    private var href: String?
    private var aspectRatio = "xMidYMid"

    internal func parseX(_ value: String) {
        frame.origin.x = CGFloat(lengthString: value) ?? 0
    }

    internal func parseY(_ value: String) {
        frame.origin.y = CGFloat(lengthString: value) ?? 0
    }

    internal func parseWidth(_ value: String) {
        frame.size.width = CGFloat(lengthString: value) ?? 0
    }

    internal func parseHeight(_ value: String) {
        frame.size.height = CGFloat(lengthString: value) ?? 0
    }

    internal func parseHref(_ value: String) {
        href = value
    }

    internal func parseAspectRatio(_ value: String) {
        aspectRatio = value
    }

    internal func parseOpacity(_ value: String) {
        if let opacity = Float(value) {
            containerLayer.opacity = opacity
        }
    }

    internal func didProcessElement(in container: SVGContainerElement?) {
        guard let container, let href, let embedded = renderContext?.embeddedImage(href) else {
            return
        }
        let imageLayer = CALayer()
        imageLayer.frame = CGRect(
            origin: frame.origin,
            size: CGSize(width: frame.width > 0 ? frame.width : embedded.size.width,
                         height: frame.height > 0 ? frame.height : embedded.size.height)
        )
        imageLayer.contents = embedded.image
        imageLayer.contentsGravity = aspectRatio.hasPrefix("none") ? .resize
            : aspectRatio.contains("slice") ? .resizeAspectFill : .resizeAspect
        imageLayer.masksToBounds = true
        containerLayer.addSublayer(imageLayer)
        container.containerLayer.addSublayer(containerLayer)
    }
}
