import Dependencies
import UIKit
import XCTest
import UIComponents
import WalletContext
import WalletResources
@testable import AirAsFramework

@MainActor
final class TopTabsRestorationTests: XCTestCase {
    override func invokeTest() {
        withDependencies {
            $0.context = .live
        } operation: {
            super.invokeTest()
        }
    }

    override func setUp() {
        super.setUp()
        _ = WalletResourcesBundle.bundle.load()
        MainActor.assumeIsolated {
            UIView.setAnimationsEnabled(false)
        }
    }

    override func tearDown() {
        MainActor.assumeIsolated {
            UIView.setAnimationsEnabled(true)
        }
        super.tearDown()
    }

    func testSelectingTabBeforeFirstViewLoad() {
        for id in [AppTabId.wallet, .market, .explore] {
            let root = TopTabsRootViewController()
            XCTAssertFalse(root.isViewLoaded)

            XCTAssertTrue(root.selectTab(id))

            XCTAssertTrue(root.isViewLoaded)
            XCTAssertEqual(root.currentTabId, id)
        }
    }

    func testSelectingSettingsBeforeFirstViewLoad() {
        let root = TopTabsRootViewController()
        let navigation = WNavigationController(rootViewController: root)
        XCTAssertFalse(root.isViewLoaded)

        XCTAssertTrue(root.selectTab(.settings))

        XCTAssertTrue(root.isViewLoaded)
        XCTAssertEqual(root.currentTabId, .settings)
        XCTAssertEqual(navigation.viewControllers.count, 2)
    }

    @available(iOS 17.0, *)
    func testLayoutRoundTripPreservesSelectedTabAndNavigationPaths() throws {
        for selectedTab in [AppTabId.wallet, .market, .explore, .settings] {
            let adaptive = AdaptiveRootViewController()
            adaptive.traitOverrides.horizontalSizeClass = .regular
            adaptive.loadViewIfNeeded()
            let split = try XCTUnwrap(adaptive.children.first as? SplitRootViewController)
            let paths = Dictionary(uniqueKeysWithValues: [AppTabId.wallet, .market, .explore, .settings].map {
                ($0, [UIViewController(), UIViewController()])
            })
            for (id, path) in paths {
                split.setNavigationPath(path, for: id)
            }
            split.select(tab: selectedTab)

            changeLayout(of: adaptive, to: .compact)
            let firstNavigation = try XCTUnwrap(adaptive.children.first as? WNavigationController)
            let firstTopTabs = try XCTUnwrap(firstNavigation.viewControllers.first as? TopTabsRootViewController)
            XCTAssertEqual(firstTopTabs.currentTabId, selectedTab)
            XCTAssertTrue(firstNavigation.viewControllers.last === paths[selectedTab]?.last)

            changeLayout(of: adaptive, to: .regular)
            let restoredSplit = try XCTUnwrap(adaptive.children.first as? SplitRootViewController)
            XCTAssertEqual(restoredSplit.currentTabId, selectedTab)

            changeLayout(of: adaptive, to: .compact)
            let navigation = try XCTUnwrap(adaptive.children.first as? WNavigationController)
            let topTabs = try XCTUnwrap(navigation.viewControllers.first as? TopTabsRootViewController)
            XCTAssertEqual(topTabs.currentTabId, selectedTab)
            XCTAssertTrue(navigation.viewControllers.last === paths[selectedTab]?.last)
            for (id, path) in paths {
                let stack = try XCTUnwrap(topTabs.takeNavigationStack(for: id, keepingRoot: true))
                XCTAssertEqual(stack.count, path.count + 1)
                XCTAssertTrue(Array(stack.dropFirst()).elementsEqual(path, by: { $0 === $1 }))
            }
        }
    }

    func testRootPagesKeepNativeMarginsAndOnlyMountSelectedContent() async throws {
        let root = TopTabsRootViewController()
        let navigation = WNavigationController(rootViewController: root)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 466, height: 874))
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        window.layoutIfNeeded()
        let pager = try XCTUnwrap(root.children.first as? WPagerViewController)
        XCTAssertEqual(pager.children.count, 1)
        XCTAssertTrue(pager.children.first?.children.first === root.homeVC)

        for (left, right) in [(0.0, 0.0), (84, 0), (0, 84), (0, 0)] {
            root.additionalSafeAreaInsets.left = left
            root.additionalSafeAreaInsets.right = right
            for tab in [AppTabId.wallet, .explore, .wallet, .market] {
                root.selectTab(tab)
                window.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(100))
                window.layoutIfNeeded()
                XCTAssertEqual(pager.children.count, 1)
                let content = root.visibleContentProviderViewController
                XCTAssertTrue(pager.children.first?.children.first === content)
                XCTAssertEqual(content.view.safeAreaInsets.left, root.view.safeAreaInsets.left)
                XCTAssertEqual(content.view.safeAreaInsets.right, root.view.safeAreaInsets.right)
                XCTAssertEqual(content.view.layoutMargins.left, root.view.layoutMargins.left)
                XCTAssertEqual(content.view.layoutMargins.right, root.view.layoutMargins.right)
                XCTAssertTrue(content.viewRespectsSystemMinimumLayoutMargins)
            }
        }
    }

    @available(iOS 17.0, *)
    private func changeLayout(of controller: AdaptiveRootViewController, to sizeClass: UIUserInterfaceSizeClass) {
        let previousTraits = controller.traitCollection
        controller.traitOverrides.horizontalSizeClass = sizeClass
        controller.traitCollectionDidChange(previousTraits)
    }
}
