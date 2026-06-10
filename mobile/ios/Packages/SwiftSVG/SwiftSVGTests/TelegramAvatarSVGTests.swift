import QuartzCore
import SwiftSVG
import XCTest

#if os(iOS) || os(tvOS)
import UIKit
typealias SVGTestFont = UIFont
#else
import AppKit
typealias SVGTestFont = NSFont
#endif

final class TelegramAvatarSVGTests: XCTestCase {
    func testTelegramAvatarSVGProducesGradientAndTextLayers() throws {
        let svg = """
        <svg width="320" height="320" preserveAspectRatio="none" viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg"><defs><linearGradient id="g" x1="0%" x2="0%" y1="0%" y2="100%"><stop offset="0%" stop-color="#72d5fd"/><stop offset="100%" stop-color="#2a9ef1"/></linearGradient></defs><style>text{font:600 44px -apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif,'Apple Color Emoji','Segoe UI Emoji','Segoe UI Symbol';-webkit-user-select:none;user-select:none}</style><rect width="100" height="100" fill="url(#g)"/><text text-anchor="middle" x="50" y="66" fill="#fff">N</text></svg>
        """
        let data = try XCTUnwrap(svg.data(using: .utf8))
        let expectation = expectation(description: "SVG parsed")

        _ = CALayer(SVGData: data) { layer in
            let sublayers = layer.recursiveSublayers
            XCTAssertTrue(sublayers.contains { $0 is CAGradientLayer })
            let textLayer = sublayers.compactMap { $0 as? CATextLayer }.first
            let attributedString = textLayer?.string as? NSAttributedString
            XCTAssertEqual(attributedString?.string, "N")
            let font = attributedString?.attribute(.font, at: 0, effectiveRange: nil) as? SVGTestFont
            XCTAssertNotNil(font)
            XCTAssertEqual(Double(font?.pointSize ?? 0), 44, accuracy: 0.1)
            XCTAssertFalse((font?.familyName ?? "").lowercased().contains("times"))
            XCTAssertGreaterThan(layer.renderedWhitePixelCount(), 20)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 3)
    }
}

private extension CALayer {
    var recursiveSublayers: [CALayer] {
        let directSublayers = sublayers ?? []
        return directSublayers + directSublayers.flatMap(\.recursiveSublayers)
    }

    func renderedWhitePixelCount() -> Int {
        let width = 100
        let height = 100
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return 0
        }

        render(in: context)

        return stride(from: 0, to: pixels.count, by: 4).filter { index in
            pixels[index] > 220 && pixels[index + 1] > 220 && pixels[index + 2] > 220 && pixels[index + 3] > 0
        }.count
    }
}
