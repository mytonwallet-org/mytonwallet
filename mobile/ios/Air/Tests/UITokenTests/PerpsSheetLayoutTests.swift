import SwiftUI
import Testing
import UIKit
import UIComponents
import WalletContext
import WalletResources
@testable import UIToken

@Suite(.serialized) @MainActor
struct PerpsSheetLayoutTests {
    init() { _ = WalletResourcesBundle.bundle.load() }

    @Test func scrollViewportExtendsBehindBarsAndReservesTheFooter() async throws {
        let review = PerpsOrderReviewVC(data: .init(token: .ETH, direction: .long, leverage: 5,
            margin: .fromDouble(100, .USD), positionSize: "$500", price: "$2 000",
            liquidationPrice: "$1 600", paymentAmount: "100 USDC", fee: "$0.05", paymentToken: .ETH), onConfirm: { _ in })
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = UINavigationController(rootViewController: review)
        window.isHidden = false
        defer { window.isHidden = true }
        review.loadViewIfNeeded()
        let layout = try #require(review.view.subviews.compactMap { $0 as? AssetDetailsView }.first)
        let footer = try #require(review.children.compactMap { $0 as? UIHostingController<PerpsOrderReviewFooter> }.first?.view)
        let content = UIView()
        content.heightAnchor.constraint(equalToConstant: 1_200).isActive = true
        layout.content.addArrangedSubview(content)
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        window.layoutIfNeeded()
        func footerFrame() -> CGRect { footer.convert(footer.bounds, to: layout) }
        let scroll = layout.scrollView
        #expect(abs(footerFrame().height - 52) < 0.5)
        #expect(scroll.frame == review.view.bounds)
        #expect(!scroll.delaysContentTouches)
        #expect(!scroll.showsVerticalScrollIndicator)
        #expect(abs(scroll.adjustedContentInset.top - layout.safeAreaInsets.top) < 0.5)
        #expect(abs(scroll.adjustedContentInset.bottom - (layout.bounds.maxY - footerFrame().minY + 12)) < 0.5)
        scroll.contentOffset.y = scroll.contentSize.height + scroll.adjustedContentInset.bottom - scroll.bounds.height
        #expect(abs(content.convert(content.bounds, to: layout).maxY - (footerFrame().minY - 28)) < 0.5)

        review.additionalSafeAreaInsets = .init(top: 18, left: 24, bottom: 45, right: 16)
        window.layoutIfNeeded()
        #expect(abs(scroll.adjustedContentInset.top - layout.safeAreaInsets.top) < 0.5)
        #expect(abs(footerFrame().maxY - (layout.bounds.maxY - max(36, layout.safeAreaInsets.bottom + 2))) < 0.5)
        #expect(content.bounds.width <= layout.safeAreaLayoutGuide.layoutFrame.width - 32 + 0.5)
        #expect(scroll.contentSize.width + scroll.adjustedContentInset.left + scroll.adjustedContentInset.right <= scroll.bounds.width + 0.5)
    }

    @Test(arguments: ["open", "increase", "reduce", "close"])
    func showFeeAboveTheConfirmationButton(operation: String) async throws {
        var data = PerpsOrderReviewDisplayData(token: .ETH, direction: .long, leverage: 5,
            margin: .fromDouble(100, .USD), positionSize: "$500", price: "$2 000",
            liquidationPrice: "$1 600", paymentAmount: "100 USDC", fee: "≈ $0.5", paymentToken: .ETH)
        let previous = PerpsPositionChange(margin: .fromDouble(75, .USD), positionSize: "$375", liquidationPrice: "$1 500")
        switch operation {
        case "increase": data.mode = .increase(previous)
        case "reduce": data.mode = .reduce(previous)
        case "close": data.mode = .close(.init(invested: "$75", currentValue: "$100", entryPrice: "$1 500"))
        default: break
        }
        data.feeRows = [
            .init(id: "exchange", title: lang("PerpsExchangeFee"), value: "≈ $0.1"),
            .init(id: "service", title: lang("PerpsServiceFee"), value: "≈ $0.2"),
            .init(id: "bridge", title: lang("PerpsBridgeFee"), value: "≈ $0.2"),
            .init(id: "total", title: lang("PerpsTotalFees"), value: "≈ $0.5"),
            .init(id: "network", title: lang("Network Fee"), value: "≈ $0.03"),
        ]
        let review = PerpsOrderReviewVC(data: data, onConfirm: { _ in })
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = UINavigationController(rootViewController: review)
        window.isHidden = false
        defer { window.isHidden = true }
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        window.layoutIfNeeded()
        let footer = try #require(review.children.compactMap { $0 as? UIHostingController<PerpsOrderReviewFooter> }.first?.view)
        #expect(abs(footer.bounds.height - 52) < 0.5)
        let content = try #require(review.children.compactMap { $0 as? UIHostingController<PerpsOrderReviewView> }.first?.view)
        #expect(content.convert(content.bounds, to: window).maxY < footer.convert(footer.bounds, to: window).minY)
        if operation == "open" {
            review.showTip(title: lang("Fee"), message: PerpsFeeSummaryRow(fee: data.fee, rows: data.feeRows, isEstimated: true).hint)
            try await Task.sleep(for: .milliseconds(400))
            window.layoutIfNeeded()
            let tip = try #require(review.presentedViewController)
            let message = try #require(descendants(tip.view).compactMap { $0 as? UITextView }.first)
            #expect(message.text.contains(lang("Network Fee")))
            #expect(message.text.contains(lang("PerpsFeeEstimateHint")))
        }
    }

    @Test func leverageDisclaimerRemainsVisibleWithoutChangingSheetHeight() async throws {
        var data = PerpsOrderDisplayData(token: .ETH, direction: .long, paymentToken: .ETH, input: .init(leverage: 2), maxLeverage: 40)
        data.price = "$2 000"
        data.leverageEstimate = .init(leverage: 2, liquidationPrice: "$1 000")
        let controller = PerpsLeverageVC(data: data) { _ in }
        let (requests, started) = AsyncStream<Void>.makeStream()
        var response: CheckedContinuation<PerpsOrderDisplayData.LeverageEstimate, Error>?
        defer { response?.resume(throwing: CancellationError()); started.finish() }
        controller.loadEstimate = { _ in
            try await withCheckedThrowingContinuation {
                response = $0
                started.yield()
            }
        }
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = UINavigationController(rootViewController: controller)
        window.isHidden = false
        defer { window.isHidden = true }
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        window.layoutIfNeeded()
        let initialHeight = controller.preferredContentSize.height
        var events = requests.makeAsyncIterator()
        let slider = try #require(descendants(controller.view).compactMap { $0 as? TradePresetSlider }.first)
        slider.setValue(40, animated: false)
        dispatch(.valueChanged, from: slider)
        _ = await events.next()
        window.layoutIfNeeded()
        #expect(slider.accessibilityValue == "40x")
        #expect(abs(controller.preferredContentSize.height - initialHeight) < 1)
        let disclaimer = try #require(descendants(controller.view).first { $0.accessibilityIdentifier == "perps.leverage.description" } as? UILabel)
        #expect(disclaimer.text == lang("$perps_leverage_disclaimer"))
        #expect(!disclaimer.isHidden)
        #expect(disclaimer.bounds.height >= disclaimer.sizeThatFits(CGSize(width: disclaimer.bounds.width, height: .greatestFiniteMagnitude)).height - 1)
        #expect(controller.metrics.isLoading)
        let metrics = try #require(descendants(controller.view).first { $0.accessibilityIdentifier == "perps.leverage.metrics" })
        let pendingImage = UIGraphicsImageRenderer(bounds: metrics.bounds).image { metrics.layer.render(in: $0.cgContext) }
        Attachment.record(try #require(pendingImage.pngData()), named: "leverage-loading.png")
        let task = controller.estimateTask
        response?.resume(returning: .init(leverage: 40, liquidationPrice: "$1 950"))
        response = nil
        await task?.value
        window.layoutIfNeeded()
        #expect(!controller.metrics.isLoading)
        #expect(abs(controller.preferredContentSize.height - initialHeight) < 1)
        let completeImage = UIGraphicsImageRenderer(bounds: metrics.bounds).image { metrics.layer.render(in: $0.cgContext) }
        Attachment.record(try #require(completeImage.pngData()), named: "leverage-complete.png")
    }

    /// A position above the market maximum keeps that leverage only while unchanged.
    @Test func leverageOutsideTheMarketRangeCannotCommit() throws {
        let data = PerpsOrderDisplayData(token: .ETH, direction: .long, paymentToken: .ETH, input: .init(leverage: 50), maxLeverage: 40)
        let controller = PerpsLeverageVC(data: data) { _ in Issue.record("An unsupported leverage must never be committed") }
        controller.loadViewIfNeeded()
        let done = try #require(descendants(controller.view).first { $0.accessibilityIdentifier == "perps.leverage.done" } as? WButton)
        #expect(!done.isEnabled)
        dispatch(.touchUpInside, from: done)
    }

    // AirTests is hostless, so UIApplication cannot dispatch UIControl target actions.
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
}
