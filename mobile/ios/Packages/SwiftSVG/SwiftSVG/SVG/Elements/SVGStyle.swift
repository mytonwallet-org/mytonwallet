import Foundation

final class SVGStyle: SVGElement, SVGCharacterDataElement {
    internal static let elementName = "style"

    internal var supportedAttributes = [String: (String) -> ()]()

    private let context: SVGRenderContext
    private var contents = ""

    init(context: SVGRenderContext) {
        self.context = context
    }

    internal func appendCharacters(_ string: String) {
        contents.append(string)
    }

    internal func didProcessElement(in container: SVGContainerElement?) {
        context.applyStyleSheet(contents)
    }
}
