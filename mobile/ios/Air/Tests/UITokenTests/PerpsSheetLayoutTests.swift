import Testing
import UIKit
import UIComponents
import WalletResources
@testable import UIToken

@Suite(.serialized) @MainActor
struct PerpsSheetLayoutTests {
    init() { _ = WalletResourcesBundle.bundle.load() }

    @Test func scrollViewportExtendsBehindBarsAndReservesTheFooter() throws {
        let controller = UIViewController()
        let content = UIView()
        let footer = UIView()
        content.heightAnchor.constraint(equalToConstant: 1_200).isActive = true
        footer.heightAnchor.constraint(equalToConstant: 90).isActive = true
        let layout = PerpsSheetContentView(content: content, footer: footer)
        controller.view.addSubview(layout)
        NSLayoutConstraint.activate([
            layout.topAnchor.constraint(equalTo: controller.view.topAnchor),
            layout.bottomAnchor.constraint(equalTo: controller.view.bottomAnchor),
            layout.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor),
            layout.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor),
        ])
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = UINavigationController(rootViewController: controller)
        window.isHidden = false
        defer { window.isHidden = true }
        window.layoutIfNeeded()
        let scroll = layout.scrollView
        #expect(scroll.frame == controller.view.bounds)
        #expect(!scroll.delaysContentTouches)
        #expect(!scroll.showsVerticalScrollIndicator)
        #expect(abs(scroll.adjustedContentInset.top - layout.safeAreaInsets.top) < 0.5)
        #expect(abs(scroll.adjustedContentInset.bottom - (layout.bounds.maxY - footer.frame.minY + 24)) < 0.5)
        scroll.contentOffset.y = scroll.contentSize.height + scroll.adjustedContentInset.bottom - scroll.bounds.height
        #expect(abs(content.convert(content.bounds, to: layout).maxY - (footer.frame.minY - 24)) < 0.5)

        controller.additionalSafeAreaInsets = .init(top: 18, left: 24, bottom: 45, right: 16)
        window.layoutIfNeeded()
        #expect(abs(scroll.adjustedContentInset.top - layout.safeAreaInsets.top) < 0.5)
        #expect(abs(footer.frame.maxY - (layout.bounds.maxY - max(36, layout.safeAreaInsets.bottom))) < 0.5)
        #expect(content.bounds.width <= layout.safeAreaLayoutGuide.layoutFrame.width)
        #expect(scroll.contentSize.width + scroll.adjustedContentInset.left + scroll.adjustedContentInset.right <= scroll.bounds.width + 0.5)
    }

    @Test func closePushedReviewDismissesTheEntireFlow() {
        let root = UIViewController()
        let review = PerpsOrderReviewVC(data: .init(token: .ETH, direction: .long, leverage: 5,
            margin: .fromDouble(100, .USD), positionSize: "$500", price: "$2 000",
            liquidationPrice: "$1 600", paymentAmount: "100 USDC", fee: "$0.05"), onConfirm: { _ in })
        let navigation = ReviewNavigationController(rootViewController: root)
        navigation.pushViewController(review, animated: false)
        review.closeReview()
        #expect(navigation.didDismiss)
        #expect(navigation.viewControllers.count == 2)
        #expect(navigation.topViewController === review)
    }

    @Test func leverageDisclaimerRemainsVisibleWithoutChangingSheetHeight() async throws {
        var data = PerpsOrderDisplayData(token: .ETH, direction: .long, paymentToken: .ETH, input: .init(leverage: 1))
        data.leverageOptions = [.init(value: 1, isPreset: true),
                                .init(value: 40, liquidationPrice: "$1 950", warning: "High leverage: a small move will trigger liquidation.", isPreset: true)]
        var committed: Int?
        let controller = PerpsLeverageVC(data: data) { committed = $0 }
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = UINavigationController(rootViewController: controller)
        window.isHidden = false
        defer { window.isHidden = true }
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        window.layoutIfNeeded()
        let initialHeight = controller.preferredContentSize.height
        let slider = try #require(descendants(controller.view).compactMap { $0 as? TradePresetSlider }.first)
        slider.setValue(40, animated: false)
        dispatch(.valueChanged, from: slider)
        try await Task.sleep(for: .milliseconds(100))
        window.layoutIfNeeded()
        #expect(abs(controller.preferredContentSize.height - initialHeight) < 1)
        let disclaimer = try #require(descendants(controller.view).first { $0.accessibilityIdentifier == "perps.leverage.disclaimer" } as? UILabel)
        #expect(!disclaimer.isHidden)
        #expect(disclaimer.bounds.height >= disclaimer.sizeThatFits(CGSize(width: disclaimer.bounds.width, height: .greatestFiniteMagnitude)).height - 1)
        let info = try #require(descendants(controller.view).first { $0.accessibilityIdentifier == "perps.leverage.liquidationInfo" })
        let icon = try #require(descendants(controller.view).first { $0.accessibilityIdentifier == "perps.leverage.liquidationInfoIcon" })
        #expect(info.bounds.height >= 44)
        #expect(icon.bounds.size == CGSize(width: 14, height: 14))
        #expect(slider.accessibilityValue == "40x")
        let done = try #require(descendants(controller.view).first { $0.accessibilityIdentifier == "perps.leverage.done" } as? WButton)
        dispatch(.touchUpInside, from: done)
        #expect(committed == 40)
    }

    @Test func leverageUsesPreparedLiquidationPriceAndFetchesOnlyChangedOptions() async throws {
        var data = PerpsOrderDisplayData(token: .ETH, direction: .long, paymentToken: .ETH, input: .init(leverage: 2))
        data.leverageOptions = [.init(value: 2, liquidationPrice: "$1 000"), .init(value: 5)]
        let controller = PerpsLeverageVC(data: data) { _ in }
        var requested: [Int] = []
        controller.loadEstimate = { leverage in
            requested.append(leverage)
            return [.init(value: leverage, liquidationPrice: "$1 600")]
        }
        controller.loadViewIfNeeded()
        let value = try #require(descendants(controller.view).first { $0.accessibilityIdentifier == "perps.leverage.liquidationPrice" } as? UILabel)
        #expect(value.text == "$1 000")
        try await Task.sleep(for: .milliseconds(300))
        #expect(requested.isEmpty)
        let slider = try #require(descendants(controller.view).compactMap { $0 as? TradePresetSlider }.first)
        slider.setValue(5, animated: false)
        dispatch(.valueChanged, from: slider)
        try await Task.sleep(for: .milliseconds(300))
        #expect(requested == [5])
        #expect(value.text == "$1 600")
        slider.setValue(2, animated: false)
        dispatch(.valueChanged, from: slider)
        #expect(value.text == "$1 000")
        try await Task.sleep(for: .milliseconds(300))
        #expect(requested == [5])
    }

    @Test func returningToCancelledLeveragePreviewStartsANewRequest() async throws {
        var data = PerpsOrderDisplayData(token: .ETH, direction: .long, paymentToken: .ETH, input: .init(leverage: 2))
        data.leverageOptions = [.init(value: 2, liquidationPrice: "$1 000"), .init(value: 5)]
        let controller = PerpsLeverageVC(data: data) { _ in }
        var requested: [Int] = []
        controller.loadEstimate = { leverage in
            requested.append(leverage)
            return [.init(value: leverage, liquidationPrice: "$1 600")]
        }
        controller.loadViewIfNeeded()
        let slider = try #require(descendants(controller.view).compactMap { $0 as? TradePresetSlider }.first)
        slider.setValue(5, animated: false)
        dispatch(.valueChanged, from: slider)
        try await Task.sleep(for: .milliseconds(50))
        slider.setValue(2, animated: false)
        dispatch(.valueChanged, from: slider)
        slider.setValue(5, animated: false)
        dispatch(.valueChanged, from: slider)
        try await Task.sleep(for: .milliseconds(300))
        #expect(requested == [5])
        let value = try #require(descendants(controller.view).first { $0.accessibilityIdentifier == "perps.leverage.liquidationPrice" } as? UILabel)
        #expect(value.text == "$1 600")
    }

    @Test func emptyLeverageOptionsCannotCommit() {
        let data = PerpsOrderDisplayData(token: .ETH, direction: .long, paymentToken: .ETH)
        let controller = PerpsLeverageVC(data: data) { _ in Issue.record("An unsupported leverage must never be committed") }
        controller.loadViewIfNeeded()
        let done = descendants(controller.view).first { $0.accessibilityIdentifier == "perps.leverage.done" } as? WButton
        #expect(done?.isEnabled == false)
    }

    @Test(arguments: ["", "0", "3", "41", "99999999999999999999999999999999999999999999999999"])
    func unsupportedManualLeverageCannotCommit(_ text: String) throws {
        var data = PerpsOrderDisplayData(token: .ETH, direction: .long, paymentToken: .ETH)
        data.leverageOptions = [.init(value: 2), .init(value: 40)]
        let controller = PerpsLeverageVC(data: data) { _ in Issue.record("Invalid leverage committed") }
        controller.loadViewIfNeeded()
        let field = try #require(descendants(controller.view).compactMap { $0 as? WAmountInput }.first)
        let done = try #require(descendants(controller.view).first { $0.accessibilityIdentifier == "perps.leverage.done" } as? WButton)
        field.text = text
        dispatch(.editingChanged, from: field)
        #expect(!done.isEnabled)
        dispatch(.touchUpInside, from: done)
    }

    @Test func manualLeverageRemainsDraftAndSliderRestoresInvalidInput() throws {
        var data = PerpsOrderDisplayData(token: .ETH, direction: .long, paymentToken: .ETH)
        data.leverageOptions = [.init(value: 2), .init(value: 5), .init(value: 10)]
        var committed: [Int] = []
        let controller = PerpsLeverageVC(data: data) { committed.append($0) }
        controller.loadViewIfNeeded()
        let field = try #require(descendants(controller.view).compactMap { $0 as? WAmountInput }.first)
        let slider = try #require(descendants(controller.view).compactMap { $0 as? TradePresetSlider }.first)
        let done = try #require(descendants(controller.view).first { $0.accessibilityIdentifier == "perps.leverage.done" } as? WButton)
        field.text = "5"
        dispatch(.editingChanged, from: field)
        #expect(committed.isEmpty)
        #expect(slider.selectedValue == 5)
        field.text = "0"
        dispatch(.editingChanged, from: field)
        #expect(!done.isEnabled)
        dispatch(.editingDidBegin, from: slider)
        #expect(field.amountValueOrNil == 5)
        #expect(done.isEnabled)
        dispatch(.touchUpInside, from: done)
        #expect(committed == [5])
    }

    private func dispatch(_ event: UIControl.Event, from control: UIControl) {
        for target in control.allTargets {
            for action in control.actions(forTarget: target, forControlEvent: event) ?? [] {
                (target as? NSObject)?.perform(NSSelectorFromString(action), with: control)
            }
        }
    }

    private func descendants(_ view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }

    private final class ReviewNavigationController: UINavigationController {
        private(set) var didDismiss = false

        override func dismiss(animated: Bool, completion: (() -> Void)? = nil) {
            didDismiss = true
            completion?()
        }
    }
}
