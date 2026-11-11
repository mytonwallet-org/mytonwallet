import ContextMenuKit
import Dependencies
import GRDB
import UIKit
import XCTest
import UIAgent
@testable import UIComponents
import WalletContext
@testable import WalletCore
import WalletResources
@testable import AirAsFramework

@MainActor
final class TopTabsRestorationTests: XCTestCase {
    private var previousTabIds: [AppTabId] = []

    override func invokeTest() {
        withDependencies {
            $0.context = .live
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
        }
    }

    override func tearDown() {
        MainActor.assumeIsolated {
            AppTabManager.shared.setTabIds(previousTabIds)
            SettingsStore.liveValue.clean()
            UIView.setAnimationsEnabled(true)
        }
        super.tearDown()
    }

    func testSelectingTabBeforeFirstViewLoad() {
        for id in [AppTabId.wallet, .market, .agent, .explore] {
            let root = TopTabsRootViewController()
            XCTAssertFalse(root.isViewLoaded)

            XCTAssertTrue(root.selectTab(id))

            XCTAssertTrue(root.isViewLoaded)
            XCTAssertEqual(root.currentTabId, id)
        }
    }

    func testDigestFeedOpensBeforeNavigationIsInAWindow() {
        let root = TopTabsRootViewController()
        let navigation = WNavigationController(rootViewController: root)
        navigation.loadViewIfNeeded()
        defer { navigation.setViewControllers([], animated: false) }
        XCTAssertNil(navigation.viewIfLoaded?.window)
        root.showAgentNewsFeed(digestId: "en:2026-11-08T18:00:00.000Z")
        XCTAssertEqual(root.currentTabId, .agent)
        XCTAssertEqual(navigation.viewControllers.count, 2)
        XCTAssertTrue(navigation.topViewController is AgentNewsFeedVC)
    }

    func testTabMenuTracksAvailableTabsAndTheirOrder() throws {
        let root = TopTabsRootViewController()
        root.loadViewIfNeeded()
        let header = try XCTUnwrap(root.navigationItem.titleView)
        func findControl(in view: UIView) -> WSegmentedControl? {
            if let control = view as? WSegmentedControl { return control }
            return view.subviews.lazy.compactMap { findControl(in: $0) }.first
        }
        let control = try XCTUnwrap(findControl(in: header))
        let provider = try XCTUnwrap(control.longPressContextMenuProvider)
        let originalItems = control.model.items
        defer { control.model.setItems(originalItems) }

        func getMenuActions() -> [ContextMenuAction] {
            provider.makeConfiguration().rootPage.items.compactMap {
                guard case .action(let action) = $0 else { return nil }
                return action
            }
        }

        XCTAssertFalse(getMenuActions().contains { $0.id == "tab_menu_futures" })
        XCTAssertTrue(getMenuActions().contains { $0.id == "tab_menu_agent" })
        let withoutAgent = originalItems.filter { $0.id != AppTabId.agent.rawValue }
        control.model.setItems(withoutAgent)
        XCTAssertEqual(getMenuActions().map(\.id), withoutAgent.map { "tab_menu_\($0.id)" })
        XCTAssertEqual(getMenuActions().map(\.title), withoutAgent.map(\.title))
        XCTAssertFalse(getMenuActions().contains { $0.id == "tab_menu_agent" })

        let reorderedItems = Array(originalItems.reversed())
        control.model.setItems(reorderedItems)
        XCTAssertEqual(getMenuActions().map(\.id), reorderedItems.map { "tab_menu_\($0.id)" })
        XCTAssertEqual(getMenuActions().map(\.title), reorderedItems.map(\.title))
        XCTAssertTrue(getMenuActions().contains { $0.id == "tab_menu_agent" })
    }

    func testFuturesRootReplacesItsAccountScopedContentWhenWalletChanges() async throws {
        let db = try DatabaseQueue()
        try makeMigrator().migrate(db)
        let first = MAccount(id: "870011-mainnet", title: "First", type: .view,
                             byChain: [.ton: .init(address: "first")])
        let second = MAccount(id: "870012-mainnet", title: "Second", type: .view,
                              byChain: [.ton: .init(address: "second")])
        try await db.write { db in
            try first.insert(db)
            try second.insert(db)
        }
        let store = _AccountStore(db: db)
        _ = try await store.accountForActivation(accountId: first.id)
        _ = try await store.accountForActivation(accountId: second.id)
        await withDependencies {
            $0.accountStore = store
        } operation: {
            let context = AccountContext(accountId: first.id)
            let root = PerpsTabVC(accountContext: context)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
            window.rootViewController = root
            root.additionalSafeAreaInsets = UIEdgeInsets(top: 52, left: 0, bottom: 64, right: 0)
            window.makeKeyAndVisible()
            window.layoutIfNeeded()
            defer { window.isHidden = true }
            let firstContent = root.children.first
            let expectedInsets = root.view.safeAreaInsets
            XCTAssertGreaterThan(expectedInsets.top, 0)
            XCTAssertGreaterThan(expectedInsets.bottom, 0)
            XCTAssertEqual(root.accountId, first.id)
            root.setPagingBackgroundColor(.systemPink)
            XCTAssertEqual(firstContent?.view.backgroundColor, .systemPink)

            context.accountId = second.id
            for _ in 0..<20 where root.accountId != second.id {
                await Task.yield()
            }

            XCTAssertEqual(root.accountId, second.id)
            XCTAssertEqual(root.children.count, 1)
            XCTAssertFalse(root.children.first === firstContent)
            XCTAssertNil(firstContent?.parent)
            XCTAssertEqual(root.children.first?.view.backgroundColor, .systemPink)
            root.setPagingBackgroundColor(nil)
            XCTAssertEqual(root.children.first?.view.backgroundColor, .air.groupedBackground)
            window.layoutIfNeeded()
            XCTAssertEqual(root.children.first?.view.frame, root.view.bounds)
            guard let collection = root.children.first?.view.subviews.first(where: { $0 is UICollectionView }) as? UICollectionView else {
                XCTFail("Futures must use a native collection view")
                return
            }
            XCTAssertEqual(collection.frame, root.view.bounds)
            XCTAssertEqual(collection.adjustedContentInset.top, expectedInsets.top, accuracy: 0.5)
            XCTAssertEqual(collection.adjustedContentInset.bottom, expectedInsets.bottom + 32, accuracy: 0.5)
            XCTAssertEqual(collection.contentOffset.y, -collection.adjustedContentInset.top, accuracy: 0.5)
            root.additionalSafeAreaInsets.top = 76
            root.additionalSafeAreaInsets.bottom = 88
            window.layoutIfNeeded()
            XCTAssertEqual(root.children.first?.view.frame, root.view.bounds)
            XCTAssertEqual(collection.adjustedContentInset.top, root.view.safeAreaInsets.top, accuracy: 0.5)
            XCTAssertEqual(collection.adjustedContentInset.bottom, root.view.safeAreaInsets.bottom + 32, accuracy: 0.5)
            XCTAssertEqual(collection.contentInsetAdjustmentBehavior, .never)
            collection.contentOffset.y = 100
            root.beginAppearanceTransition(false, animated: false)
            root.endAppearanceTransition()
            root.beginAppearanceTransition(true, animated: false)
            root.endAppearanceTransition()
            XCTAssertEqual(collection.contentOffset.y, 100, accuracy: 0.5)
        }
    }

    func testAccountsPreferenceMovesAvatarOnEveryTab() throws {
        let key = ToolbarSettings.accountsKey
        let previousValue = UserDefaults.standard.object(forKey: key)
        defer {
            UserDefaults.standard.set(previousValue, forKey: key)
            ToolbarSettings.notifyDidChange()
        }
        UserDefaults.standard.set(false, forKey: key)
        let root = TopTabsRootViewController()
        let navigation = WNavigationController(rootViewController: root)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        root.loadViewIfNeeded()
        window.layoutIfNeeded()
        func find(_ identifier: String, in view: UIView) -> UIView? {
            if view.accessibilityIdentifier == identifier { return view }
            return view.subviews.lazy.compactMap { find(identifier, in: $0) }.first
        }
        let header = try XCTUnwrap(root.navigationItem.titleView)
        let avatar = try XCTUnwrap(find("tab_settings_button", in: header))
        XCTAssertFalse(avatar.isHidden)
        XCTAssertTrue(root.searchController.searchToolbar.accountsButton.isHidden)

        UserDefaults.standard.set(true, forKey: key)
        ToolbarSettings.notifyDidChange()
        window.layoutIfNeeded()
        XCTAssertTrue(avatar.isHidden)
        XCTAssertFalse(root.searchController.searchToolbar.accountsButton.isHidden)
        XCTAssertTrue(root.searchController.searchToolbar.accountsButton.isUserInteractionEnabled)

        // The Agent tab's header has no avatar either, so the tabs stay where they are between pages. In a window that
        // isn't on screen, as here, the navigation bar may leave the header out of the window until its content is laid
        // out again, which a screen on display does before it first shows, so each place is read once it is laid out.
        func laidOutTabsOrigin() throws -> CGPoint {
            var views: [UIView] = [navigation.navigationBar]
            while let view = views.popLast() {
                if #available(iOS 26.0, *) { view.setNeedsUpdateProperties() }
                view.setNeedsLayout()
                views += view.subviews
            }
            if #available(iOS 26.0, *) { window.updatePropertiesIfNeeded() }
            window.layoutIfNeeded()
            XCTAssertNotNil(header.window, "The header shows in the window")
            var tabs: UIView? = try XCTUnwrap(find("tab_wallet", in: header))
            while let view = tabs, !(view is WSegmentedControl) { tabs = view.superview }
            // The selected title scrolls within the capsule when five tabs overflow.
            return try XCTUnwrap(tabs).convert(CGPoint.zero, to: header)
        }
        let tabsOrigin = try laidOutTabsOrigin()
        XCTAssertTrue(root.selectTab(.agent, animated: false))
        XCTAssertTrue(avatar.isHidden)
        XCTAssertEqual(try laidOutTabsOrigin(), tabsOrigin)
        XCTAssertTrue(root.selectTab(.wallet, animated: false))
        XCTAssertTrue(avatar.isHidden)

        UserDefaults.standard.set(false, forKey: key)
        ToolbarSettings.notifyDidChange()
        XCTAssertFalse(avatar.isHidden)
        XCTAssertTrue(root.searchController.searchToolbar.accountsButton.isHidden)
    }

    @available(iOS 17.0, *)
    func testDraggingInTheTabMenuReordersTheTabsAndKeepsTheSelectedPage() throws {
        let adaptive = AdaptiveRootViewController()
        adaptive.traitOverrides.horizontalSizeClass = .compact
        adaptive.loadViewIfNeeded()
        let navigation = try XCTUnwrap(adaptive.children.first as? WNavigationController)
        let root = try XCTUnwrap(navigation.viewControllers.first as? TopTabsRootViewController)
        // The navigation controller loads its root's view only to show it, and the header comes with the view
        root.loadViewIfNeeded()
        func findControl(in view: UIView) -> WSegmentedControl? {
            if let control = view as? WSegmentedControl { return control }
            return view.subviews.lazy.compactMap { findControl(in: $0) }.first
        }
        let control = try XCTUnwrap(findControl(in: try XCTUnwrap(root.navigationItem.titleView)))
        let menuPage = try XCTUnwrap(control.longPressContextMenuProvider).makeConfiguration().rootPage
        XCTAssertTrue(root.selectTab(.agent, animated: false))

        // Wallet is dragged past Agent
        menuPage.onReorder?(0, 2)

        XCTAssertEqual(AppTabManager.shared.orderedTabIds, [.market, .agent, .wallet, .explore, .settings])
        XCTAssertEqual(control.model.items.map(\.id), [AppTabId.market, .agent, .wallet, .explore].map(\.rawValue))
        XCTAssertEqual(root.currentTabId, .agent)
        XCTAssertTrue(root.visibleContentProviderViewController is AgentThreadListVC)

        XCTAssertTrue(root.selectTab(.market, animated: false))
        XCTAssertEqual(root.currentTabId, .market)
        XCTAssertEqual(control.model.selectedItem?.id, AppTabId.market.rawValue)
    }

    /// Top Tabs shows a page left out of the user's order after the others, and the menu's drags still reorder the rest
    @available(iOS 17.0, *)
    func testTabMenuReordersTheTabsWhileAPageIsLeftOutOfTheOrder() throws {
        AppTabManager.shared.setTabIds([.wallet, .market, .explore, .settings])
        let adaptive = AdaptiveRootViewController()
        adaptive.traitOverrides.horizontalSizeClass = .compact
        adaptive.loadViewIfNeeded()
        let navigation = try XCTUnwrap(adaptive.children.first as? WNavigationController)
        let root = try XCTUnwrap(navigation.viewControllers.first as? TopTabsRootViewController)
        root.loadViewIfNeeded()
        func findControl(in view: UIView) -> WSegmentedControl? {
            if let control = view as? WSegmentedControl { return control }
            return view.subviews.lazy.compactMap { findControl(in: $0) }.first
        }
        let control = try XCTUnwrap(findControl(in: try XCTUnwrap(root.navigationItem.titleView)))
        let menuPage = try XCTUnwrap(control.longPressContextMenuProvider).makeConfiguration().rootPage

        // Explore is dragged to the first place, over the Agent page shown after it
        menuPage.onReorder?(2, 0)

        XCTAssertEqual(AppTabManager.shared.orderedTabIds, [.explore, .wallet, .market, .settings])
        XCTAssertEqual(control.model.items.map(\.id), [AppTabId.explore, .wallet, .market, .agent].map(\.rawValue))
    }

    @available(iOS 17.0, *)
    func testAgentRemainsSelectableWhenExcludedFromSidebarOrder() throws {
        AppTabManager.shared.setTabIds([.wallet, .market, .explore, .settings])
        let adaptive = AdaptiveRootViewController()
        adaptive.traitOverrides.horizontalSizeClass = .compact
        adaptive.loadViewIfNeeded()
        let navigation = try XCTUnwrap(adaptive.children.first as? WNavigationController)
        let root = try XCTUnwrap(navigation.viewControllers.first as? TopTabsRootViewController)

        XCTAssertTrue(root.selectTab(.agent))

        XCTAssertEqual(root.currentTabId, .agent)
        XCTAssertTrue(root.visibleContentProviderViewController is AgentThreadListVC)
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
        XCTAssertNil(state.navigationStacks[.agent])
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
        pager.prepareNextPage()
        pager.prepareNextPage()
        let destination = UIViewController()
        root.setNavigationPath([destination], for: .wallet)
        let state = try XCTUnwrap(AdaptiveRootNavigationState(viewController: navigation))
        XCTAssertNotNil(state.navigationStacks[.market])
        XCTAssertNotNil(state.navigationStacks[.agent])
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
        XCTAssertNil(split.takeNavigationStack(for: .agent, keepingRoot: true))
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
        for selectedTab in [AppTabId.wallet, .market, .agent, .explore, .settings] {
            let adaptive = AdaptiveRootViewController()
            adaptive.traitOverrides.horizontalSizeClass = .regular
            adaptive.loadViewIfNeeded()
            let split = try XCTUnwrap(adaptive.children.first as? SplitRootViewController)
            let paths = Dictionary(uniqueKeysWithValues: [AppTabId.wallet, .market, .agent, .explore, .settings].map {
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
        pager.prepareNextPage()
        XCTAssertEqual(pager.children.count, 4)
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
            for tab in [AppTabId.wallet, .agent, .explore, .wallet, .market] {
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
