import Dependencies
import GRDB
import UIKit
import XCTest
import UIComponents
import WalletContext
@testable import WalletCore
import WalletResources
@testable import AirAsFramework

@MainActor
final class RootPromotionOverlayTests: XCTestCase {
    private static let walletSecondTabIds: [AppTabId] = [.market, .wallet, .futures, .agent, .explore, .settings]
    private static let banner = ApiPromotion(id: "offer", infoBanner: .init(
        title: "💎 Higher-yield staking available",
        description: "Tap Earn to restake your TON with higher returns.",
        actionButton: .init(title: "Restake Now", onClickAction: .openEarn)
    ))
    private var previousTabIds: [AppTabId] = []

    override func invokeTest() {
        withDependencies {
            $0.context = .live
            $0[AccountConfigStore.self] = AccountConfigStore()
            $0[AccountSettingsStore.self] = AccountSettingsStore()
        } operation: {
            super.invokeTest()
        }
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        _ = WalletResourcesBundle.bundle.load()
        try MainActor.assumeIsolated {
            let db = try DatabaseQueue()
            try makeMigrator().migrate(db)
            SettingsStore.liveValue.use(db: db)
            UIView.setAnimationsEnabled(false)
            previousTabIds = AppTabManager.shared.orderedTabIds
            AppTabManager.shared.resetToDefault()
            AccountContext(source: .current).config.banners.replace(home: [Self.banner], staking: [])
        }
    }

    override func tearDown() {
        MainActor.assumeIsolated {
            AccountContext(source: .current).config.banners.replace(home: [], staking: [])
            AppTabManager.shared.setTabIds(previousTabIds)
            SettingsStore.liveValue.clean()
            UIView.setAnimationsEnabled(true)
        }
        super.tearDown()
    }

    @available(iOS 17.0, *)
    func testBannersFloatAboveTheTopTabsToolbarOnlyWhileWalletIsNotFirst() async throws {
        let (root, window) = host(.compact)
        defer { window.isHidden = true }
        try await settle(window)
        let topTabs = try getTopTabs(root)
        let walletList = try XCTUnwrap(topTabs.promotionOverlayContentControllers.first)
        let restingInset = walletList.additionalSafeAreaInsets.bottom
        XCTAssertFalse(HomePromotionPlacement.shared.isOverlay)
        XCTAssertEqual(root.searchController.promotionOverlay.reservedHeight, 0)

        AppTabManager.shared.setTabIds(Self.walletSecondTabIds)
        try await settle(window)
        XCTAssertTrue(HomePromotionPlacement.shared.isOverlay)
        let overlay = try getOverlayView(in: window)
        XCTAssertFalse(overlay.isHidden)
        let reservedHeight = root.searchController.promotionOverlay.reservedHeight
        XCTAssertGreaterThan(overlay.bounds.height, 60)
        XCTAssertEqual(reservedHeight, overlay.bounds.height + 10, accuracy: 0.5)
        // The lists the banners float over end above them
        XCTAssertEqual(walletList.additionalSafeAreaInsets.bottom, restingInset + reservedHeight, accuracy: 0.5)
        // The cards line up with the toolbar, which a wide screen caps, and float 10 pt above it
        let toolbar = root.searchController.searchToolbar
        let toolbarFrame = toolbar.convert(toolbar.bounds, to: window)
        let overlayFrame = overlay.convert(overlay.bounds, to: window)
        XCTAssertEqual(overlayFrame.minX, toolbarFrame.minX - 12, accuracy: 0.5)
        XCTAssertEqual(overlayFrame.maxX, toolbarFrame.maxX + 12, accuracy: 0.5)
        XCTAssertLessThan(overlayFrame.width, window.bounds.width - 32)
        XCTAssertEqual(overlayFrame.maxY, toolbarFrame.minY - 10, accuracy: 0.5)

        AppTabManager.shared.resetToDefault()
        try await settle(window)
        XCTAssertFalse(HomePromotionPlacement.shared.isOverlay)
        XCTAssertEqual(root.searchController.promotionOverlay.reservedHeight, 0)
        XCTAssertEqual(walletList.additionalSafeAreaInsets.bottom, restingInset, accuracy: 0.5)
    }

    /// The split layout's sidebar shows the banners, so they do not float over its content panel as well
    @available(iOS 17.0, *)
    func testSplitLayoutKeepsTheBannersInItsSidebar() async throws {
        AppTabManager.shared.setTabIds(Self.walletSecondTabIds)
        let (root, window) = host(.regular)
        defer { window.isHidden = true }
        try await settle(window)
        XCTAssertFalse(HomePromotionPlacement.shared.isOverlay)
        XCTAssertEqual(root.searchController.promotionOverlay.reservedHeight, 0)
    }

    @available(iOS 17.0, *)
    func testBannersHideAwayFromTheRootToolbarAndReturnOnceItSettles() async throws {
        AppTabManager.shared.setTabIds(Self.walletSecondTabIds)
        let (root, window) = host(.compact)
        defer { window.isHidden = true }
        try await settle(window)
        let topTabs = try getTopTabs(root)
        let navigation = try XCTUnwrap(root.children.first as? WNavigationController)
        let overlay = try getOverlayView(in: window)
        XCTAssertFalse(overlay.isHidden)

        navigation.pushViewController(UIViewController(), animated: true)
        try await settle(window)
        XCTAssertTrue(overlay.isHidden)
        navigation.popViewController(animated: true)
        try await settle(window)
        XCTAssertFalse(overlay.isHidden)

        root.searchController.setToolbarEditorDimmed(true)
        try await settle(window)
        XCTAssertTrue(overlay.isHidden)
        root.searchController.setToolbarEditorDimmed(false)
        try await settle(window)
        XCTAssertFalse(overlay.isHidden)

        // A swipe toward another screen hides the banners at once, and cancelling it brings them back
        UIView.setAnimationsEnabled(true)
        let transition = try XCTUnwrap(navigation.beginInteractivePush(UIViewController()))
        transition.update(0.4)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(overlay.isHidden)
        transition.cancel()
        try await settle(window)
        UIView.setAnimationsEnabled(false)
        XCTAssertTrue(navigation.topViewController === topTabs)
        XCTAssertFalse(overlay.isHidden)

        // The Agent tab's question field and suggestions take the banners' place
        _ = topTabs.selectTab(.agent, animated: false)
        try await settle(window)
        XCTAssertTrue(overlay.isHidden)
        _ = topTabs.selectTab(.market, animated: false)
        try await settle(window)
        XCTAssertFalse(overlay.isHidden)
    }

    @available(iOS 17.0, *)
    private func host(_ sizeClass: UIUserInterfaceSizeClass) -> (AdaptiveRootViewController, UIWindow) {
        let root = AdaptiveRootViewController()
        root.traitOverrides.horizontalSizeClass = sizeClass
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1024, height: 900))
        window.rootViewController = root
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        return (root, window)
    }

    private func getTopTabs(_ root: AdaptiveRootViewController) throws -> TopTabsRootViewController {
        let navigation = try XCTUnwrap(root.children.first as? WNavigationController)
        return try XCTUnwrap(navigation.viewControllers.first as? TopTabsRootViewController)
    }

    private func getOverlayView(in window: UIWindow) throws -> UIView {
        try XCTUnwrap(findDescendants(of: window).first {
            String(describing: type(of: $0)).contains("RootPromotionOverlayView")
        })
    }

    private func settle(_ window: UIWindow) async throws {
        // The overlay's height reaches the root tabs' insets one layout pass after the banners change
        for index in 0..<30 {
            try await Task.sleep(for: .milliseconds(50))
            window.layoutIfNeeded()
            let navigation = window.rootViewController?.children.first as? WNavigationController
            if index >= 4, navigation?.transitionCoordinator == nil { return }
        }
        XCTFail("Navigation did not settle")
    }

    private func findDescendants(of view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + findDescendants(of: $0) }
    }
}
