import UIKit
import Testing
import UIComponents
import WalletResources
@testable import UISwap

@Suite("Buy/Sell native layout", .serialized)
struct TokenTradeLayoutTests {
    @MainActor @Test(arguments: [false, true])
    func `warning text is fully laid out before its entrance`(alreadyLaidOut: Bool) async throws {
        _ = WalletResourcesBundle.bundle.load()
        let content = TokenTradeNoticeView(frame: .zero)
        let notice = TokenTradePresenceView(content)
        let host = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 810))
        window.rootViewController = host
        host.view.addSubview(notice)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        if alreadyLaidOut {
            TokenTradeMotion.place(notice, in: CGRect(x: 16, y: 290, width: 370, height: 77))
        }
        host.view.layoutIfNeeded()
        content.update(.init(title: "The exchange rate is 12% below market value!",
                             message: "We do not recommend to perform an exchange, try to specify a lower amount.",
                             isWarning: true), animated: true)
        notice.setVisible(true, animated: true)
        let height = content.sizeThatFits(CGSize(width: 370, height: CGFloat.greatestFiniteMagnitude)).height
        UIView.animate(withDuration: 0.32) {
            TokenTradeMotion.place(notice, in: CGRect(x: 16, y: 290, width: 370, height: height))
            host.view.layoutIfNeeded()
        }
        try await Task.sleep(for: .milliseconds(30))
        let replacement = try #require(content.subviews.compactMap { $0 as? BlurReplaceView }.first)
        let label = try #require(replacement.contentView as? UILabel)
        #expect(label.bounds.width == 334)
        expectStableGeometry(label, through: replacement)
    }

    @MainActor @Test func `loading spinner starts at its trailing position during the button transition`() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let content = TokenTradeContinueButton(action: {})
        let presence = TokenTradePresenceView(content)
        let host = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 810))
        window.rootViewController = host
        host.view.addSubview(presence)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        TokenTradeMotion.place(presence, in: CGRect(x: 24, y: 470, width: 354, height: 52))
        content.update(configuration: .init(title: .text("Sell GRAM"), isEnabled: false, showLoading: false,
                                             resetsLoadingAppearance: true), tintColor: .systemRed, diagnostics: nil, animated: false)
        host.view.layoutIfNeeded()
        content.update(configuration: .init(title: .text("Sell GRAM"), isEnabled: false, showLoading: true),
                       tintColor: .systemRed, diagnostics: nil, animated: true)
        presence.setVisible(true, animated: true)
        UIView.animate(withDuration: 0.32) { host.view.layoutIfNeeded() }
        try await Task.sleep(for: .milliseconds(30))
        let spinner = try #require(content.button.subviews.compactMap { $0 as? WActivityIndicator }.first)
        #expect(spinner.center == CGPoint(x: 326, y: 26))
        expectStableGeometry(spinner, through: content.button)
        #expect(spinner.layer.animation(forKey: "rotationAnimation") != nil)
    }

    @MainActor @Test func `new notices enter at their final frame during a parent animation`() {
        let parent = UIView(frame: CGRect(x: 0, y: 0, width: 402, height: 810))
        let notice = TokenTradePresenceView(UILabel())
        parent.addSubview(notice)
        let destination = CGRect(x: 16, y: 290, width: 370, height: 77)
        UIView.animate(withDuration: 0.32) {
            notice.setVisible(true, animated: true)
            TokenTradeMotion.place(notice, in: destination)
        }
        #expect(notice.frame == destination)
        #expect(notice.layer.animation(forKey: "position") == nil)
        #expect(notice.layer.animation(forKey: "bounds") == nil)
        #expect(notice.content.bounds.size == destination.size)
    }

    @Test func `quote warnings leave the method row and keypad anchored`() {
        let size = CGSize(width: 402, height: 810)
        let empty = TokenTradeLayout(size: size, bottomSafeArea: 34, navigationBarSpace: 64,
                                     feeHeight: 0, impactHeight: 0, hintHeight: 0)
        let quoted = TokenTradeLayout(size: size, bottomSafeArea: 34, navigationBarSpace: 64,
                                      feeHeight: 17, impactHeight: 77, hintHeight: 0)
        #expect(empty.method == quoted.method)
        #expect(empty.controls == quoted.controls)
        #expect(quoted.amountTop + 26 + quoted.maximumAmountHeight + 18 <= quoted.footerTop)
    }

    @Test(arguments: [CGFloat(480), 650, 810])
    func `large notices remain scrollable above a fixed keypad`(height: CGFloat) {
        let layout = TokenTradeLayout(size: CGSize(width: 320, height: height), bottomSafeArea: 0,
                                      navigationBarSpace: 64, feeHeight: 34, impactHeight: 210, hintHeight: 140)
        #expect(layout.footerTop >= layout.amountTop + 26 + layout.maximumAmountHeight + 18)
        #expect(layout.method.minY >= layout.card.maxY + 16)
        #expect(layout.contentHeight >= layout.method.maxY + 16)
        #expect(layout.controls.maxY == height)
        #expect(layout.keypadHeight >= 176)
    }

    @Test func `side navigation reclaims the top inset`() {
        let layout = TokenTradeLayout(size: CGSize(width: 600, height: 500), bottomSafeArea: 0,
                                      navigationBarSpace: 0, feeHeight: 17, impactHeight: 77, hintHeight: 0)
        #expect(layout.amountTop >= 16)
        #expect(layout.amountTop < 64)
        #expect(layout.footerTop >= layout.amountTop + 26 + layout.maximumAmountHeight + 18)
    }
}

@MainActor private func expectStableGeometry(_ view: UIView, through ancestor: UIView) {
    var current: UIView? = view
    while let node = current {
        for key in node.layer.animationKeys() ?? [] {
            if let animation = node.layer.animation(forKey: key) as? CABasicAnimation,
               let path = animation.keyPath {
                #expect(!path.hasPrefix("bounds") && !path.hasPrefix("position"),
                        "Unexpected geometry animation on \(type(of: node)): \(path), from \(String(describing: animation.fromValue))")
            }
        }
        if node === ancestor { break }
        current = node.superview
    }
}
