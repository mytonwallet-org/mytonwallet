import Testing
import UIKit
@testable import UIComponents

@MainActor @Suite(.serialized)
struct TradeValueLabelTests {
    @Test(arguments: [("—", "0.00012345 BTC"), ("123456.78", "0"), ("9.99", "10.20")])
    func amountCanvasDoesNotInheritTheParentResize(_ before: String, _ after: String) throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        let controller = UIViewController()
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let value = TradeValueLabel(font: .systemFont(ofSize: 17), color: .secondaryLabel)
        controller.view.addSubview(value)
        value.setText(before, animated: false)
        value.frame = CGRect(x: 24, y: 100, width: value.intrinsicContentSize.width, height: 26)
        value.layoutIfNeeded()
        let canvas = try #require(value.subviews.first)

        value.setText(after, animated: true)
        UIView.animate(withDuration: 1) {
            value.bounds.size.width = value.intrinsicContentSize.width
            value.layoutIfNeeded()
        }

        #expect(value.layer.animationKeys()?.isEmpty == false)
        #expect(canvas.layer.animationKeys()?.isEmpty != false)
        #expect(canvas.bounds.size == value.intrinsicContentSize)
        #expect(canvas.transform == .identity)
        #expect(canvas.frame.minX == 0)
        #expect(canvas.frame.midY == value.bounds.midY)
        if TradeMotion.enabled {
            #expect(canvas.subviews.contains { $0.layer.animationKeys()?.isEmpty == false })
        }
    }

    @Test func fittingLongValuesKeepsGlyphScaleBoundedDuringRapidReplacements() throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        let controller = UIViewController()
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let value = TradeValueLabel(font: .systemFont(ofSize: 17), color: .secondaryLabel)
        controller.view.addSubview(value)
        value.frame = CGRect(x: 24, y: 100, width: 50, height: 26)
        for text in ["0 BTC", "0.00012345 BTC", "—", "12345.6789 BTC", "1 BTC"] {
            value.setText(text, animated: true)
            UIView.animate(withDuration: 0.32) { value.layoutIfNeeded() }
            let canvas = try #require(value.subviews.first)
            #expect(canvas.layer.animationKeys()?.isEmpty != false)
            #expect(canvas.transform.a > 0 && canvas.transform.a <= 1)
            #expect(canvas.transform.d == canvas.transform.a)
            #expect(abs(canvas.frame.minX) < 0.0001)
            #expect(canvas.frame.width <= value.bounds.width + 0.0001)
            for glyph in canvas.subviews {
                #expect(abs(glyph.transform.a) <= 1)
                #expect(abs(glyph.transform.d) <= 1)
                #expect(abs(glyph.transform.ty) <= 17)
            }
        }
    }
}
