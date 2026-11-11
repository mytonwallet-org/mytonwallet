import SwiftUI
import Testing
import UIKit
import WalletContext
import WalletResources
@testable import UIComponents

@Suite @MainActor
struct TradeContinueButtonTests {
    @Test(arguments: [UIUserInterfaceStyle.light, .dark])
    func `loading after a disabled draft remains legible on glass`(style: UIUserInterfaceStyle) throws {
        guard IOS_26_MODE_ENABLED, #available(iOS 26, *) else { return }
        _ = WalletResourcesBundle.bundle.load()
        let control = NativeTradeContinueButton(action: {})
        control.overrideUserInterfaceStyle = style
        control.update(configuration: .init(title: .text("Review"), isEnabled: false, showLoading: false),
                       tintColor: .systemBlue, animated: false)
        control.update(configuration: .init(title: .text("Review"), isEnabled: false, showLoading: true),
                       tintColor: .systemBlue, animated: false)
        let button = control.button
        let spinner = try #require(button.subviews.flatMap(\.subviews).compactMap { $0 as? WActivityIndicator }.first)
        #expect(!button.isEnabled)
        #expect(!button.isUserInteractionEnabled)
        #expect(spinner.tintColor.resolvedColor(with: button.traitCollection)
            == UIColor.air.secondaryLabel.resolvedColor(with: button.traitCollection))

        control.update(configuration: .init(title: .text("Review"), isEnabled: true, showLoading: false),
                       tintColor: .systemBlue, animated: false)
        control.update(configuration: .init(title: .text("Review"), isEnabled: false, showLoading: true),
                       tintColor: .systemBlue, animated: false)
        #expect(button.isEnabled)
        #expect(!button.isUserInteractionEnabled)
        #expect(spinner.tintColor.resolvedColor(with: button.traitCollection) == UIColor.white)
    }

    @Test func `review exposes button semantics and cannot activate while loading`() async throws {
        _ = WalletResourcesBundle.bundle.load()
        var activations = 0
        @MainActor func content(loading: Bool) -> TradeContinueButton {
            TradeContinueButton(configuration: .init(title: .text("Review"), isEnabled: !loading, showLoading: loading),
                                tintColor: .systemBlue, accessibilityIdentifier: "trade.test.review") {
                activations += 1
            }
        }
        let host = UIHostingController(rootView: content(loading: false))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        @MainActor func descendants(_ view: UIView) -> [UIView] { view.subviews.flatMap { [$0] + descendants($0) } }
        let button = try #require(descendants(host.view).first { $0.accessibilityIdentifier == "trade.test.review" } as? WButton)
        #expect(button.isAccessibilityElement)
        #expect(button.accessibilityLabel == "Review")
        #expect(button.accessibilityTraits.contains(.button))
        // Exercise the registered target directly; simulator taps cover UIKit's event dispatch.
        let target = try #require(button.allTargets.compactMap { $0.base as? TradeContinueButton.Coordinator }.first)
        #expect(button.actions(forTarget: target, forControlEvent: .touchUpInside) == ["pressed"])
        target.pressed()
        #expect(activations == 1)

        host.rootView = content(loading: true)
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        #expect(button.accessibilityTraits.contains(.button))
        #expect(button.accessibilityTraits.contains(.notEnabled))
        #expect(!button.isUserInteractionEnabled)
        target.pressed()
        #expect(activations == 1)
    }
}
