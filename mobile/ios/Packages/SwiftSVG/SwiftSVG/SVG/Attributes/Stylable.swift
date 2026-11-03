//
//  Stylable.swift
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



import Foundation

/**
 A protocol that describes instances whose attributes that can be set vis a css style string. A default implementation is supplied that parses the style string and applies the attributes using the `SVGelement`'s `supportedAttributes`.
 */
public protocol Stylable { }

extension Stylable where Self : SVGElement {
  /**
   The curried function to be used for the `SVGElement`'s default implementation. This dictionary is meant to be used in the `SVGParserSupportedElements` instance
   - parameter Key: The SVG string value of the attribute
   - parameter Value: A curried function to use to implement the SVG attribute
   */
  var styleAttributes: [String : (String) -> ()] {
    return [
      "style": self.style,
    ]
  }
}

extension Stylable where Self : SVGGroup {
  /**
   The curried function to be used for the `SVGElement`'s default implementation. This dictionary is meant to be used in the `SVGParserSupportedElements` instance
   - parameter Key: The SVG string value of the attribute
   - parameter Value: A curried function to use to implement the SVG attribute
   */
  var styleAttributes: [String : (String) -> ()] {
    return [
      "style": unown(self, SVGGroup.style),
    ]
  }
}

/**
 Default implementation for the style attribute on `SVGElement`s
 */
extension Stylable where Self : SVGElement {

    /**
     Parses and applies the css-style `style` string to this `SVGElement`'s `SVGLayer`
     */
    func style(_ styleString: String) {
        for declaration in styleString.split(separator: ";") {
            let parts = declaration.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let name = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            supportedAttributes[name]?(value)
        }
    }
}
