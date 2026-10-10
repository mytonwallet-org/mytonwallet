import Dependencies
import UIKit
import XCTest
@testable import UIComponents
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
        for animated in [false, true] {
            let root = TopTabsRootViewController()
            let navigation = WNavigationController(rootViewController: root)
            XCTAssertFalse(root.isViewLoaded)

            XCTAssertTrue(root.selectTab(.settings, animated: animated))

            XCTAssertTrue(root.isViewLoaded)
            XCTAssertEqual(root.currentTabId, .settings)
            XCTAssertEqual(navigation.viewControllers.count, 2)
            XCTAssertTrue(root.selectTab(.settings, animated: animated))
            XCTAssertEqual(navigation.viewControllers.count, 2)
        }
    }

    func testOpeningSettingsPathBeforeFirstViewLoad() {
        let root = TopTabsRootViewController()
        let navigation = WNavigationController(rootViewController: root)
        let destination = UIViewController()
        root.switchToSettings(path: [destination])
        XCTAssertEqual(root.currentTabId, .settings)
        XCTAssertEqual(navigation.viewControllers.count, 3)
        XCTAssertTrue(navigation.topViewController === destination)
    }

    func testPushingOnSettingsRootBeforeFirstViewLoad() {
        let root = TopTabsRootViewController()
        let navigation = WNavigationController(rootViewController: root)
        let destination = UIViewController()
        XCTAssertTrue(root.pushOnSettingsRoot(destination))
        XCTAssertEqual(root.currentTabId, .settings)
        XCTAssertEqual(navigation.viewControllers.count, 3)
        XCTAssertTrue(navigation.topViewController === destination)
    }

    func testMigrationDoesNotCreateUnusedCompactPages() throws {
        let root = TopTabsRootViewController()
        let navigation = WNavigationController(rootViewController: root)
        root.loadViewIfNeeded()

        let state = try XCTUnwrap(AdaptiveRootNavigationState(viewController: navigation))

        XCTAssertNil(state.navigationStacks[.market])
        XCTAssertNil(state.navigationStacks[.explore])
        XCTAssertNil(state.navigationStacks[.settings])
    }

    func testMigrationPreservesPathOnUnloadedCompactPage() throws {
        let root = TopTabsRootViewController()
        let navigation = WNavigationController(rootViewController: root)
        root.loadViewIfNeeded()
        let destination = UIViewController()
        root.setNavigationPath([destination], for: .explore)

        let state = try XCTUnwrap(AdaptiveRootNavigationState(viewController: navigation))
        let split = SplitRootViewController()
        split.loadViewIfNeeded()
        split.applyTabConfiguration(AppTabManager.shared.orderedTabIds)
        state.apply(to: split, layout: .split)

        let stack = try XCTUnwrap(split.takeNavigationStack(for: .explore, keepingRoot: true))
        XCTAssertEqual(stack.count, 2)
        XCTAssertTrue(stack.last === destination)
    }

    func testRestorationReusesDestinationHomeAndKeepsUnusedSplitTabsLazy() throws {
        let root = TopTabsRootViewController()
        let navigation = WNavigationController(rootViewController: root)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 466, height: 874))
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        window.layoutIfNeeded()
        // Even prepared pages must not force new roots in the destination layout.
        let pager = try XCTUnwrap(root.children.first as? WPagerViewController)
        pager.prepareNextPage()
        pager.prepareNextPage()
        let destination = UIViewController()
        root.setNavigationPath([destination], for: .wallet)
        let state = try XCTUnwrap(AdaptiveRootNavigationState(viewController: navigation))
        XCTAssertNotNil(state.navigationStacks[.market])
        XCTAssertNotNil(state.navigationStacks[.explore])

        let split = SplitRootViewController()
        split.loadViewIfNeeded()
        split.applyTabConfiguration(AppTabManager.shared.orderedTabIds)
        let home = try XCTUnwrap(split.takeNavigationStack(for: .wallet, keepingRoot: true)?.first)
        state.apply(to: split, layout: .split)

        let stack = try XCTUnwrap(split.takeNavigationStack(for: .wallet, keepingRoot: true))
        XCTAssertTrue(stack.first === home)
        XCTAssertTrue(stack.last === destination)
        XCTAssertNil(split.takeNavigationStack(for: .market, keepingRoot: true))
        XCTAssertNil(split.takeNavigationStack(for: .explore, keepingRoot: true))
        XCTAssertNil(split.takeNavigationStack(for: .settings, keepingRoot: true))
    }

    func testRestorationReusesDestinationCompactHome() throws {
        let split = SplitRootViewController()
        split.loadViewIfNeeded()
        split.applyTabConfiguration(AppTabManager.shared.orderedTabIds)
        let destination = UIViewController()
        split.setNavigationPath([destination], for: .wallet)
        let state = try XCTUnwrap(AdaptiveRootNavigationState(viewController: split))
        let root = TopTabsRootViewController()
        let navigation = WNavigationController(rootViewController: root)
        let home = root.homeVC

        state.apply(to: navigation, layout: .tab)

        XCTAssertTrue(root.homeVC === home)
        XCTAssertTrue(navigation.topViewController === destination)
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

    @available(iOS 17.0, *)
    func testPreparedPagesSurviveCompactRegularRoundTripWithNavigationPath() throws {
        let adaptive = AdaptiveRootViewController()
        adaptive.traitOverrides.horizontalSizeClass = .compact
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 466, height: 874))
        window.rootViewController = adaptive
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        window.layoutIfNeeded()
        let navigation = try XCTUnwrap(adaptive.children.first as? WNavigationController)
        let root = try XCTUnwrap(navigation.viewControllers.first as? TopTabsRootViewController)
        let pager = try XCTUnwrap(root.children.first as? WPagerViewController)
        pager.prepareNextPage()
        pager.prepareNextPage()
        XCTAssertEqual(pager.children.count, 3)
        let destination = UIViewController()
        root.setNavigationPath([destination], for: .explore)
        root.selectTab(.explore)
        XCTAssertTrue(navigation.topViewController === destination)

        changeLayout(of: adaptive, to: .regular)
        window.layoutIfNeeded()
        let split = try XCTUnwrap(adaptive.children.first as? SplitRootViewController)
        XCTAssertEqual(split.currentTabId, .explore)
        changeLayout(of: adaptive, to: .compact)
        window.layoutIfNeeded()
        let restoredNavigation = try XCTUnwrap(adaptive.children.first as? WNavigationController)
        let restoredRoot = try XCTUnwrap(restoredNavigation.viewControllers.first as? TopTabsRootViewController)
        XCTAssertEqual(restoredRoot.currentTabId, .explore)
        XCTAssertTrue(restoredNavigation.topViewController === destination)
    }

    func testLayoutChangeDuringSwipeCapturesTheResolvedTabAndItsNavigationPath() throws {
        let adaptive = AdaptiveRootViewController()
        adaptive.traitOverrides.horizontalSizeClass = .compact
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 466, height: 874))
        window.rootViewController = adaptive
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        window.layoutIfNeeded()
        let navigation = try XCTUnwrap(adaptive.children.first as? WNavigationController)
        let root = try XCTUnwrap(navigation.viewControllers.first as? TopTabsRootViewController)
        let pager = try XCTUnwrap(root.children.first as? WPagerViewController)
        let destination = UIViewController()
        root.setNavigationPath([destination], for: .market)
        let scroll = pager.scrollView!
        pager.scrollViewWillBeginDragging(scroll)
        scroll.contentOffset.x += scroll.bounds.width * 0.8
        pager.scrollViewDidEndDragging(scroll, willDecelerate: true)

        changeLayout(of: adaptive, to: .regular)
        window.layoutIfNeeded()
        let split = try XCTUnwrap(adaptive.children.first as? SplitRootViewController)
        XCTAssertEqual(split.currentTabId, .market)
        changeLayout(of: adaptive, to: .compact)
        window.layoutIfNeeded()
        let restoredNavigation = try XCTUnwrap(adaptive.children.first as? WNavigationController)
        let restoredRoot = try XCTUnwrap(restoredNavigation.viewControllers.first as? TopTabsRootViewController)
        XCTAssertEqual(restoredRoot.currentTabId, .market)
        XCTAssertTrue(restoredNavigation.topViewController === destination)
        pager.scrollViewDidEndDecelerating(scroll)
        XCTAssertEqual(restoredRoot.currentTabId, .market)
    }

    func testPreparedRootPagesKeepNativeMarginsAndOnlyPresentSelectedContent() async throws {
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
                let visiblePages = pager.children.filter { $0.view.superview?.isHidden == false }
                XCTAssertEqual(visiblePages.count, 1)
                let content = root.visibleContentProviderViewController
                XCTAssertTrue(visiblePages.first?.children.first === content)
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
