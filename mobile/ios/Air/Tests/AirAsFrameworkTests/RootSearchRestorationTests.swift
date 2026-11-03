import Dependencies
import GRDB
import UIKit
import XCTest
import UIComponents
import UISettings
import UIUniversalSearch
import WalletContext
@testable import WalletCore
import WalletResources
@testable import AirAsFramework
@testable import UIAgent

@MainActor
final class RootSearchRestorationTests: XCTestCase {
    private var previousTabIds: [AppTabId] = []

    override func invokeTest() {
        withDependencies { $0.context = .live } operation: { super.invokeTest() }
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

    @available(iOS 17.0, *)
    func testClosingSearchCrossfadesPlaceholderAtDestinationWidth() async throws {
        let keys = [ToolbarSettings.accountsKey, ToolbarSettings.scanKey, ToolbarSettings.sharedBackgroundKey]
        let previous = keys.map { ($0, UserDefaults.standard.object(forKey: $0)) }
        defer {
            previous.forEach { UserDefaults.standard.set($0.1, forKey: $0.0) }
            ToolbarSettings.notifyDidChange()
        }
        keys.forEach { UserDefaults.standard.set(true, forKey: $0) }
        let (root, window) = host(.compact)
        defer { window.isHidden = true }
        window.frame.size.width = 402
        let controller = root.searchController
        let toolbar = controller.searchToolbar
        toolbar.configuration = .init(placeholder: "Искать или спросить", shortPlaceholder: "Поиск", showsMicrophone: false)
        try await settle(window)
        UIView.setAnimationsEnabled(true)
        controller.openSearch()
        try await settle(window)

        func textField(in view: UIView) -> UITextField? {
            (view as? UITextField) ?? view.subviews.lazy.compactMap { textField(in: $0) }.first
        }
        let field = try XCTUnwrap(textField(in: toolbar))
        let labels = field.subviews.flatMap(\.subviews).compactMap { $0 as? UILabel }
        let full = try XCTUnwrap(labels.first { $0.attributedText?.string == "Искать или спросить" }?.superview)
        let short = try XCTUnwrap(labels.first { $0.attributedText?.string == "Поиск" }?.superview)
        XCTAssertEqual(field.attributedPlaceholder?.string, "Искать или спросить")

        controller.closeSearch()
        try await Task.sleep(for: .milliseconds(100))
        let fullOpacity = try XCTUnwrap(full.layer.presentation()?.opacity)
        let shortOpacity = try XCTUnwrap(short.layer.presentation()?.opacity)
        XCTAssertGreaterThan(fullOpacity, 0.01)
        XCTAssertLessThan(fullOpacity, 0.99)
        XCTAssertGreaterThan(shortOpacity, 0.01)
        XCTAssertLessThan(shortOpacity, 0.99)
        try await settle(window)
        XCTAssertEqual(field.attributedPlaceholder?.string, "Поиск")
        XCTAssertEqual(full.alpha, 0)
        XCTAssertEqual(short.alpha, 1)
    }

    @available(iOS 17.0, *)
    func testToolbarPreferencesSurviveIPadWindowLayoutAndSearchChanges() async throws {
        let keys = [ToolbarSettings.accountsKey, ToolbarSettings.scanKey, ToolbarSettings.sharedBackgroundKey]
        let previous = keys.map { ($0, UserDefaults.standard.object(forKey: $0)) }
        defer {
            previous.forEach { UserDefaults.standard.set($0.1, forKey: $0.0) }
            ToolbarSettings.notifyDidChange()
        }
        keys.forEach { UserDefaults.standard.set(true, forKey: $0) }
        let (root, window) = host(.regular)
        defer { window.isHidden = true }
        let controller = root.searchController
        let toolbar = controller.searchToolbar
        for shared in [true, false] {
            UserDefaults.standard.set(shared, forKey: ToolbarSettings.sharedBackgroundKey)
            ToolbarSettings.notifyDidChange()
            for sizeClass: UIUserInterfaceSizeClass in [.regular, .compact, .regular] {
                window.frame.size.width = sizeClass == .regular ? 1024 : 500
                changeLayout(root, to: sizeClass)
                try await settle(window)
                let scan = try XCTUnwrap(toolbar.scanButtonPresentationSourceView)
                XCTAssertFalse(toolbar.accountsButton.isHidden)
                XCTAssertEqual(toolbar.homeConfiguration, .init(showsAccounts: true, showsScan: true, sharesBackground: shared))
                for control in [toolbar.searchButtonPresentationSourceView, toolbar.accountsButton, scan, toolbar.trailingButtonView] {
                    XCTAssertTrue(toolbar.bounds.contains(control.convert(control.bounds, to: toolbar)))
                }
                controller.openSearch()
                try await settle(window)
                XCTAssertNil(toolbar.scanButtonPresentationSourceView)
                controller.closeSearch()
                try await settle(window)
                XCTAssertTrue(toolbar.scanButtonPresentationSourceView === scan)
                XCTAssertFalse(toolbar.accountsButton.isHidden)
            }
        }
    }

    @available(iOS 17.0, *)
    func testActiveSearchAndQuerySurviveBothLayoutDirections() async throws {
        for (initial, tab) in [UIUserInterfaceSizeClass.compact, .regular].flatMap({ sizeClass in
            [AppTabId.wallet, .market, .agent, .explore].map { (sizeClass, $0) }
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
            // As wide as a chat's composer row at most, on every tab, so the Agent's field lands on the composer at its
            // width
            let maximumWidth = AgentListBottomBar.getMaximumToolbarWidth(sideInset: 28)
            XCTAssertEqual(frame.width, min(maximumWidth, contentPanel.width - 56), accuracy: 0.5)
            XCTAssertLessThanOrEqual(frame.width, maximumWidth + 0.5)
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

    func testAgentIsAnOptionalDefaultTabIncludingSavedOrders() {
        let tabs = AppTabManager.shared
        XCTAssertEqual(AppTabManager.defaultTabIds, [.wallet, .market, .agent, .explore, .settings])
        XCTAssertTrue(tabs.registeredTabIds.contains(.agent))
        XCTAssertFalse(AppTabId.agent.isRequired)
        XCTAssertEqual(tabs.validatedTabOrder(from: ["market", "agent", "wallet", "settings"]),
                       [.market, .agent, .wallet, .settings])
        XCTAssertEqual(tabs.validatedTabOrder(from: ["market", "wallet", "settings"]),
                       [.market, .wallet, .settings])
        XCTAssertEqual(tabs.validatedTabOrder(from: ["agent", "agent", "wallet", "unknown", "settings"]),
                       [.agent, .wallet, .settings])
    }

    @available(iOS 17.0, *)
    func testAgentRootToolbarFollowsConsentInBothLayouts() async throws {
        for (initial, hasConsent) in [(UIUserInterfaceSizeClass.compact, false), (.regular, false), (.compact, true), (.regular, true)] {
            let (root, window) = host(initial)
            defer { window.isHidden = true }
            var didLoadConsent = false
            installAgentList(in: root, hasConsent: hasConsent, loadConsent: {
                didLoadConsent = true
                return hasConsent
            })
            selectTab(.agent, in: root)
            try await settle(window)

            let navigation = try navigation(root)
            let list: AgentThreadListVC
            if let compact = navigation.viewControllers.first as? TopTabsRootViewController {
                list = try XCTUnwrap(compact.visibleContentProviderViewController as? AgentThreadListVC)
            } else {
                list = try XCTUnwrap(navigation.viewControllers.first as? AgentThreadListVC)
            }
            list.loadViewIfNeeded()
            try await waitUntil(window) { didLoadConsent && list.isConsentRequired == !hasConsent }
            XCTAssertEqual(currentTab(root), .agent)
            // Consent replaces the toolbar; an allowed Agent hosts its question field on it.
            XCTAssertEqual(list.additionalSafeAreaInsets.bottom, hasConsent ? 64 : 0)
            XCTAssertEqual(root.searchController.searchToolbar.presentation, hasConsent ? .homeToolbar : .empty)
            XCTAssertTrue(list.bottomBar.isDescendant(of: window))
            XCTAssertFalse(list.bottomBar.isDescendant(of: list.view))
            XCTAssertEqual(list.bottomBar.isHidden, !hasConsent)
        }
    }

    @available(iOS 17.0, *)
    func testAgentKeepsToolbarAndInsetsWhileConsentIsUnknown() async throws {
        for initial in [UIUserInterfaceSizeClass.compact, .regular] {
            for hasConsent in [true, false] {
                let (root, window) = host(initial)
                defer { window.isHidden = true }
                var response: CheckedContinuation<Bool, Never>?
                var hasReturnedConsent = false
                defer { response?.resume(returning: hasConsent) }
                installAgentList(in: root, hasConsent: hasConsent, loadConsent: {
                    let consent = await withCheckedContinuation { response = $0 }
                    hasReturnedConsent = true
                    return consent
                })
                selectTab(.agent, in: root)
                try await settle(window)

                let navigation = try navigation(root)
                let list: AgentThreadListVC
                if let compact = navigation.viewControllers.first as? TopTabsRootViewController {
                    list = try XCTUnwrap(compact.visibleContentProviderViewController as? AgentThreadListVC)
                } else {
                    list = try XCTUnwrap(navigation.viewControllers.first as? AgentThreadListVC)
                }
                list.loadViewIfNeeded()
                try await waitUntil(window) { response != nil }
                let resolveConsent = try XCTUnwrap(response)
                XCTAssertFalse(list.isConsentRequired)
                XCTAssertEqual(list.additionalSafeAreaInsets.bottom, 64)
                XCTAssertEqual(root.searchController.searchToolbar.presentation, .homeToolbar)
                XCTAssertFalse(list.bottomBar.isHidden)

                resolveConsent.resume(returning: hasConsent)
                response = nil
                try await waitUntil(window) { hasReturnedConsent && list.isConsentRequired == !hasConsent }
                try await settle(window)
                XCTAssertEqual(list.isConsentRequired, !hasConsent)
                XCTAssertEqual(list.additionalSafeAreaInsets.bottom, hasConsent ? 64 : 0)
                XCTAssertEqual(root.searchController.searchToolbar.presentation, hasConsent ? .homeToolbar : .empty)
                XCTAssertEqual(list.bottomBar.isHidden, !hasConsent)
            }
        }
    }

    @available(iOS 17.0, *)
    func testOpeningNewsKeepsEmptyListSuggestionsInPlaceThroughPushAndPop() async throws {
        try XCTSkipIf(UIAccessibility.isReduceMotionEnabled, "This checks UIKit navigation in motion")
        let (root, window) = host(.compact)
        defer { window.isHidden = true }
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window.windowScene = scene
            window.frame = scene.coordinateSpace.bounds
            window.makeKeyAndVisible()
        } else {
            window.frame.size = CGSize(width: 402, height: 874)
        }
        let hints = ["What can you do?", "How swaps work", "What is staking", "Wallet security"].enumerated().map {
            AgentHint(id: "hint:\($0.offset)", title: $0.element, subtitle: "", prompt: $0.element)
        }
        installAgentList(in: root, hasConsent: true, suggestions: hints)
        selectTab(.agent, in: root)
        try await settle(window)
        let navigation = try navigation(root)
        let tabs = try XCTUnwrap(navigation.viewControllers.first as? TopTabsRootViewController)
        let list = try XCTUnwrap(tabs.visibleContentProviderViewController as? AgentThreadListVC)
        let suggestions = try XCTUnwrap(findView(in: list.view, accessibilityIdentifier: "agent_suggestions"))
        let collection = try XCTUnwrap(findView(in: list.view, accessibilityIdentifier: "AgentThreadList") as? UICollectionView)
        for _ in 0..<50 where suggestions.isHidden || suggestions.bounds.height == 0 || collection.numberOfSections == 0 {
            try await Task.sleep(for: .milliseconds(20))
            window.layoutIfNeeded()
        }
        XCTAssertFalse(suggestions.isHidden)
        XCTAssertGreaterThan(suggestions.bounds.height, 100)
        XCTAssertEqual(collection.numberOfItems(inSection: 0), 1)
        XCTAssertFalse(list.bottomBar.isDescendant(of: list.view), "The real root owns the list's question field")
        let restingBottomInset = list.view.bounds.maxY - suggestions.frame.maxY
        UIView.setAnimationsEnabled(true)

        func sampleTransition(_ name: String) async throws {
            var maximumDrift: CGFloat = 0
            var sampleCount = 0
            var image: UIImage?
            let deadline = ContinuousClock.now.advanced(by: .seconds(3))
            while navigation.transitionCoordinator != nil, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(16))
                window.layoutIfNeeded()
                guard suggestions.window === window else { continue }
                let shown = suggestions.convertAsShown(to: list.view)
                let bounds = list.view.layer.presentation()?.bounds ?? list.view.bounds
                let drift = abs(bounds.maxY - shown.maxY - restingBottomInset)
                maximumDrift = max(maximumDrift, drift)
                sampleCount += 1
                if sampleCount == 6 {
                    image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
                        window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
                    }
                }
            }
            XCTAssertNil(navigation.transitionCoordinator, "Navigation must finish")
            XCTAssertGreaterThan(sampleCount, 2, "The test must inspect the moving screen")
            XCTAssertLessThanOrEqual(maximumDrift, 1, "\(name): suggestions moved vertically inside the departing list")
            if let image {
                let attachment = XCTAttachment(image: image)
                attachment.name = "\(name) — suggestions keep their place in the moving list"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }

        for attempt in 1...2 {
            list.collectionView(collection, didSelectItemAt: IndexPath(item: 0, section: 0))
            XCTAssertTrue(navigation.topViewController is AgentNewsFeedVC)
            try await sampleTransition("News push \(attempt)")
            navigation.popViewController(animated: true)
            try await sampleTransition("News pop \(attempt)")
            try await settle(window)
            XCTAssertEqual(suggestions.frame.maxY, list.bottomBar.convert(list.bottomBar.bounds, to: list.view).minY - 26,
                           accuracy: 0.5, "Returning to the list restores its spacing above the field")
        }
    }

    func testDeletingTheTopChatRestoresTheAgentToolbar() async throws {
        for initial: UIUserInterfaceSizeClass in [.compact, .regular] {
            let (root, window) = host(initial)
            defer { window.isHidden = true }
            installAgentList(in: root, hasConsent: true)
            selectTab(.agent, in: root)
            try await settle(window)
            let navigation = try navigation(root)
            let chat = AgentEntryPoint.makeNewChatViewController(query: "Test deletion")
            XCTAssertTrue(chat is AgentVC)
            navigation.pushViewController(chat, animated: true)
            try await settle(window)
            AgentEntryPoint.removeDeletedChat(chat, animated: true)
            try await Task.sleep(for: .milliseconds(20))
            try await settle(window)
            XCTAssertEqual(navigation.viewControllers.count, 1)
            XCTAssertEqual(root.searchController.searchToolbar.presentation, .homeToolbar)
            XCTAssertFalse(root.searchController.searchToolbar.isHidden)
            XCTAssertEqual(root.searchController.searchToolbar.alpha, 1)
            var ancestor = root.searchController.searchToolbar.superview
            while let view = ancestor {
                XCTAssertFalse(view.isHidden)
                XCTAssertGreaterThan(view.alpha, 0.01)
                ancestor = view.superview
            }
        }
    }

    @available(iOS 17.0, *)
    func testExternalQuestionOpensNewChatInAgentTabNavigation() async throws {
        for initial: UIUserInterfaceSizeClass in [.compact, .regular] {
            let (root, window) = host(initial)
            defer { window.isHidden = true }
            selectTab(.market, in: root)
            try await settle(window)

            if let compact = try navigation(root).viewControllers.first as? TopTabsRootViewController {
                compact.showAgent(query: "Explain this token", entryPoint: nil)
            } else {
                let split = try XCTUnwrap(root.children.first as? SplitRootViewController)
                split.showAgent(query: "Explain this token", entryPoint: nil)
            }
            try await settle(window)

            let agentNavigation = try navigation(root)
            XCTAssertEqual(currentTab(root), .agent)
            XCTAssertEqual(agentNavigation.viewControllers.count, 2)
            XCTAssertTrue(agentNavigation.topViewController is AgentVC)
            agentNavigation.popViewController(animated: false)
            try await settle(window)
            if let compact = agentNavigation.viewControllers.first as? TopTabsRootViewController {
                XCTAssertTrue(compact.visibleContentProviderViewController is AgentThreadListVC)
            } else {
                XCTAssertTrue(agentNavigation.topViewController is AgentThreadListVC)
            }
        }
    }

    @available(iOS 17.0, *)
    func testHiddenAgentTabOpensNewChatInCurrentNavigation() async throws {
        let tabs = AppTabManager.shared
        tabs.setTabIds([.wallet, .market, .explore, .settings])
        XCTAssertFalse(tabs.contains(.agent))
        XCTAssertEqual(AppStorageHelper.appTabOrder, ["wallet", "market", "explore", "settings"])

        for hasSearch in [false, true] {
            for query: String? in ["Explain this token", nil] {
                let (root, window) = host(.regular)
                defer { window.isHidden = true }
                selectTab(.market, in: root)
                try await settle(window)
                let split = try XCTUnwrap(root.children.first as? SplitRootViewController)
                let navigation = try navigation(root)
                let detail = UIViewController()
                navigation.pushViewController(detail, animated: false)
                try await settle(window)
                if hasSearch {
                    root.searchController.openSearch()
                    try await settle(window)
                    let search = try XCTUnwrap(root.searchController.universalSearchViewController)
                    search.restoresKeyboard = false
                    root.searchController.searchToolbar.endEditing()
                    XCTAssertTrue(navigation.topViewController === search)
                }
                let search = root.searchController.universalSearchViewController
                let originalStack = navigation.viewControllers

                split.showAgent(query: query, entryPoint: query.map { .globalSearch(query: $0) })
                try await settle(window)

                XCTAssertEqual(currentTab(root), .market)
                XCTAssertTrue(split.searchNavigationController === navigation)
                XCTAssertTrue(navigation.viewControllers.dropLast().elementsEqual(originalStack, by: { $0 === $1 }))
                XCTAssertEqual(navigation.viewControllers.count, originalStack.count + 1)
                if query != nil {
                    XCTAssertTrue(navigation.topViewController is AgentVC)
                } else {
                    XCTAssertTrue(navigation.topViewController is AgentRootVC)
                }
                XCTAssertTrue(root.searchController.universalSearchViewController === search)
                XCTAssertFalse(root.searchController.isSearchVisible)
                navigation.popViewController(animated: false)
                try await settle(window)
                XCTAssertTrue(navigation.topViewController === originalStack.last)
                XCTAssertEqual(root.searchController.isSearchVisible, hasSearch)
            }
        }
    }

    @available(iOS 17.0, *)
    func testHiddenAgentListSelectsVisibleTabAcrossLayoutChanges() async throws {
        AppTabManager.shared.setTabIds([.wallet, .market, .explore, .settings])
        let (root, window) = host(.compact)
        defer { window.isHidden = true }

        for _ in 0..<2 {
            selectTab(.agent, in: root)
            try await settle(window)
            XCTAssertEqual(currentTab(root), .agent)
            XCTAssertEqual(try navigation(root).viewControllers.count, 1)

            changeLayout(root, to: .regular)
            try await settle(window)
            let split = try XCTUnwrap(root.children.first as? SplitRootViewController)
            XCTAssertEqual(currentTab(root), .wallet)
            XCTAssertTrue(split.searchNavigationController === (try navigation(root)))
            XCTAssertTrue(split.isHomeRootSelected())
            XCTAssertEqual(try navigation(root).viewControllers.count, 1)

            changeLayout(root, to: .compact)
            try await settle(window)
            XCTAssertEqual(currentTab(root), .wallet)
            XCTAssertEqual(try navigation(root).viewControllers.count, 1)
        }
    }

    @available(iOS 17.0, *)
    func testHiddenAgentChatPreservesVisibleBackStackAndSearchAcrossLayoutChanges() async throws {
        AppTabManager.shared.setTabIds([.wallet, .market, .explore, .settings])
        let thread = try JSONDecoder().decode(ApiAgentV2ThreadSummary.self, from: Data(#"""
        {"id":"hidden-agent-thread","revision":2,"title":"Hidden chat","createdAt":"2026-10-01T00:00:00.000Z","updatedAt":"2026-10-02T00:00:00.000Z","lastActivityAt":"2026-10-02T00:00:00.000Z","messageCount":2}
        """#.utf8))

        let scenarios: [(hasSearch: Bool, visibleTab: AppTabId)] = [
            (false, .wallet),
            (true, .wallet),
            (false, .market),
        ]
        for (hasSearch, visibleTab) in scenarios {
            let (root, window) = host(.compact)
            defer { window.isHidden = true }
            selectTab(visibleTab, in: root)
            try await settle(window)
            let detail = UIViewController()
            try navigation(root).pushViewController(detail, animated: false)
            try await settle(window)
            selectTab(.agent, in: root)
            try await settle(window)
            if hasSearch {
                root.searchController.openSearch()
                try await settle(window)
                root.searchController.universalSearchViewController?.restoresKeyboard = false
                root.searchController.searchToolbar.endEditing()
                root.searchController.searchToolbar.onTextChange?("ton")
            }
            let search = root.searchController.universalSearchViewController
            let chat = AgentEntryPoint.makeRootViewController(thread: thread)
            if hasSearch {
                XCTAssertTrue(root.searchController.pushFromSearch(chat))
            } else {
                try navigation(root).pushViewController(chat, animated: false)
            }
            try await settle(window)
            if visibleTab != .wallet {
                selectTab(visibleTab, in: root)
                try await settle(window)
            }
            let deadline = search?.returnDeadline
            var expectedPath: [UIViewController] = [detail]
            if let search { expectedPath.append(search) }
            expectedPath.append(chat)

            for sizeClass: UIUserInterfaceSizeClass in [.regular, .compact, .regular, .compact] {
                changeLayout(root, to: sizeClass)
                try await settle(window)
                let navigation = try navigation(root)
                XCTAssertEqual(currentTab(root), visibleTab)
                XCTAssertTrue(navigation.topViewController === chat)
                XCTAssertTrue(navigation.viewControllers.dropFirst().elementsEqual(expectedPath, by: { $0 === $1 }))
                XCTAssertTrue(root.searchController.universalSearchViewController === search)
                XCTAssertEqual(search?.returnDeadline, deadline)
                if let split = root.children.first as? SplitRootViewController {
                    XCTAssertTrue(split.searchNavigationController === navigation)
                }
            }

            try navigation(root).popViewController(animated: false)
            try await settle(window)
            if hasSearch {
                XCTAssertTrue(root.searchController.isSearchVisible)
                XCTAssertEqual(search?.fieldConfiguration.text, "ton")
                root.searchController.closeSearch()
                try await settle(window)
            }
            XCTAssertTrue(try navigation(root).topViewController === detail)
            try navigation(root).popViewController(animated: false)
            try await settle(window)
            XCTAssertEqual(try navigation(root).viewControllers.count, 1)
        }
    }

    @available(iOS 17.0, *)
    func testSelectingAgentThreadPushesChatAboveSearch() async throws {
        let thread = try JSONDecoder().decode(ApiAgentV2ThreadSummary.self, from: Data(#"""
        {"id":"selected-thread","revision":2,"title":"Selected chat","createdAt":"2026-10-01T00:00:00.000Z","updatedAt":"2026-10-02T00:00:00.000Z","lastActivityAt":"2026-10-02T00:00:00.000Z","messageCount":2}
        """#.utf8))
        for initial: UIUserInterfaceSizeClass in [.compact, .regular] {
            let (root, window) = host(initial)
            defer { window.isHidden = true }
            let toolbar = root.searchController
            toolbar.openSearch()
            try await settle(window)
            let search = try XCTUnwrap(toolbar.universalSearchViewController)
            search.restoresKeyboard = false

            search.session.onSelectRoute?(.agentThread(thread))
            try await settle(window)

            let navigation = try navigation(root)
            XCTAssertTrue(navigation.topViewController is AgentRootVC)
            XCTAssertTrue(navigation.viewControllers.dropLast().last === search)
            XCTAssertFalse(toolbar.isSearchVisible)
            navigation.popViewController(animated: false)
            try await settle(window)
            XCTAssertTrue(toolbar.isSearchVisible)
        }
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

    @available(iOS 27.1, *)
    func testDuoNavigationPlacementPreservesSplitSidebarAndSearchStack() async throws {
        let key = DuoNavigationSettings.userDefaultsKey
        let previous = UserDefaults.standard.object(forKey: key)
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
            DuoNavigationSettings.notifyDidChange()
        }
        UserDefaults.standard.set(DuoNavigationSettings.Placement.sidebar.rawValue, forKey: key)
        let (root, window) = host(.regular)
        defer { window.isHidden = true }
        selectTab(.market, in: root)
        try await settle(window)
        let split = try XCTUnwrap(root.children.first as? SplitRootViewController)
        let sidebar = try XCTUnwrap(split.viewController(for: .primary))
        let navigation = try navigation(root)
        let market = try XCTUnwrap(navigation.viewControllers.first)
        root.searchController.openSearch()
        try await settle(window)
        let search = try XCTUnwrap(root.searchController.universalSearchViewController)
        search.restoresKeyboard = false
        root.searchController.searchToolbar.endEditing()
        root.searchController.searchToolbar.onTextChange?("ton")

        for placement in [DuoNavigationSettings.Placement.toolbar, .sidebar] {
            UserDefaults.standard.set(placement.rawValue, forKey: key)
            DuoNavigationSettings.notifyDidChange()
            try await settle(window)
            XCTAssertTrue(root.children.first === split)
            XCTAssertTrue(split.viewController(for: .primary) === sidebar)
            XCTAssertTrue(split.searchNavigationController === navigation)
            XCTAssertTrue(navigation.viewControllers.first === market)
            XCTAssertTrue(navigation.topViewController === search)
            XCTAssertEqual(search.fieldConfiguration.text, "ton")
            XCTAssertEqual(split.currentTabId, .market)
        }
    }

    @available(iOS 17.0, *)
    private func installAgentList(
        in root: AdaptiveRootViewController,
        hasConsent: Bool,
        suggestions: [AgentHint] = [],
        loadConsent: (() async throws -> Bool)? = nil
    ) {
        let client = RootAgentListClient()
        let list = AgentThreadListVC(
            model: AgentThreadListModel(client: client, newsClient: client),
            loadConsent: loadConsent ?? { hasConsent },
            acceptConsent: {},
            loadSuggestions: { suggestions }
        )
        if let navigation = root.children.first as? WNavigationController,
           let compact = navigation.viewControllers.first as? TopTabsRootViewController {
            compact.setNavigationStack([list], for: .agent)
        } else if let split = root.children.first as? SplitRootViewController {
            split.setNavigationStack([list], for: .agent)
        } else {
            XCTFail("Missing root navigation")
        }
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

    private func findView(in view: UIView?, accessibilityIdentifier: String) -> UIView? {
        guard let view else { return nil }
        if view.accessibilityIdentifier == accessibilityIdentifier { return view }
        return view.subviews.lazy.compactMap {
            self.findView(in: $0, accessibilityIdentifier: accessibilityIdentifier)
        }.first
    }

    private func waitUntil(_ window: UIWindow, condition: () -> Bool) async throws {
        for _ in 0..<100 {
            window.layoutIfNeeded()
            if condition() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTFail("The consent lookup did not reach the expected state")
    }

    private func settle(_ window: UIWindow) async throws {
        // A custom navigation animator can outlive UIView's disabled animations.
        for _ in 0..<30 {
            try await Task.sleep(for: .milliseconds(50))
            window.layoutIfNeeded()
            if let root = window.rootViewController as? AdaptiveRootViewController {
                let navigation = try navigation(root)
                if navigation.transitionCoordinator == nil, navigation.delegate === navigation { return }
            }
        }
        XCTFail("Navigation did not settle")
    }
}

@MainActor
private final class RootAgentListClient: AgentThreadListClient, AgentNewsFeedClient {
    func listThreads(cursor: String?, limit: Int?, query: String?) async throws -> ApiAgentV2ThreadListResponse {
        .init(protocolVersion: 3, threads: [], nextCursor: nil)
    }

    func getNewsFeed(lang: String, cursor: String?) async throws -> ApiAgentV2NewsFeedPage {
        .init(locale: lang, items: [])
    }

    func updateThread(id: String, update: ApiAgentV2ThreadUpdate) async throws -> ApiAgentV2ThreadUpdateResponse {
        XCTFail("Unexpected thread update")
        throw CancellationError()
    }

    func deleteThread(id: String) async throws -> ApiAgentV2ThreadDeleteResponse {
        XCTFail("Unexpected thread deletion")
        throw CancellationError()
    }
}
