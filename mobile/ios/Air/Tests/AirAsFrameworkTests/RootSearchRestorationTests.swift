import Dependencies
import UIKit
import XCTest
import UIComponents
import UISettings
import UIUniversalSearch
import WalletContext
import WalletResources
@testable import AirAsFramework

@MainActor
final class RootSearchRestorationTests: XCTestCase {
    override func invokeTest() {
        withDependencies { $0.context = .live } operation: { super.invokeTest() }
    }

    override func setUp() {
        super.setUp()
        _ = WalletResourcesBundle.bundle.load()
        MainActor.assumeIsolated { UIView.setAnimationsEnabled(false) }
    }

    override func tearDown() {
        MainActor.assumeIsolated { UIView.setAnimationsEnabled(true) }
        super.tearDown()
    }

    @available(iOS 17.0, *)
    func testActiveSearchAndQuerySurviveBothLayoutDirections() async throws {
        for (initial, tab) in [UIUserInterfaceSizeClass.compact, .regular].flatMap({ sizeClass in
            [AppTabId.wallet, .market, .explore].map { (sizeClass, $0) }
        }) {
            let (root, window) = host(initial)
            selectTab(tab, in: root)
            try await settle(window)
            defer { window.isHidden = true }
            let toolbar = root.searchController
            toolbar.openSearch()
            try await settle(window)
            let search = try XCTUnwrap(toolbar.universalSearchViewController)
            search.restoresKeyboard = false
            toolbar.searchToolbar.endEditing()
            toolbar.searchToolbar.onTextChange?("ton")
            let session = search.session
            let field = toolbar.searchToolbar

            for sizeClass in [opposite(initial), initial] {
                changeLayout(root, to: sizeClass)
                try await settle(window)
                let navigation = try navigation(root)
                XCTAssertTrue(toolbar.universalSearchViewController === search, "\(initial) \(tab) → \(sizeClass)")
                XCTAssertTrue(search.session === session)
                XCTAssertTrue(toolbar.searchToolbar === field)
                XCTAssertTrue(navigation.topViewController === search)
                XCTAssertEqual(search.fieldConfiguration.text, "ton")
                XCTAssertEqual(field.configuration.text, "ton")
                XCTAssertNil(search.returnDeadline)
                XCTAssertEqual(currentTab(root), tab)
                XCTAssertFalse(search.restoresKeyboard)
                if let split = root.children.first as? SplitRootViewController {
                    let sidebar = try XCTUnwrap(split.viewController(for: .primary) as? SplitRootSidebarNavigationController)
                    XCTAssertTrue(sidebar.isSearchVisible)
                }
            }
            toolbar.closeSearch()
            try await settle(window)
            XCTAssertNil(toolbar.universalSearchViewController)
            XCTAssertEqual(try navigation(root).viewControllers.count, 1)
        }
    }

    @available(iOS 17.0, *)
    func testCoveredSearchPreservesDeadlineAndSettingsResultInItsSourceTab() async throws {
        for initial: UIUserInterfaceSizeClass in [.compact, .regular] {
            let (root, window) = host(initial)
            defer { window.isHidden = true }
            let toolbar = root.searchController
            toolbar.openSearch()
            try await settle(window)
            let search = try XCTUnwrap(toolbar.universalSearchViewController)
            toolbar.searchToolbar.onTextChange?("appearance")
            search.restoresKeyboard = false
            let destination = SettingsVC()
            XCTAssertTrue(toolbar.pushFromSearch(destination))
            try await settle(window)
            let deadline = try XCTUnwrap(search.returnDeadline)

            for sizeClass in [opposite(initial), initial] {
                changeLayout(root, to: sizeClass)
                try await settle(window)
                let navigation = try navigation(root)
                XCTAssertTrue(navigation.topViewController === destination)
                XCTAssertTrue(navigation.viewControllers.dropFirst().first === search)
                XCTAssertEqual(search.returnDeadline, deadline)
                XCTAssertEqual(currentTab(root), .wallet)
            }

            // Expiring a covered search removes only that entry, never the result on top.
            search.returnDeadline = ContinuousClock.now.advanced(by: .seconds(-1))
            toolbar.expireSearchIfNeeded(search)
            let navigation = try navigation(root)
            XCTAssertNil(toolbar.universalSearchViewController)
            XCTAssertFalse(navigation.viewControllers.contains { $0 === search })
            XCTAssertTrue(navigation.topViewController === destination)
            changeLayout(root, to: opposite(initial))
            try await settle(window)
            let restoredNavigation = try self.navigation(root)
            XCTAssertEqual(currentTab(root), .wallet)
            XCTAssertTrue(restoredNavigation.topViewController === destination)
            restoredNavigation.popViewController(animated: false)
            XCTAssertEqual(restoredNavigation.viewControllers.count, 1)
        }
    }

    @available(iOS 17.0, *)
    func testReturningBeforeDeadlineRestoresSearchAfterLayoutChange() async throws {
        let (root, window) = host(.regular)
        defer { window.isHidden = true }
        let toolbar = root.searchController
        toolbar.openSearch()
        try await settle(window)
        let search = try XCTUnwrap(toolbar.universalSearchViewController)
        toolbar.searchToolbar.onTextChange?("wallet")
        search.restoresKeyboard = false
        XCTAssertTrue(toolbar.pushFromSearch(UIViewController()))
        try await settle(window)
        XCTAssertNotNil(search.returnDeadline)
        let viewport = try XCTUnwrap(toolbar.searchToolbar.transitionViewportView)
        XCTAssertFalse(viewport.bounds.intersects(toolbar.searchToolbar.convert(toolbar.searchToolbar.bounds, to: viewport)))
        changeLayout(root, to: .compact)
        try await settle(window)
        try navigation(root).popViewController(animated: false)
        try await settle(window)
        XCTAssertTrue(toolbar.isSearchVisible)
        XCTAssertNil(search.returnDeadline)
        XCTAssertEqual(toolbar.searchToolbar.configuration.text, "wallet")
    }

    @available(iOS 17.0, *)
    func testLayoutChangeUnderModalKeepsSearchDeadline() async throws {
        let (root, window) = host(.regular)
        defer { window.isHidden = true }
        let toolbar = root.searchController
        toolbar.openSearch()
        try await settle(window)
        let search = try XCTUnwrap(toolbar.universalSearchViewController)
        search.restoresKeyboard = false
        toolbar.searchToolbar.endEditing()
        let modal = UIViewController()
        modal.modalPresentationStyle = .overFullScreen
        root.present(modal, animated: false)
        window.layoutIfNeeded()
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        search.returnDeadline = deadline

        changeLayout(root, to: .compact)
        // The covered navigation stack need not appear until modal dismissal.
        await Task.yield()
        window.layoutIfNeeded()
        XCTAssertTrue(root.presentedViewController === modal)
        XCTAssertTrue(toolbar.universalSearchViewController === search)
        XCTAssertEqual(search.returnDeadline, deadline)
        search.returnDeadline = ContinuousClock.now.advanced(by: .seconds(-1))
        toolbar.expireSearchIfNeeded(search)
        XCTAssertNil(toolbar.universalSearchViewController)
        XCTAssertFalse(try navigation(root).viewControllers.contains { $0 === search })
        XCTAssertTrue(root.presentedViewController === modal)
        root.dismiss(animated: false)
    }

    @available(iOS 17.0, *)
    func testToolbarCentersInContentPanelAndDoesNotAccumulateInsets() async throws {
        let (root, window) = host(.regular)
        defer { window.isHidden = true }
        let toolbar = root.searchController
        for sizeClass: UIUserInterfaceSizeClass in [.regular, .compact, .regular, .compact] {
            changeLayout(root, to: sizeClass)
            try await settle(window)
            let navigation = try navigation(root)
            let field = toolbar.searchToolbar
            let frame = navigation.view.convert(field.bounds, from: field)
            let contentPanel = navigation.view.safeAreaLayoutGuide.layoutFrame
            let viewport = try XCTUnwrap(field.transitionViewportView)
            let viewportFrame = viewport.convert(viewport.bounds, to: navigation.view)
            XCTAssertTrue(viewport.clipsToBounds)
            XCTAssertEqual(viewportFrame.minX, contentPanel.minX, accuracy: 0.5)
            XCTAssertEqual(viewportFrame.maxX, contentPanel.maxX, accuracy: 0.5)
            XCTAssertEqual(frame.midX, contentPanel.midX, accuracy: 0.5)
            XCTAssertEqual(frame.width, min(600, contentPanel.width - 56), accuracy: 0.5)
            XCTAssertLessThanOrEqual(frame.width, 600.5)
            XCTAssertFalse(field.isHidden)
            let content: UIViewController
            if let compact = navigation.viewControllers.first as? TopTabsRootViewController {
                content = compact.homeVC
            } else {
                content = try XCTUnwrap(navigation.viewControllers.first)
            }
            let inset = content.additionalSafeAreaInsets.bottom
            toolbar.updatePresentation()
            window.layoutIfNeeded()
            XCTAssertEqual(content.additionalSafeAreaInsets.bottom, inset)
            XCTAssertEqual(inset, 64)
        }
    }

    func testFloatingKeyboardDoesNotReserveDockedKeyboardSpace() throws {
        let screen = UniversalSearchScreenViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1024, height: 900))
        window.rootViewController = screen
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        window.layoutIfNeeded()
        let results = try XCTUnwrap(screen.children.first?.view.subviews.compactMap { $0 as? UICollectionView }.first)
        let restingInset = results.contentInset.bottom

        for (width, expectedOverlap) in [(window.bounds.width, CGFloat(300)), (CGFloat(320), CGFloat(0))] {
            let frame = CGRect(x: 0, y: window.bounds.maxY - 300, width: width, height: 300)
            NotificationCenter.default.post(name: UIResponder.keyboardWillChangeFrameNotification, object: nil, userInfo: [
                UIResponder.keyboardFrameEndUserInfoKey: window.convert(frame, to: window.screen.coordinateSpace),
                UIResponder.keyboardAnimationDurationUserInfoKey: 0,
            ])
            XCTAssertEqual(results.contentInset.bottom,
                           restingInset + max(0, expectedOverlap - screen.view.safeAreaInsets.bottom), accuracy: 0.5)
        }
    }

    func testAgentIsNoLongerATabIncludingSavedOrders() {
        let tabs = AppTabManager.shared
        XCTAssertFalse(AppTabManager.defaultTabIds.contains(.agent))
        XCTAssertFalse(tabs.registeredTabIds.contains(.agent))
        XCTAssertFalse(tabs.orderedTabIds.contains(.agent))
        XCTAssertEqual(tabs.validatedTabOrder(from: ["market", "agent", "wallet", "settings"]),
                       [.market, .wallet, .settings])
    }

    @available(iOS 17.0, *)
    func testSidebarCoverBlocksControlsAndClosesSearch() async throws {
        let (root, window) = host(.regular)
        defer { window.isHidden = true }
        let split = try XCTUnwrap(root.children.first as? SplitRootViewController)
        let sidebar = try XCTUnwrap(split.viewController(for: .primary) as? SplitRootSidebarNavigationController)
        let cover = try XCTUnwrap(sidebar.view.subviews.first { $0.accessibilityIdentifier == "SearchSidebarDismissOverlay" } as? UIControl)
        let searchController = root.searchController
        searchController.openSearch()
        try await settle(window)
        searchController.universalSearchViewController?.restoresKeyboard = false
        searchController.searchToolbar.endEditing()
        XCTAssertFalse(cover.isHidden)
        XCTAssertTrue(sidebar.topViewController?.view.accessibilityElementsHidden == true)
        XCTAssertTrue(sidebar.navigationBar.accessibilityElementsHidden)
        XCTAssertTrue(sidebar.view.hitTest(CGPoint(x: sidebar.view.bounds.midX, y: sidebar.view.bounds.midY), with: nil) === cover)

        XCTAssertTrue(searchController.pushFromSearch(UIViewController()))
        try await settle(window)
        XCTAssertTrue(cover.isHidden)
        XCTAssertFalse(sidebar.navigationBar.accessibilityElementsHidden)
        _ = try navigation(root).popViewController(animated: false)
        try await settle(window)
        XCTAssertFalse(cover.isHidden)

        cover.sendActions(for: .touchUpInside)
        try await settle(window)
        XCTAssertNil(searchController.universalSearchViewController)
        XCTAssertTrue(cover.isHidden)
        XCTAssertFalse(sidebar.topViewController?.view.accessibilityElementsHidden == true)
    }

    @available(iOS 17.0, *)
    func testCancelledResultTransitionKeepsSidebarCovered() async throws {
        let (root, window) = host(.regular)
        defer { window.isHidden = true }
        root.searchController.openSearch()
        try await settle(window)
        root.searchController.universalSearchViewController?.restoresKeyboard = false
        root.searchController.searchToolbar.endEditing()
        let split = try XCTUnwrap(root.children.first as? SplitRootViewController)
        let sidebar = try XCTUnwrap(split.viewController(for: .primary) as? SplitRootSidebarNavigationController)
        UIView.setAnimationsEnabled(true)
        let transition = try XCTUnwrap(try navigation(root).beginInteractivePush(UIViewController()))
        transition.update(0.4)
        try await Task.sleep(for: .milliseconds(50))
        transition.cancel()
        try await settle(window)
        XCTAssertTrue(root.searchController.isSearchVisible)
        XCTAssertTrue(sidebar.isSearchVisible)
        root.searchController.closeSearch()
        try await settle(window)
        XCTAssertFalse(sidebar.isSearchVisible)
    }

    @available(iOS 17.0, *)
    func testExpiringSearchUnderModalRemovesSidebarCover() async throws {
        let (root, window) = host(.regular)
        defer { window.isHidden = true }
        let searchController = root.searchController
        searchController.openSearch()
        try await settle(window)
        let search = try XCTUnwrap(searchController.universalSearchViewController)
        search.restoresKeyboard = false
        searchController.searchToolbar.endEditing()
        let split = try XCTUnwrap(root.children.first as? SplitRootViewController)
        let sidebar = try XCTUnwrap(split.viewController(for: .primary) as? SplitRootSidebarNavigationController)
        let modal = UIViewController()
        modal.modalPresentationStyle = .overFullScreen
        root.present(modal, animated: false)
        window.layoutIfNeeded()
        XCTAssertTrue(sidebar.isSearchVisible)
        search.returnDeadline = ContinuousClock.now.advanced(by: .seconds(-1))
        searchController.expireSearchIfNeeded(search)
        XCTAssertFalse(sidebar.isSearchVisible)
        XCTAssertTrue(root.presentedViewController === modal)
        root.dismiss(animated: false)
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

    @available(iOS 17.0, *)
    private func changeLayout(_ root: AdaptiveRootViewController, to sizeClass: UIUserInterfaceSizeClass) {
        let previous = root.traitCollection
        root.traitOverrides.horizontalSizeClass = sizeClass
        root.traitCollectionDidChange(previous)
    }

    private func navigation(_ root: AdaptiveRootViewController) throws -> WNavigationController {
        if let navigation = root.children.first as? WNavigationController { return navigation }
        let split = try XCTUnwrap(root.children.first as? SplitRootViewController)
        return try XCTUnwrap(split.searchNavigationController)
    }

    private func selectTab(_ tab: AppTabId, in root: AdaptiveRootViewController) {
        if let navigation = root.children.first as? WNavigationController {
            (navigation.viewControllers.first as? TopTabsRootViewController)?.selectTab(tab)
        } else {
            (root.children.first as? SplitRootViewController)?.select(tab: tab)
        }
    }

    private func currentTab(_ root: AdaptiveRootViewController) -> AppTabId? {
        if let navigation = root.children.first as? WNavigationController {
            return (navigation.viewControllers.first as? TopTabsRootViewController)?.currentTabId
        }
        return (root.children.first as? SplitRootViewController)?.currentTabId
    }

    private func opposite(_ sizeClass: UIUserInterfaceSizeClass) -> UIUserInterfaceSizeClass {
        sizeClass == .compact ? .regular : .compact
    }

    private func settle(_ window: UIWindow) async throws {
        // A custom navigation animator can outlive UIView's disabled animations.
        for _ in 0..<30 {
            try await Task.sleep(for: .milliseconds(50))
            window.layoutIfNeeded()
            if let root = window.rootViewController as? AdaptiveRootViewController,
               try navigation(root).transitionCoordinator == nil { return }
        }
        XCTFail("Navigation did not settle")
    }
}
