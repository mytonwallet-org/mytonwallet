import ContextMenuKit
import Dependencies
import GRDB
import UIKit
import XCTest
import UIComponents
import UIReceive
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
    func testBothLayoutsOpenOnTheFirstTabInTheUserOrder() async throws {
        AppTabManager.shared.setTabIds([.market, .wallet, .agent, .explore, .settings])
        for sizeClass in [UIUserInterfaceSizeClass.compact, .regular] {
            let (root, window) = host(sizeClass)
            try await settle(window)
            XCTAssertEqual(currentTab(root), .market)
            window.isHidden = true
        }
    }

    /// The sidebar the split layout shows, on an iPad and on a large iPhone in landscape, reorders the tabs with
    /// the collection view's interactive movement
    @available(iOS 17.0, *)
    func testDraggingSidebarTabsToTheFirstAndLastPlacesReordersTheTabs() async throws {
        let (root, window) = host(.regular)
        defer { window.isHidden = true }
        try await settle(window)
        let split = try XCTUnwrap(root.children.first as? SplitRootViewController)
        let navigation = try XCTUnwrap(split.viewController(for: .primary) as? SplitRootSidebarNavigationController)
        let sidebar = try XCTUnwrap(navigation.viewControllers.first as? SplitRootSidebarViewController)
        let collectionView = try XCTUnwrap(
            findDescendants(of: sidebar.view).lazy.compactMap { $0 as? UICollectionView }.first { $0.delegate === sidebar }
        )
        let tabIds = AppTabManager.shared.orderedTabIds.filter { !sidebar.hiddenTabIds.contains($0) }
        XCTAssertEqual(tabIds, AppTabManager.defaultTabIds)
        // No other section of the sidebar has as many rows as the tabs
        let section = try XCTUnwrap((0..<collectionView.numberOfSections).first {
            collectionView.numberOfItems(inSection: $0) == tabIds.count
        })

        func drag(from sourceItem: Int, to destinationItem: Int) async throws {
            let destination = try XCTUnwrap(
                collectionView.layoutAttributesForItem(at: IndexPath(item: destinationItem, section: section))
            )
            XCTAssertTrue(collectionView.beginInteractiveMovementForItem(at: IndexPath(item: sourceItem, section: section)))
            collectionView.updateInteractiveMovementTargetPosition(
                CGPoint(x: collectionView.bounds.midX, y: destination.center.y)
            )
            collectionView.endInteractiveMovement()
            try await settle(window)
        }

        try await drag(from: 1, to: tabIds.count - 1)
        XCTAssertEqual(AppTabManager.shared.orderedTabIds, [.wallet, .agent, .explore, .settings, .market])
        try await drag(from: tabIds.count - 1, to: 0)
        XCTAssertEqual(AppTabManager.shared.orderedTabIds, [.market, .wallet, .agent, .explore, .settings])
        XCTAssertEqual(collectionView.numberOfItems(inSection: section), tabIds.count)
    }

    @available(iOS 17.0, *)
    func testAgentRootToolbarHostsTheQuestionFieldWithOrWithoutConsentInBothLayouts() async throws {
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
            try await waitUntil(window) { didLoadConsent }
            try await settle(window)
            XCTAssertEqual(currentTab(root), .agent)
            // With consent or without, the Agent hosts its question field on the toolbar; the first question asks
            XCTAssertEqual(list.additionalSafeAreaInsets.bottom, 64)
            XCTAssertEqual(root.searchController.searchToolbar.presentation, .homeToolbar)
            XCTAssertTrue(list.bottomBar.isDescendant(of: window))
            XCTAssertFalse(list.bottomBar.isDescendant(of: list.view))
            XCTAssertFalse(list.bottomBar.isHidden)
        }
    }

    func testAgentBarStaysVisibleWhileTabMenuDismisses() {
        let host = AgentBarHost()
        let root = host.navigation.viewControllers[0]
        let toolbar = UniversalSearchFieldView(configuration: .init(placeholder: "Search"))
        host.agentBarHostView.addSubview(toolbar)
        let controller = RootAgentBarController(host: host, searchToolbar: toolbar, containerView: host.agentBarHostView)
        let bar = AgentListBottomBar()
        controller.install(bar)
        controller.setMorphProgress(1)
        XCTAssertFalse(bar.isHidden)
        XCTAssertEqual(bar.alpha, 1)

        for style in [UIModalPresentationStyle.popover, .pageSheet, .custom] {
            let coordinator = AgentBarTransitionCoordinator(style: style, from: UIViewController(), to: host.navigation)
            host.navigation.stubTransitionCoordinator = coordinator
            controller.updateForNavigation(showing: root, isShowingRoot: true, in: host.navigation)
            XCTAssertFalse(bar.isHidden)
            XCTAssertEqual(bar.alpha, 1, "Dismissing a modal must not restart the Agent field's appearance")
            coordinator.completeTransition()
            XCTAssertEqual(coordinator.animationCount, 0)
            XCTAssertFalse(bar.isHidden)
            XCTAssertEqual(bar.alpha, 1)
        }

        let pop = AgentBarTransitionCoordinator(style: .none, from: UIViewController(), to: root)
        host.navigation.stubTransitionCoordinator = pop
        controller.updateForNavigation(showing: root, isShowingRoot: true, in: host.navigation)
        XCTAssertEqual(bar.alpha, 0, "A navigation pop still carries the field back onto the root")
        pop.completeTransition()
        XCTAssertEqual(pop.animationCount, 1)
        XCTAssertFalse(bar.isHidden)
        XCTAssertEqual(bar.alpha, 1)
    }

    /// Back from a chat whose composer rides the keyboard, as a swipe back while typing goes, the chat keeps its
    /// composer, above the keyboard that leaves with it, and the list's field comes in at the bottom with the pop. A chat
    /// whose composer rests at the bottom hands it over to the list's field.
    func testChatComposerOnTheKeyboardStaysWithTheChatGoingBack() {
        for isOnKeyboard in [true, false] {
            let host = AgentBarHost()
            let root = host.navigation.viewControllers[0]
            let toolbar = UniversalSearchFieldView(configuration: .init(placeholder: "Search"))
            host.agentBarHostView.addSubview(toolbar)
            let controller = RootAgentBarController(host: host, searchToolbar: toolbar, containerView: host.agentBarHostView)
            let bar = AgentListBottomBar()
            controller.install(bar)
            controller.setMorphProgress(1)
            let chat = AgentBarHandoffChat(isComposerOnKeyboard: isOnKeyboard)
            let pop = AgentBarTransitionCoordinator(style: .none, from: chat, to: root)
            host.navigation.stubTransitionCoordinator = pop
            controller.updateForNavigation(showing: root, isShowingRoot: true, in: host.navigation)
            XCTAssertEqual(chat.hiddenStates, isOnKeyboard ? [] : [true], "On the keyboard: \(isOnKeyboard)")
            XCTAssertEqual(bar.alpha, isOnKeyboard ? 0 : 1, "The list's field comes in with the pop")
            pop.completeTransition()
            XCTAssertFalse(bar.isHidden)
            XCTAssertEqual(bar.alpha, 1)
            if isOnKeyboard {
                XCTAssertTrue(chat.hiddenStates.allSatisfy { !$0 }, "The chat's composer never hides")
            }
        }
    }

    /// While the Agent list's field holds a question, the search circle waits away past the leading edge and the field
    /// is wide over its place; once the field is empty again, they come back
    func testSearchCircleStaysAwayWhileTheAgentFieldHoldsAQuestion() async throws {
        let host = AgentBarHost()
        let toolbar = UniversalSearchFieldView(configuration: .init(placeholder: "Search"))
        toolbar.frame = CGRect(x: 16, y: 780, width: 358, height: AgentListBottomBar.height)
        host.agentBarHostView.addSubview(toolbar)
        let controller = RootAgentBarController(host: host, searchToolbar: toolbar, containerView: host.agentBarHostView)
        let bar = AgentListBottomBar()
        controller.install(bar)
        controller.setMorphProgress(1)
        let circle = toolbar.searchButtonPresentationSourceView
        XCTAssertFalse(bar.hasQuestion)
        XCTAssertEqual(bar.expansion, 0)
        XCTAssertEqual(circle.transform, .identity)

        bar.composerView.setDraftText("Раз, два, три", focus: false)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(bar.hasQuestion)
        XCTAssertEqual(bar.expansion, 1, "The field is wide over the circle's place")
        XCTAssertLessThan(circle.transform.tx, -(toolbar.frame.minX + AgentListBottomBar.height), "The circle is away")

        bar.composerView.setDraftText(" \n", focus: false)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(bar.hasQuestion, "Blank text holds no question")
        XCTAssertEqual(bar.expansion, 0)
        XCTAssertEqual(circle.transform, .identity)
    }

    /// Asking the Agent from search switches to the Agent tab and pushes the new chat at once: the bar's fold is still
    /// springing once the chat's composer has taken the field's place, and its late frames leave the search circle away
    /// instead of over the composer
    func testFoldFramesUnderAChatLeaveTheSearchCircleAway() {
        let host = AgentBarHost()
        let toolbar = UniversalSearchFieldView(configuration: .init(placeholder: "Search"))
        toolbar.frame = CGRect(x: 16, y: 780, width: 358, height: AgentListBottomBar.height)
        host.agentBarHostView.addSubview(toolbar)
        let controller = RootAgentBarController(host: host, searchToolbar: toolbar, containerView: host.agentBarHostView)
        let bar = AgentListBottomBar()
        controller.install(bar)
        controller.setMorphProgress(1)
        let chat = AgentBarHandoffChat(isComposerOnKeyboard: false)
        host.navigation.setViewControllers([host.navigation.viewControllers[0], chat], animated: false)
        controller.updateForNavigation(showing: chat, isShowingRoot: false, in: host.navigation)
        let circle = toolbar.searchButtonPresentationSourceView
        let awayOffset = -(toolbar.frame.minX + AgentListBottomBar.height)
        XCTAssertLessThan(circle.transform.tx, awayOffset, "The push sends the circle away")

        for progress: CGFloat in [0.6, 0.95, 1.04, 1] {
            bar.onMorphFrame?(progress)
            XCTAssertLessThan(circle.transform.tx, awayOffset, "A fold frame at \(progress) keeps the circle away")
        }
    }

    /// A touch on the Agent list's microphone moves nothing until it is a tap or a hold; a hold then sends the search
    /// circle away as any question does
    func testSearchCircleStaysPutUntilTheMicrophoneTouchIsATapOrAHold() async throws {
        let host = AgentBarHost()
        let toolbar = UniversalSearchFieldView(configuration: .init(placeholder: "Search"))
        toolbar.frame = CGRect(x: 16, y: 780, width: 358, height: AgentListBottomBar.height)
        host.agentBarHostView.addSubview(toolbar)
        let controller = RootAgentBarController(host: host, searchToolbar: toolbar, containerView: host.agentBarHostView)
        let bar = AgentListBottomBar()
        controller.install(bar)
        controller.setMorphProgress(1)
        let scheduler = AgentBarDictationScheduler()
        let dictation = AgentDictationController(
            scheduler: scheduler,
            requestPermission: { true },
            makeRecorder: { AgentBarDictationRecorder() },
            transcribe: { _ in .init(outcome: .noSpeech) },
            haptic: {},
            gestureFeedback: {},
            failureFeedback: {},
            observeLifecycle: false
        )
        defer { dictation.cancel() }
        bar.composerView.dictationController = dictation
        let circle = toolbar.searchButtonPresentationSourceView

        dictation.touchBegan()
        for _ in 0..<100 where dictation.state.phase != .holding { await Task.yield() }
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(bar.hasQuestion, "Nothing moves for a touch that isn't yet a tap or a hold")
        XCTAssertEqual(circle.transform, .identity)
        scheduler.advance(by: AgentDictationController.tapDuration)
        XCTAssertTrue(dictation.state.isHeld)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(bar.hasQuestion)
        XCTAssertLessThan(circle.transform.tx, -(toolbar.frame.minX + AgentListBottomBar.height), "The circle is away")
        XCTAssertEqual(circle.transform.ty, 0)
    }

    func testTabMenuSelectionDoesNotWaitForNativeDismissalCompletion() throws {
        let account = MAccount(id: "0-mainnet", title: "Menu fixture", type: .view, byChain: [
            .ton: .init(address: "EQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAM9c"),
            .solana: .init(address: "11111111111111111111111111111111"),
        ])
        try withDependencies {
            $0.context = .preview
            $0.accountStore = .makePreview(accounts: [account], selectedAccountId: account.id)
        } operation: {
            func findControl(in view: UIView?) -> WSegmentedControl? {
                guard let view else { return nil }
                if let control = view as? WSegmentedControl { return control }
                return view.subviews.lazy.compactMap { findControl(in: $0) }.first
            }

            let tabs = TopTabsRootViewController()
            let homeNavigation = AgentBarNavigationController(rootViewController: tabs)
            homeNavigation.loadViewIfNeeded()
            tabs.loadViewIfNeeded()
            let homeControl = try XCTUnwrap(findControl(in: tabs.navigationItem.titleView))
            let homeProvider = try XCTUnwrap(homeControl.longPressContextMenuProvider)
            let homeAction = try XCTUnwrap(homeProvider.makeConfiguration().rootPage.items.compactMap { item -> ContextMenuAction? in
                guard case .action(let action) = item, action.id == "tab_menu_market" else { return nil }
                return action
            }.first)
            let homeTransition = AgentBarTransitionCoordinator(style: .popover, from: UIViewController(), to: homeNavigation)
            homeNavigation.stubTransitionCoordinator = homeTransition
            XCTAssertEqual(tabs.currentTabId, .wallet)
            try XCTUnwrap(homeAction.handler)()
            XCTAssertEqual(tabs.currentTabId, .market, "The menu callback already marks dismissal readiness")
            homeTransition.completeTransition()
            XCTAssertEqual(tabs.currentTabId, .market)

            let receive = ReceiveVC(accountContext: AccountContext(accountId: account.id), chain: .ton)
            let fundNavigation = AgentBarNavigationController(rootViewController: receive)
            fundNavigation.loadViewIfNeeded()
            receive.loadViewIfNeeded()
            let fundControl = try XCTUnwrap(findControl(in: receive.navigationItem.titleView))
            let pager = try XCTUnwrap(receive.children.compactMap { $0 as? WPagerViewController }.first)
            let destination = try XCTUnwrap(fundControl.model.items.indices.first { $0 != pager.selectedIndex })
            let fundProvider = try XCTUnwrap(fundControl.longPressContextMenuProvider)
            let fundRow = try XCTUnwrap(fundProvider.makeConfiguration().rootPage.items.compactMap { item -> ContextMenuCustomRow? in
                guard case .custom(let row) = item, row.id == fundControl.model.items[destination].id else { return nil }
                return row
            }.first)
            guard case .selectable(_, _, _, let handler) = fundRow.interaction else {
                XCTFail("A chain menu row must be selectable")
                return
            }
            let fundTransition = AgentBarTransitionCoordinator(style: .popover, from: UIViewController(), to: fundNavigation)
            fundNavigation.stubTransitionCoordinator = fundTransition
            try XCTUnwrap(handler)()
            XCTAssertEqual(pager.selectedIndex, destination, "Fund must switch before UIKit's late completion")
            fundTransition.completeTransition()
            XCTAssertEqual(pager.selectedIndex, destination)
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
                XCTAssertEqual(list.additionalSafeAreaInsets.bottom, 64)
                XCTAssertEqual(root.searchController.searchToolbar.presentation, .homeToolbar)
                XCTAssertFalse(list.bottomBar.isHidden)

                resolveConsent.resume(returning: hasConsent)
                response = nil
                try await waitUntil(window) { hasReturnedConsent }
                try await settle(window)
                XCTAssertEqual(list.additionalSafeAreaInsets.bottom, 64)
                XCTAssertEqual(root.searchController.searchToolbar.presentation, .homeToolbar)
                XCTAssertFalse(list.bottomBar.isHidden)
                XCTAssertNil(window.rootViewController?.presentedViewController, "No consent sheet before a question")
            }
        }
    }

    /// The floating microphone over a dictated question stands above the Agent list's field, out of the root toolbar's
    /// container: a touch reaches it through the window and records on, and the search circle stays away meanwhile
    @available(iOS 17.0, *)
    func testAgentListFloatingMicrophoneTakesTapsAboveTheToolbar() async throws {
        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(true) }
        for initial in [UIUserInterfaceSizeClass.compact, .regular] {
            let (root, window) = host(initial)
            defer { window.isHidden = true }
            installAgentList(in: root, hasConsent: true)
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
            try await waitUntil(window) { !list.bottomBar.hostedGlassViews.isEmpty }

            let scheduler = RootDictationScheduler()
            var recordings = 0
            let dictation = AgentDictationController(
                scheduler: scheduler,
                requestPermission: { true },
                makeRecorder: { RootDictationRecorder() },
                transcribe: { _ in .init(outcome: .transcribed, text: "Раз, два, три") },
                haptic: { recordings += 1 },
                gestureFeedback: {},
                observeLifecycle: false
            )
            defer { dictation.cancel() }
            let composer = list.bottomBar.composerView
            composer.dictationController = dictation
            dictation.onTranscript = { [weak composer] in composer?.revealDictatedText($0) }
            dictation.startHandsFree()
            try await waitUntil(window) { recordings == 1 }
            scheduler.now = 1
            dictation.finish()
            try await waitUntil(window) { dictation.state.phase == .idle }
            XCTAssertTrue(dictation.state.canDictateMore)
            XCTAssertEqual(composer.draftText, "Раз, два, три")
            let resume = try XCTUnwrap(findDescendants(of: list.bottomBar).compactMap { $0 as? UIButton }.first {
                $0.accessibilityLabel == lang("$agent_voice_resume") && !$0.isHidden
            })
            let toolbar = root.searchController.searchToolbar
            let frame = resume.convert(resume.bounds, to: window)
            XCTAssertLessThan(frame.maxY, toolbar.convert(toolbar.bounds, to: window).minY)
            XCTAssertLessThan(toolbar.searchButtonPresentationSourceView.transform.tx, 0, "The search circle is away")
            let center = CGPoint(x: frame.midX, y: frame.midY)
            // The microphone takes the tap, on its glass where it has Liquid Glass
            for point in [center, CGPoint(x: frame.midX, y: frame.maxY - 2)] {
                XCTAssertTrue(
                    window.hitTest(point, with: nil)?.isDescendant(of: resume) == true,
                    "\(initial) layout, a tap at \(point)"
                )
            }

            // A tap on it, through its press, records hands-free
            let touchView = try XCTUnwrap(resume.superview)
            for state in [UIGestureRecognizer.State.began, .ended] {
                touchView.perform(
                    NSSelectorFromString("handleFloatingPress:"),
                    with: RootFloatingMicrophonePress(state: state)
                )
            }
            XCTAssertEqual(dictation.state.phase, .handsFree)
            try await waitUntil(window) { recordings == 2 }
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
    func testHiddenAgentPushLinksOpenTheirTargetsModally() throws {
        AppTabManager.shared.setTabIds([.wallet, .market, .explore, .settings])
        let urls = [
            "https://my.tt/agent?news=307",
            "https://my.tt/agent?digest=en%3A2026-11-08T18%3A00%3A00.000Z"
        ]
        for sizeClass: UIUserInterfaceSizeClass in [.compact, .regular] {
            for url in urls {
                let link = try XCTUnwrap(Deeplink(url: XCTUnwrap(URL(string: url))))
                let newsTarget = UIViewController()
                let list = AgentThreadListVC()
                var requestedTabs: [AppTabId] = []
                var path: [UIViewController] = []
                func recordModalRequest(_ id: AppTabId, from _: UIViewController, makePath: (UIViewController) -> [UIViewController]) {
                    requestedTabs.append(id)
                    path = makePath(list)
                }
                if sizeClass == .compact {
                    let compact = TopTabsRootViewController()
                    compact.presentHiddenTab = recordModalRequest
                    switch link {
                    case .agentNews: compact.showAgentNewsChat(newsTarget)
                    case .agentDigest(let id): compact.showAgentNewsFeed(digestId: id)
                    default: return XCTFail("Expected an Agent push link")
                    }
                } else {
                    let split = SplitRootViewController()
                    split.presentHiddenTab = recordModalRequest
                    switch link {
                    case .agentNews: split.showAgentNewsChat(newsTarget)
                    case .agentDigest(let id): split.showAgentNewsFeed(digestId: id)
                    default: return XCTFail("Expected an Agent push link")
                    }
                }
                XCTAssertEqual(requestedTabs, [.agent])
                XCTAssertEqual(path.count, 1)
                switch link {
                case .agentNews:
                    XCTAssertTrue(path.first === newsTarget)
                case .agentDigest(let id):
                    let feed = try XCTUnwrap(path.first as? AgentNewsFeedVC)
                    let model = try XCTUnwrap(Mirror(reflecting: feed).children.first { $0.label == "model" }?.value as? AgentNewsFeedModel)
                    XCTAssertEqual(model.requestedDigestId, id)
                default: break
                }
                XCTAssertFalse(AppTabManager.shared.contains(.agent))
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

    private func findDescendants(of view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + findDescendants(of: $0) }
    }
}

@MainActor
private final class RootDictationRecorder: AgentDictationRecording {
    var onFailure: (() -> Void)?

    func averagePower() -> Float { -20 }
    func getPeakPower() -> Float { -160 }
    func stop() async throws -> Data { Data([1]) }
    func cancel() {}
}

/// A clock that moves only when the test sets it, so a recording never reaches its limit on its own
@MainActor
private final class RootDictationScheduler: AgentDictationScheduling {
    var now: TimeInterval = 0

    func schedule(
        after delay: TimeInterval,
        repeating interval: TimeInterval?,
        _ action: @escaping @MainActor () -> Void
    ) -> any AgentDictationScheduledTask {
        Event()
    }

    private final class Event: AgentDictationScheduledTask {
        func cancel() {}
    }
}

@MainActor
private final class AgentBarHost: RootAgentBarHost {
    let navigation = AgentBarNavigationController(rootViewController: UIViewController())
    let agentBarHostView = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    var agentBarNavigationController: WNavigationController? { navigation }
    var agentBarSideEdge: UIRectEdge? { nil }
    var agentBarSearchViewController: UIViewController? { nil }
    func agentBarMorphProgressDidChange(_ progress: CGFloat) {}
    func agentBarEditingDidChange(_ isEditing: Bool) {}
    func agentBarDidHandOffEditingToComposedChat() {}
}

/// Runs a dictation's scheduled work when the test advances its time
@MainActor
private final class AgentBarDictationScheduler: AgentDictationScheduling {
    private(set) var now: TimeInterval = 0
    private var events: [Event] = []

    func schedule(
        after delay: TimeInterval,
        repeating interval: TimeInterval?,
        _ action: @escaping @MainActor () -> Void
    ) -> any AgentDictationScheduledTask {
        let event = Event(deadline: now + delay, interval: interval, action: action)
        events.append(event)
        return event
    }

    func advance(by duration: TimeInterval) {
        let target = now + duration
        while let event = events.filter({ !$0.isCancelled && $0.deadline <= target }).min(by: { $0.deadline < $1.deadline }) {
            now = event.deadline
            if let interval = event.interval {
                event.deadline += interval
            } else {
                events.removeAll { $0 === event }
            }
            event.action()
        }
        now = target
        events.removeAll { $0.isCancelled }
    }

    private final class Event: AgentDictationScheduledTask {
        var deadline: TimeInterval
        let interval: TimeInterval?
        let action: @MainActor () -> Void
        var isCancelled = false

        init(deadline: TimeInterval, interval: TimeInterval?, action: @escaping @MainActor () -> Void) {
            self.deadline = deadline
            self.interval = interval
            self.action = action
        }

        func cancel() { isCancelled = true }
    }
}

private final class AgentBarDictationRecorder: AgentDictationRecording {
    var onFailure: (() -> Void)?
    func averagePower() -> Float { -20 }
    func getPeakPower() -> Float { -160 }
    func stop() async throws -> Data { Data([1, 2, 3]) }
    func cancel() {}
}

@MainActor
private final class AgentBarHandoffChat: UIViewController, AgentComposerHandoffTarget {
    let isComposerOnKeyboard: Bool
    private(set) var hiddenStates: [Bool] = []

    init(isComposerOnKeyboard: Bool) {
        self.isComposerOnKeyboard = isComposerOnKeyboard
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setComposerHandoffHidden(_ isHidden: Bool) {
        hiddenStates.append(isHidden)
    }
}

@MainActor
private final class AgentBarNavigationController: WNavigationController {
    var stubTransitionCoordinator: (any UIViewControllerTransitionCoordinator)?
    override var transitionCoordinator: (any UIViewControllerTransitionCoordinator)? { stubTransitionCoordinator }
}

@MainActor
private final class AgentBarTransitionCoordinator: NSObject, UIViewControllerTransitionCoordinator {
    let presentationStyle: UIModalPresentationStyle
    let from: UIViewController
    let to: UIViewController
    let containerView = UIView()
    let isAnimated = true
    let initiallyInteractive = false
    let isInterruptible = false
    let isInteractive = false
    let isCancelled = false
    let transitionDuration: TimeInterval = 1
    let percentComplete: CGFloat = 0.5
    let completionVelocity: CGFloat = 0
    let completionCurve = UIView.AnimationCurve.easeInOut
    let targetTransform = CGAffineTransform.identity
    private(set) var animationCount = 0
    private var pending: [() -> Void] = []

    init(style: UIModalPresentationStyle, from: UIViewController, to: UIViewController) {
        presentationStyle = style
        self.from = from
        self.to = to
    }

    func viewController(forKey key: UITransitionContextViewControllerKey) -> UIViewController? {
        key == .from ? from : to
    }
    func view(forKey key: UITransitionContextViewKey) -> UIView? { nil }
    func animate(
        alongsideTransition animation: ((any UIViewControllerTransitionCoordinatorContext) -> Void)?,
        completion: ((any UIViewControllerTransitionCoordinatorContext) -> Void)? = nil
    ) -> Bool {
        animationCount += 1
        pending.append { [self] in
            animation?(self)
            completion?(self)
        }
        return true
    }
    func animateAlongsideTransition(
        in view: UIView?,
        animation: ((any UIViewControllerTransitionCoordinatorContext) -> Void)?,
        completion: ((any UIViewControllerTransitionCoordinatorContext) -> Void)? = nil
    ) -> Bool {
        animate(alongsideTransition: animation, completion: completion)
    }
    func notifyWhenInteractionEnds(_ handler: @escaping (any UIViewControllerTransitionCoordinatorContext) -> Void) {}
    func notifyWhenInteractionChanges(_ handler: @escaping (any UIViewControllerTransitionCoordinatorContext) -> Void) {}

    func completeTransition() {
        let callbacks = pending
        pending.removeAll()
        callbacks.forEach { $0() }
    }
}

@MainActor
private final class RootAgentListClient: AgentThreadListClient, AgentNewsFeedClient {
    func listThreads(cursor: String?, limit: Int?, query: String?) async throws -> ApiAgentV2ThreadListResponse {
        .init(protocolVersion: 3, threads: [], nextCursor: nil)
    }

    func cachedThreads() async -> [ApiAgentV2ThreadListItem]? { nil }

    func getNewsFeed(lang: String, cursor: String?, schedule: AgentNewsDigestSchedule, view: ApiAgentV2NewsFeedView = .all) async throws -> ApiAgentV2NewsFeedPage {
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

/// A press on the Agent list's floating microphone in the state the test gives
private final class RootFloatingMicrophonePress: UILongPressGestureRecognizer {
    private let reportedState: UIGestureRecognizer.State

    init(state: UIGestureRecognizer.State) {
        reportedState = state
        super.init(target: nil, action: nil)
    }

    override var state: UIGestureRecognizer.State {
        get { reportedState }
        set { }
    }
}
