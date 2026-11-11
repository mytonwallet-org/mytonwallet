//
//  SVGRootElement.swift
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
 Concrete implementation that creates a container from a `<svg>` element and its attributes. This will almost always be the root container element that will container all other `SVGElement` layers
 */

struct SVGRootElement: SVGContainerElement {

    /// :nodoc:
    internal static let elementName = "svg"

    // :nodoc:
    internal var delayedAttributes = [String : String]()

    // :nodoc:
    internal var containerLayer = CALayer()

    // :nodoc:
    internal var supportedAttributes = [String : (String) -> ()]()

    private let viewport = Viewport()

    /// Attributes arrive in dictionary order, so the layout is computed once all of them are known.
    private final class Viewport {
        var width: CGFloat?
        var height: CGFloat?
        var viewBox: CGRect?
    }

    internal func parseWidth(lengthString: String) {
        viewport.width = CGFloat(lengthString: lengthString.trimWhitespace()).flatMap { $0 > 0 ? $0 : nil }
    }

    internal func parseHeight(lengthString: String) {
        viewport.height = CGFloat(lengthString: lengthString.trimWhitespace()).flatMap { $0 > 0 ? $0 : nil }
    }

    /// :nodoc:
    internal func didProcessElement(in container: SVGContainerElement?) {
        return
    }

    /// nodoc:
    internal func viewBox(coordinates: String) {
        let points = coordinates
            .components(separatedBy: CharacterSet(charactersIn: ", "))
            .compactMap { (thisString) -> Double? in
               return Double(thisString.trimWhitespace())
            }
        guard points.count == 4, points[2] > 0, points[3] > 0 else {
            return
        }
        viewport.viewBox = CGRect(x: points[0], y: points[1], width: points[2], height: points[3])
    }

    /// A layer the size of the viewport that centers the view box in it, scaled to fit as `xMidYMid meet` does.
    internal func makeViewportLayer() -> CALayer {
        let viewBox = viewport.viewBox
        let width = viewport.width ?? viewport.height.flatMap { height in viewBox.map { height * $0.width / $0.height } } ?? viewBox?.width ?? 0
        let height = viewport.height ?? viewport.width.flatMap { width in viewBox.map { width * $0.height / $0.width } } ?? viewBox?.height ?? 0
        let viewportLayer = CALayer()
        viewportLayer.frame = CGRect(x: 0, y: 0, width: width, height: height)
        let content = viewBox ?? viewportLayer.bounds
        containerLayer.bounds = content
        if content.width > 0, content.height > 0 {
            let scale = min(width / content.width, height / content.height)
            containerLayer.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
        }
        containerLayer.position = CGPoint(x: width / 2, y: height / 2)
        viewportLayer.addSublayer(containerLayer)
        return viewportLayer
    }
}
