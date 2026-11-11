import XCTest
import UIKit
import UIComponents
import WalletCore
import WalletResources
import UIToken

@MainActor
final class PerpsInfoMenuTests: XCTestCase {
    func testDismissInfoMenuDuringPresentationWhenReviewPushes() async throws {
        for operation in ["open", "increase", "reduce", "close"] {
            try await checkInfoMenuDismissal(operation: operation, isMenuPresented: false)
        }
    }

    func testDismissPresentedInfoMenuWhenReviewPushes() async throws {
        for operation in ["open", "increase", "reduce", "close"] {
            try await checkInfoMenuDismissal(operation: operation, isMenuPresented: true)
        }
    }

    private func checkInfoMenuDismissal(operation: String, isMenuPresented: Bool) async throws {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        if #available(iOS 26, *), scene == nil {
            throw XCTSkip("Native popover transitions require an app-hosted test runner")
        }
        _ = WalletResourcesBundle.bundle.load()
        var data = PerpsOrderDisplayData(token: .ETH, direction: .long, paymentToken: .ETH,
                                        input: .init(amount: "100", leverage: 5), maxLeverage: 40)
        data.status = .ready
        if operation != "open" {
            data.editingPosition = .init(id: "position", currentInput: .init(text: "75"), currentCollateral: "75",
                currentAmount: "$75", currentLeverage: 5, change: operation == "increase" ? .increase : .reduce)
            if operation == "close" { data.input.intent = .fraction(-100) }
        }
        var request: PerpsOrderRequest?
        let controller = PerpsOrderVC(data: data, onRequest: { request = $0 })
        let navigation = WNavigationController(rootViewController: controller)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.windowScene = scene
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        defer { navigation.dismiss(animated: false); window.isHidden = true }
        for _ in 0..<20 where request == nil {
            try await settle(window)
        }
        let fundingRequest = try XCTUnwrap(request)
        XCTAssertTrue(controller.update(data: data, for: fundingRequest))
        try await settle(window)
        let continueButton = try XCTUnwrap(findViews(in: controller.view).first {
            $0.accessibilityIdentifier == "perps.order.review"
        } as? UIControl)
        XCTAssertTrue(continueButton.isEnabled)
        continueButton.sendActions(for: .touchUpInside)
        XCTAssertEqual(request?.action, .review)

        let infoButton = try XCTUnwrap(findViews(in: navigation.navigationBar).first {
            $0.accessibilityIdentifier == "perps.order.info"
        } as? UIButton)
        infoButton.sendActions(for: .primaryActionTriggered)
        if isMenuPresented { try await settle(window, milliseconds: 600) }
        let menu = navigation.presentedViewController
        let overlays = window.subviews.filter { String(describing: type(of: $0)) == "ContextMenuOverlayView" }
        XCTAssertTrue(menu != nil || !overlays.isEmpty)

        let review = PerpsOrderReviewVC(data: .init(token: .ETH, direction: .long, leverage: 5,
            margin: .fromDouble(100, .USD), positionSize: "$500", price: "$2 000",
            liquidationPrice: "$1 600", paymentAmount: "100 USDC", fee: "$0.05", paymentToken: .ETH), onConfirm: { _ in })
        let response = Task { @MainActor in
            await Task.yield()
            navigation.pushViewController(review, animated: true)
        }
        await response.value
        try await waitForDismissal(in: navigation, window: window)
        XCTAssertTrue(navigation.topViewController === review)
        XCTAssertNil(navigation.presentedViewController)
        XCTAssertNil(menu?.viewIfLoaded?.window)
        XCTAssertTrue(overlays.allSatisfy { $0.superview == nil })

        infoButton.sendActions(for: .primaryActionTriggered)
        try await settle(window, milliseconds: 600)
        XCTAssertNil(navigation.presentedViewController)
        XCTAssertFalse(window.subviews.contains { String(describing: type(of: $0)) == "ContextMenuOverlayView" })

        _ = navigation.popViewController(animated: false)
        try await settle(window)
        infoButton.sendActions(for: .primaryActionTriggered)
        try await settle(window, milliseconds: 600)
        XCTAssertTrue(navigation.presentedViewController != nil
                || window.subviews.contains { String(describing: type(of: $0)) == "ContextMenuOverlayView" })
        navigation.pushViewController(review, animated: false)
        try await waitForDismissal(in: navigation, window: window)
    }

    private func waitForDismissal(in navigation: UINavigationController, window: UIWindow) async throws {
        for _ in 0..<60 where navigation.presentedViewController != nil || navigation.transitionCoordinator != nil
            || window.subviews.contains(where: { String(describing: type(of: $0)) == "ContextMenuOverlayView" }) {
            try await settle(window)
        }
        try await settle(window)
    }

    private func settle(_ window: UIWindow, milliseconds: Int = 100) async throws {
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(milliseconds))
        window.layoutIfNeeded()
    }

    private func findViews(in view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + findViews(in: $0) }
    }
}
