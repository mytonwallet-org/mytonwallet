//
//  NSXMLSVGParser.swift
//  SwiftSVG
//
//
//  Copyright (c) 2017 Michael Choe
//  http://www.github.com/mchoe
//  http://www.straussmade.com/
//  http://www.twitter.com/_mchoe
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.



#if os(iOS) || os(tvOS)
    import UIKit
#elseif os(OSX)
    import AppKit
#endif



/**
 `NSXMLSVGParser` conforms to `SVGParser`
 */
extension NSXMLSVGParser: SVGParser { }

/**
 Concrete implementation of `SVGParser` that uses Foundation's `XMLParser` to parse a given SVG file.
 */

open class NSXMLSVGParser: XMLParser, XMLParserDelegate {

    /// Rasterizers can parse on one thread to avoid reading partially committed layers.
    public var shouldParsePathsAsynchronously = true
    private var rootFill: String?

    /**
     Error type used when a fatal error has occured
     */
    enum SVGParserError {
        case invalidSVG
        case invalidURL
    }

    /// :nodoc:
    fileprivate var asyncParseCount: Int = 0

    /// :nodoc:
    fileprivate var didDispatchAllElements = true

    /// :nodoc:
    fileprivate var elementStack = Stack<SVGElement>()

    /// :nodoc:
    public var completionBlock: ((SVGLayer) -> ())?

    /// :nodoc:
    public var supportedElements: SVGParserSupportedElements? = nil

    /// The `SVGLayer` that will contain all of the SVG's sublayers
    open var containerLayer = SVGLayer()

    /// :nodoc:
    let asyncCountQueue = DispatchQueue(label: "com.straussmade.swiftsvg.asyncCountQueue.serial", qos: .userInteractive)

    /// :nodoc:
    private init() {
        super.init(data: Data())
    }

    /**
     Convenience initializer that can initalize an `NSXMLSVGParser` using a local or remote `URL`
     - parameter SVGURL: The URL of the SVG.
     - parameter supportedElements: Optional `SVGParserSupportedElements` struct that restrict the elements and attributes that this parser can parse.If no value is provided, all supported attributes will be used.
     - parameter completion: Optional completion block that will be executed after all elements and attribites have been parsed.
     */
    public convenience init(SVGURL: URL, supportedElements: SVGParserSupportedElements? = nil, completion: ((SVGLayer) -> ())? = nil) {

        do {
            let urlData = try Data(contentsOf: SVGURL)
            self.init(SVGData: urlData, supportedElements: supportedElements, completion: completion)
        } catch {
            self.init()
            print("Couldn't get data from URL")
        }
    }

    /**
     Initializer that can initalize an `NSXMLSVGParser` using SVG `Data`
     - parameter SVGURL: The URL of the SVG.
     - parameter supportedElements: Optional `SVGParserSupportedElements` struct that restricts the elements and attributes that this parser can parse. If no value is provided, all supported attributes will be used.
     - parameter completion: Optional completion block that will be executed after all elements and attribites have been parsed.
     */
    public required init(SVGData: Data, supportedElements: SVGParserSupportedElements? = SVGParserSupportedElements.allSupportedElements, completion: ((SVGLayer) -> ())? = nil) {
        super.init(data: SVGData)
        self.delegate = self
        self.supportedElements = supportedElements
        self.completionBlock = completion
    }

    /**
     Starts parsing the SVG document
     */
    public func startParsing() {
        self.asyncCountQueue.sync {
            self.didDispatchAllElements = false
        }
        self.parse()
    }

    /// An element as written in the document. The tree renders once the document ends, so references resolve in either direction.
    final class Node {
        let name: String
        let attributes: [String: String]
        var children = [Node]()
        var text = ""

        init(name: String, attributes: [String: String], children: [Node] = []) {
            self.name = name
            self.attributes = attributes
            self.children = children
        }

        var allText: String {
            children.reduce(text) { $0 + $1.allText }
        }
    }

    private var openNodes = [Node]()
    private var rootNode: Node?
    private var nodesById = [String: Node]()
    private var referenceDepth = 0
    private var renderedElementCount = 0
    private var renderDepth = 0
    private var singleClipPaths = [ObjectIdentifier: (path: CGPath, rule: CGPathFillRule)?]()
    /// Clips that may avoid a mask layer, decided once inheritance and paints are known.
    private var pendingClips = [(layer: CALayer, clip: Node)]()

    /// Bound the recursion that rendering and layer drawing use, and the elements that references can multiply.
    private static let maximumDepth = 256
    private static let maximumReferenceDepth = 16
    private static let maximumRenderedElements = 50_000

    /// Elements that render only through a reference: `clip-path`, `mask`, `fill` or `<use>`.
    private static let referencedOnly: Set<String> = ["clipPath", "mask", "pattern", "symbol", "marker", "filter", "style"]

    open func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String]) {
        let node = Node(name: elementName, attributes: attributeDict)
        if let parent = openNodes.last {
            if openNodes.count < Self.maximumDepth {
                parent.children.append(node)
            }
        } else if rootNode == nil {
            rootNode = node
        }
        if let id = attributeDict["id"], nodesById[id] == nil {
            nodesById[id] = node
        }
        openNodes.append(node)
    }

    open func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        _ = openNodes.popLast()
    }

    open func parser(_ parser: XMLParser, foundCharacters string: String) {
        openNodes.last?.text.append(string)
    }

    open func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        openNodes.last?.text.append(String(decoding: CDATABlock, as: UTF8.self))
    }

    /**
     The `XMLParserDelegate` method called when the parser has finished parsing the SVG document. The document tree is rendered here, after which all supported elements and attributes are guaranteed to be dispatched, but there's no guarantee that all elements have finished parsing.

     - SeeAlso: `CanManageAsychronousParsing` `finishedProcessing(shapeLayer:)`
     - SeeAlso: `XMLParserDelegate` (`parserDidEndDocument(_:)`)[https://developer.apple.com/documentation/foundation/xmlparserdelegate/1418172-parserdidenddocument]
     */
    public func parserDidEndDocument(_ parser: XMLParser) {
        if let rootNode {
            applyStyleSheets(in: rootNode)
            render(rootNode)
        }

        self.asyncCountQueue.sync {
            self.didDispatchAllElements = true
        }
        if self.asyncParseCount <= 0 {
            DispatchQueue.main.safeAsync {
                Self.applyPaintOpacity(in: self.containerLayer)
                self.resolvePaints()
                Self.foldOpacityIntoFill(in: self.containerLayer)
                self.completionBlock?(self.containerLayer)
                self.completionBlock = nil
            }
        }
    }

    private func applyStyleSheets(in node: Node) {
        if node.name == "style" {
            supportedElements?.renderContext.applyStyleSheet(node.allText)
        }
        node.children.forEach(applyStyleSheets)
    }

    /// Renders a node with its own presentation, or with one the caller resolved for it.
    private func render(_ node: Node, presentation resolved: [(String, String)]? = nil) {
        guard !Self.referencedOnly.contains(node.name), renderedElementCount < Self.maximumRenderedElements,
              renderDepth < Self.maximumDepth else {
            return
        }
        renderedElementCount += 1
        renderDepth += 1
        defer { renderDepth -= 1 }
        let presentation = resolved ?? presentation(of: node)
        guard presentation.last(where: { $0.0 == "display" })?.1 != "none" else {
            return
        }
        if node.name == "use" {
            renderUse(node, presentation: presentation)
            return
        }
        guard let element = startElement(node, presentation: presentation) else {
            node.children.forEach { render($0) }
            return
        }
        if let characterData = element as? SVGCharacterDataElement {
            characterData.appendCharacters(node.allText)
        }
        node.children.forEach { render($0) }
        endElement(element, presentation: presentation)
    }

    /// The value of each property that wins the cascade of attributes, style sheet rules and the inline `style`.
    private func presentation(of node: Node) -> [(String, String)] {
        var declarations = node.attributes
            .filter { $0.key != "style" && $0.key != "class" }
            .sorted { $0.key < $1.key }
            .map { ($0.key, $0.value) }
        if let context = supportedElements?.renderContext {
            let classes = node.attributes["class"]?.split(whereSeparator: { $0.isWhitespace }).map(String.init) ?? []
            declarations += context.styleDeclarations(forElement: node.name, classes: classes, id: node.attributes["id"])
        }
        if let style = node.attributes["style"] {
            declarations += SVGRenderContext.declarations(in: style)
        }
        var winners = [String: Int]()
        for (index, declaration) in declarations.enumerated() {
            winners[declaration.0] = index
        }
        return declarations.enumerated().filter { winners[$0.element.0] == $0.offset }.map(\.element)
    }

    private func startElement(_ node: Node, presentation: [(String, String)]) -> SVGElement? {
        guard let elementType = self.supportedElements?.tags[node.name] else {
            print("\(node.name) is unsupported. For a complete list of supported elements, see the `allSupportElements` variable in the `SVGParserSupportedElements` struct. Click through on the `elementName` variable name to see the SVG tag name.")
            return nil
        }

        let svgElement = elementType()
        if node.name == "svg", elementStack.last == nil {
            rootFill = node.attributes["fill"]
        } else if svgElement is SVGShapeElement, let rootFill {
            svgElement.supportedAttributes["fill"]?(rootFill)
        }

        if var asyncElement = svgElement as? ParsesAsynchronously {
            asyncElement.shouldParseAsynchronously = shouldParsePathsAsynchronously
            if shouldParsePathsAsynchronously {
                self.asyncCountQueue.sync {
                    self.asyncParseCount += 1
                    asyncElement.asyncParseManager = self
                }
            }
        }

        for (name, value) in presentation where name != "d" {
            svgElement.supportedAttributes[name]?(value)
        }
        if let shape = svgElement as? SVGShapeElement {
            shape.svgLayer.svgExplicitAttributes = Set(presentation.map(\.0))
        }
        // Path completion clears its attribute handlers; apply all styling first.
        if let path = presentation.last(where: { $0.0 == "d" })?.1 {
            svgElement.supportedAttributes["d"]?(path)
        }

        self.elementStack.push(svgElement)
        return svgElement
    }

    /**
     Pops the element and adds its layer to the enclosing container, which every valid SVG has (at a minimum, a `SVGRootElement` instance). A finished `SVGShapeElement` grows the parser's `containerLayer` bounding box; a finished `<svg>` element adds its viewport to the enclosing container or to the parser's `containerLayer`.
     */
    private func endElement(_ svgElement: SVGElement, presentation: [(String, String)]) {
        _ = self.elementStack.pop()

        if let rootItem = svgElement as? SVGRootElement {
            let viewport = rootItem.makeViewportLayer()
            let parent = (self.elementStack.last as? SVGContainerElement)?.containerLayer ?? self.containerLayer
            DispatchQueue.main.safeAsync {
                parent.addSublayer(viewport)
            }
            return
        }

        guard let containerElement = self.elementStack.last as? SVGContainerElement else {
            return
        }

        svgElement.didProcessElement(in: containerElement)
        applyMasks(presentation, to: svgElement)

        if let lastShapeElement = svgElement as? SVGShapeElement {
            self.resizeContainerBoundingBox(lastShapeElement.boundingBox)
        }
    }

    /// `<use>` renders as a group with the use element's own presentation, holding the referenced element offset by `x` and `y`.
    private func renderUse(_ node: Node, presentation: [(String, String)]) {
        guard referenceDepth < Self.maximumReferenceDepth,
              let id = (node.attributes["xlink:href"] ?? node.attributes["href"]).flatMap({ $0.hasPrefix("#") ? String($0.dropFirst()) : nil }),
              let referenced = nodesById[id] else {
            return
        }
        var wrapper = presentation.filter { !["id", "href", "xlink:href", "x", "y", "width", "height", "transform"].contains($0.0) }
        let x = node.attributes["x"].flatMap { CGFloat(lengthString: $0) } ?? 0
        let y = node.attributes["y"].flatMap { CGFloat(lengthString: $0) } ?? 0
        let transform = presentation.last(where: { $0.0 == "transform" })?.1
        if transform != nil || x != 0 || y != 0 {
            wrapper.append(("transform", (transform.map { $0 + " " } ?? "") + "translate(\(x) \(y))"))
        }
        let content = referenced.name == "symbol" ? Node(name: "g", attributes: [:], children: referenced.children) : referenced
        referenceDepth += 1
        render(Node(name: "g", attributes: [:], children: [content]), presentation: wrapper)
        referenceDepth -= 1
    }

    /// Renders the children of a referenced element into a detached group layer with the element's presentation, such as a
    /// clip path's transform.
    private func makeLayer(from node: Node) -> CALayer? {
        guard referenceDepth < Self.maximumReferenceDepth else {
            return nil
        }
        let ownPresentation = presentation(of: node).filter { !["id", "clip-path", "mask", "filter", "display"].contains($0.0) }
        guard let group = startElement(Node(name: "g", attributes: [:]), presentation: ownPresentation) as? SVGContainerElement else {
            return nil
        }
        referenceDepth += 1
        node.children.forEach { render($0) }
        referenceDepth -= 1
        _ = elementStack.pop()
        group.didProcessElement(in: nil)
        Self.applyPaintOpacity(in: group.containerLayer)
        return group.containerLayer
    }

    private func applyMasks(_ presentation: [(String, String)], to svgElement: SVGElement) {
        let layer: CALayer
        if let shape = svgElement as? SVGShapeElement {
            layer = shape.svgLayer
        } else if let container = svgElement as? SVGContainerElement {
            layer = container.containerLayer
        } else {
            return
        }
        func referencedNode(_ property: String, _ name: String) -> Node? {
            guard let id = presentation.last(where: { $0.0 == property })?.1.svgURLReferenceId,
                  let node = nodesById[id], node.name == name else {
                return nil
            }
            return node
        }
        let clipNode = referencedNode("clip-path", "clipPath")
        // A luminance mask of white content, which is how masks are usually drawn, matches an alpha mask.
        let mask = referencedNode("mask", "mask").flatMap(makeLayer)
        if mask == nil, let clipNode, singleClipPath(clipNode) != nil {
            pendingClips.append((layer, clipNode))
            return applyFilter()
        }
        let clip = clipNode.flatMap(makeClipLayer)
        if let mask {
            mask.mask = clip
            layer.mask = mask
        } else if let clip {
            layer.mask = clip
        }
        applyFilter()

        func applyFilter() {
            if let filter = referencedNode("filter", "filter") {
                applyDropShadow(filter, to: layer)
            }
        }
    }

    /// The clip path's shapes, all opaque, since clipping uses the geometry alone.
    private func makeClipLayer(_ node: Node) -> CALayer? {
        let clip = makeLayer(from: node)
        clip?.applyOnSublayers(ofType: CAShapeLayer.self) { shape in
            shape.fillColor = UIColor.black.cgColor
            shape.strokeColor = nil
            shape.opacity = 1
        }
        return clip
    }

    /// Applies clips that waited for inherited strokes and paints: without a mask layer where that keeps the result the same.
    private func resolveClips(context: SVGRenderContext) {
        let clips = pendingClips
        pendingClips.removeAll()
        for (layer, node) in clips {
            guard let clipPath = singleClipPath(node), !clip(layer, to: clipPath, context: context) else {
                continue
            }
            layer.mask = makeClipLayer(node)
        }
    }

    /// The path of a clip path made of one untransformed shape, which most clip paths are.
    private func singleClipPath(_ node: Node) -> (path: CGPath, rule: CGPathFillRule)? {
        if let cached = singleClipPaths[ObjectIdentifier(node)] {
            return cached
        }
        var result: (path: CGPath, rule: CGPathFillRule)?
        if let layer = makeLayer(from: node) {
            let shapes: [CAShapeLayer] = layer.sublayers(in: layer)
            let layers: [CALayer] = layer.sublayers(in: layer)
            if shapes.count == 1, let path = shapes[0].path,
               (layers + [layer]).allSatisfy({ $0.affineTransform().isIdentity }) {
                result = (path, shapes[0].fillRule == .evenOdd ? .evenOdd : .winding)
            }
        }
        singleClipPaths[ObjectIdentifier(node)] = .some(result)
        return result
    }

    /// Clips without a mask layer, each of which costs an offscreen pass when the layers render: a rectangle that contains
    /// the content changes nothing, and a shape filled with a color and no stroke takes the intersection with the clip path.
    /// A gradient or pattern fill keeps the shape's own geometry, since its extent derives from it.
    private func clip(_ layer: CALayer, to clip: (path: CGPath, rule: CGPathFillRule), context: SVGRenderContext) -> Bool {
        var clipRect = CGRect.zero
        if clip.path.isRect(&clipRect), let bounds = Self.contentBounds(of: layer), clipRect.contains(bounds) {
            return true
        }
        guard let shape = layer as? CAShapeLayer, let path = shape.path, shape.strokeColor == nil,
              context.shapeFills[ObjectIdentifier(shape)] == nil, #available(iOS 16, macOS 13, tvOS 16, *) else {
            return false
        }
        let rule: CGPathFillRule = shape.fillRule == .evenOdd ? .evenOdd : .winding
        shape.path = path.normalized(using: rule).intersection(clip.path.normalized(using: clip.rule))
        shape.fillRule = .nonZero
        return true
    }

    /// What the layer draws, in its own coordinates, or `nil` when that is unknown.
    private static func contentBounds(of layer: CALayer) -> CGRect? {
        var bounds = CGRect.null
        if let shape = layer as? CAShapeLayer, let path = shape.path {
            let strokeOutset = shape.strokeColor == nil ? 0 : shape.lineWidth / 2
            bounds = path.boundingBoxOfPath.insetBy(dx: -strokeOutset, dy: -strokeOutset)
        } else if layer.contents != nil || layer.mask != nil || layer.shadowOpacity > 0 {
            return nil
        }
        for sublayer in layer.sublayers ?? [] {
            // Layers built from SVG elements have empty bounds at the origin, so their transform applies about it.
            guard sublayer.bounds.isEmpty, sublayer.position == .zero, let sublayerBounds = contentBounds(of: sublayer) else {
                return nil
            }
            bounds = bounds.union(sublayerBounds.applying(sublayer.affineTransform()))
        }
        return bounds
    }

    /// Applies the drop shadow that design tools export as offset, blur and color matrix primitives. Other filters are skipped.
    private func applyDropShadow(_ filter: Node, to layer: CALayer) {
        let primitives = filter.children
        guard let offset = primitives.first(where: { $0.name == "feOffset" }),
              let blur = primitives.first(where: { $0.name == "feGaussianBlur" }),
              primitives.contains(where: { $0.name == "feBlend" && $0.attributes["in"] == "SourceGraphic" }),
              !primitives.contains(where: { $0.attributes["operator"] == "arithmetic" }) else {
            return
        }
        func number(_ node: Node, _ name: String) -> CGFloat {
            node.attributes[name].flatMap { CGFloat(lengthString: $0) } ?? 0
        }
        // The last color matrix sets the shadow color: red, green and blue offsets and the alpha factor.
        let values = primitives.last(where: { $0.name == "feColorMatrix" && $0.attributes["in"] == nil })?
            .attributes["values"]?.split(whereSeparator: { $0 == "," || $0.isWhitespace }).compactMap { CGFloat(String($0)) } ?? []
        guard values.count == 20 else {
            return
        }
        layer.shadowColor = UIColor(red: values[4], green: values[9], blue: values[14], alpha: 1).cgColor
        layer.shadowOpacity = Float(values[18])
        layer.shadowOffset = CGSize(width: number(offset, "dx"), height: number(offset, "dy"))
        layer.shadowRadius = number(blur, "stdDeviation")
    }

    /// Multiplies each shape's colors by its `fill-opacity` and `stroke-opacity` once.
    private static func applyPaintOpacity(in layer: CALayer) {
        for sublayer in layer.sublayers ?? [] {
            if let shape = sublayer as? CAShapeLayer {
                if let opacity = shape.svgFillOpacity, let fillColor = shape.fillColor {
                    shape.fillColor = fillColor.copy(alpha: fillColor.alpha * opacity)
                }
                if let opacity = shape.svgStrokeOpacity, let strokeColor = shape.strokeColor {
                    shape.strokeColor = strokeColor.copy(alpha: strokeColor.alpha * opacity)
                }
                shape.svgFillOpacity = nil
                shape.svgStrokeOpacity = nil
            }
            applyPaintOpacity(in: sublayer)
        }
    }

    /// Layer opacity renders each shape in a pass of its own. A shape that only fills a color is the same with the alpha in its fill.
    private static func foldOpacityIntoFill(in layer: CALayer) {
        for sublayer in layer.sublayers ?? [] {
            if let shape = sublayer as? CAShapeLayer, shape.opacity < 1, shape.strokeColor == nil, shape.sublayers == nil,
               shape.mask == nil, shape.shadowOpacity == 0, let fillColor = shape.fillColor {
                shape.fillColor = fillColor.copy(alpha: fillColor.alpha * CGFloat(shape.opacity))
                shape.opacity = 1
            }
            foldOpacityIntoFill(in: sublayer)
        }
        layer.mask.map(foldOpacityIntoFill)
    }

    /// Fills shapes that reference a gradient or a pattern. Pattern content can reference further paints.
    private func resolvePaints() {
        guard let context = supportedElements?.renderContext else {
            return
        }
        var rounds = 0
        while !(context.shapeFills.isEmpty && context.shapeStrokes.isEmpty && pendingClips.isEmpty), rounds < 4 {
            rounds += 1
            resolveClips(context: context)
            let fills = context.shapeFills
            let strokes = context.shapeStrokes
            context.shapeFills.removeAll()
            context.shapeStrokes.removeAll()
            for (shape, id) in strokes.values
            where !context.applyGradient(id, to: shape, isStroke: true, pixelsPerUnit: gradientPixelsPerUnit(for: shape)) {
                shape.strokeColor = nil
            }
            for (shape, id) in fills.values {
                if context.applyGradient(id, to: shape, isStroke: false, pixelsPerUnit: gradientPixelsPerUnit(for: shape)) {
                    continue
                }
                if let pattern = nodesById[id], pattern.name == "pattern" {
                    applyPattern(pattern, to: shape, context: context)
                } else {
                    // A missing paint server paints nothing.
                    shape.fillColor = nil
                }
            }
        }
    }

    /// Pixels per unit of the shape when the viewport renders 512 pixels across, twice what icons use. Shapes outside the
    /// viewport's tree, such as mask content, get 2.
    private func gradientPixelsPerUnit(for shape: CALayer) -> CGFloat {
        guard let viewport = containerLayer.sublayers?.first, viewport.bounds.width > 0, viewport.bounds.height > 0 else {
            return 2
        }
        var ancestor = shape.superlayer
        while let layer = ancestor, layer !== viewport {
            ancestor = layer.superlayer
        }
        guard ancestor != nil else {
            return 2
        }
        let unit = shape.convert(CGRect(x: 0, y: 0, width: 1, height: 1), to: viewport)
        return max(unit.width, unit.height) * 512 / max(viewport.bounds.width, viewport.bounds.height)
    }

    /// Draws one tile of the pattern over the shape's bounding box, which covers the single-tile patterns that design tools export.
    private func applyPattern(_ pattern: Node, to shape: CAShapeLayer, context: SVGRenderContext) {
        guard let path = shape.path else {
            return
        }
        let bounds = path.boundingBoxOfPath
        guard bounds.width > 0, bounds.height > 0, let content = makeLayer(from: pattern) else {
            return
        }
        func number(_ name: String, _ fallback: CGFloat) -> CGFloat {
            pattern.attributes[name].flatMap { SVGLengthParser.number($0) } ?? fallback
        }
        let usesUserSpace = pattern.attributes["patternUnits"] == "userSpaceOnUse"
        var tile = CGRect(x: number("x", 0), y: number("y", 0), width: number("width", 0), height: number("height", 0))
        if !usesUserSpace {
            tile = CGRect(x: bounds.minX + tile.minX * bounds.width, y: bounds.minY + tile.minY * bounds.height,
                          width: tile.width * bounds.width, height: tile.height * bounds.height)
        }
        var transform = CGAffineTransform(translationX: tile.minX, y: tile.minY)
        if pattern.attributes["patternContentUnits"] == "objectBoundingBox" {
            transform = CGAffineTransform(scaleX: bounds.width, y: bounds.height).concatenating(transform)
        }
        content.setAffineTransform(transform)

        let holder = CALayer()
        holder.addSublayer(content)
        let mask = CAShapeLayer()
        mask.path = path
        mask.fillRule = shape.fillRule
        holder.mask = mask
        holder.opacity = Float(shape.fillColor?.alpha ?? 1)
        shape.fillColor = UIColor.clear.cgColor
        context.liftStroke(of: shape)
        shape.insertSublayer(holder, at: 0)
    }

    /**
     The `XMLParserDelegate` method called when the parser has reached a fatal error in parsing. Parsing is stopped if an error is reached and you may want to check that your SVG file passes validation.
     - SeeAlso: `XMLParserDelegate` (`parser(_:parseErrorOccurred:)`)[https://developer.apple.com/documentation/foundation/xmlparserdelegate/1412379-parser]
     - SeeAlso: (SVG Validator)[https://validator.w3.org/]
     */
    public func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        print("Parse Error: \(parseError)")
        let code = (parseError as NSError).code
        switch code {
        case 76:
            print("Invalid XML: \(SVGParserError.invalidSVG)")
        default:
            break
        }
    }


}

extension NSXMLSVGParser {

    /**
     Method that resizes the container bounding box that fits all the subpaths.
     */
    func resizeContainerBoundingBox(_ boundingBox: CGRect?) {
        guard let thisBoundingBox = boundingBox else {
            return
        }
        self.containerLayer.boundingBox = self.containerLayer.boundingBox.union(thisBoundingBox)
    }
}

/**
 `NSXMLSVGParser` conforms to the protocol `CanManageAsychronousParsing` that uses a simple reference count to see if there are any pending asynchronous tasks that have been dispatched and are still being processed. Once the element has finished processing, the asynchronous elements calls the delegate callback `func finishedProcessing(shapeLayer:)` and the delegate will decrement the count.
 */
extension NSXMLSVGParser: CanManageAsychronousParsing {

    /**
     The `CanManageAsychronousParsing` callback called when an `ParsesAsynchronously` element has finished parsing
     */
    func finishedProcessing(_ shapeLayer: CAShapeLayer) {

        self.asyncCountQueue.sync {
            self.asyncParseCount -= 1
        }

        self.resizeContainerBoundingBox(shapeLayer.path?.boundingBox)

        guard self.asyncParseCount <= 0 && self.didDispatchAllElements else {
            return
        }
        DispatchQueue.main.safeAsync {
            Self.applyPaintOpacity(in: self.containerLayer)
            self.resolvePaints()
            Self.foldOpacityIntoFill(in: self.containerLayer)
            self.completionBlock?(self.containerLayer)
            self.completionBlock = nil
        }
    }

}
