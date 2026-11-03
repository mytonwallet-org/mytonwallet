import Dependencies
import GRDB
import UIKit
import XCTest
import UISettings
import UIComponents
import WalletContext
@testable import WalletCore
import WalletResources
@testable import AirAsFramework

@MainActor
final class SettingsMorphTransitionTests: XCTestCase {
    private var previousAccountsPreference: Any?

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
            previousAccountsPreference = UserDefaults.standard.object(forKey: ToolbarSettings.accountsKey)
            UserDefaults.standard.set(false, forKey: ToolbarSettings.accountsKey)
            UIView.setAnimationsEnabled(true)
        }
    }

    override func tearDown() {
        MainActor.assumeIsolated {
            UserDefaults.standard.set(previousAccountsPreference, forKey: ToolbarSettings.accountsKey)
            ToolbarSettings.notifyDidChange()
            SettingsStore.liveValue.clean()
        }
        super.tearDown()
    }

    func testToolbarAccountsSkipsTheMorphInBothDirections() async throws {
        let (window, root, navigation) = try await makeRoot()
        defer { window.isHidden = true }
        root.selectTab(.settings, animated: false)
        let settings = try XCTUnwrap(navigation.topViewController as? SettingsVC)
        navigation.popViewController(animated: false)
        try await waitForNavigation(navigation, on: root)
        let provider = try XCTUnwrap(navigation.customTransitionProvider)
        XCTAssertNotNil(provider(.push, root, settings))
        XCTAssertNotNil(provider(.pop, settings, root))

        UserDefaults.standard.set(true, forKey: ToolbarSettings.accountsKey)
        ToolbarSettings.notifyDidChange()
        window.layoutIfNeeded()
        XCTAssertNil(provider(.push, root, settings))
        XCTAssertNil(provider(.pop, settings, root), "A cached horizontal source cannot survive moving Accounts")

        root.selectTab(.settings, animated: true)
        try await waitForNavigation(navigation, on: settings)
        navigation.popViewController(animated: true)
        try await waitForNavigation(navigation, on: root)
        XCTAssertTrue(navigation.delegate === navigation)
        XCTAssertFalse(navigation.view.subviews.contains { $0.accessibilityIdentifier == "settings_morph_overlay" })
    }

    func testScrolledSettingsKeepsItsAvatarStateAndScrollPositionAcrossMorphs() async throws {
        let (window, root, navigation) = try await makeRoot()
        defer { window.isHidden = true }
        root.selectTab(.settings, animated: true)
        let settings = try XCTUnwrap(navigation.topViewController as? SettingsVC)
        try await waitForNavigation(navigation, on: settings)
        let collection = try XCTUnwrap(settings.view.subviews.compactMap { $0 as? UICollectionView }.first)
        // The empty test account has fewer rows; make all three scroll states reachable
        collection.contentInset.bottom += 500
        for scrollOffset: CGFloat in [80, 200, 260] {
            collection.contentOffset.y = scrollOffset - collection.adjustedContentInset.top
            settings.scrollViewDidScroll(collection)
            window.layoutIfNeeded()
            let offset = collection.contentOffset
            let barMidY = navigation.navigationBar.convert(
                CGPoint(x: 0, y: 22), to: settings.view
            ).y
            let state = settings.morphAvatarState(navigationBarMidY: barMidY)
            let actual = settings.morphAvatarView.convert(settings.morphAvatarView.bounds, to: settings.view)
            XCTAssertEqual(state.frame.midY, actual.midY, accuracy: 0.5)
            XCTAssertEqual(state.alpha, settings.morphAvatarView.alpha, accuracy: 0.001)
            XCTAssertGreaterThan(state.blurRadius, 0)
            if scrollOffset == 260 { XCTAssertEqual(state.alpha, 0) }

            XCTAssertNotNil(navigation.customTransitionProvider?(.pop, settings, root))
            navigation.popViewController(animated: true)
            try await waitForNavigation(navigation, on: root)
            XCTAssertFalse(settings.morphAvatarView.isHidden)
            XCTAssertTrue(navigation.navigationBar.subviews.allSatisfy { $0.layer.mask == nil })
            XCTAssertFalse(navigation.view.subviews.contains { $0.accessibilityIdentifier == "settings_morph_overlay" })
            root.selectTab(.settings, animated: true)
            try await waitForNavigation(navigation, on: settings)
            XCTAssertEqual(collection.contentOffset.y, offset.y, accuracy: 0.5)
            XCTAssertEqual(settings.morphAvatarView.alpha, state.alpha, accuracy: 0.001)
        }
        let next = WViewController()
        navigation.pushViewController(next, animated: true)
        try await waitForNavigation(navigation, on: next)
        XCTAssertTrue(navigation.delegate === navigation)
    }

    func testResizingInvalidatesTheCachedPopGeometry() async throws {
        let (window, root, navigation) = try await makeRoot()
        defer { window.isHidden = true }
        root.selectTab(.settings, animated: true)
        let settings = try XCTUnwrap(navigation.topViewController as? SettingsVC)
        try await waitForNavigation(navigation, on: settings)
        let provider = try XCTUnwrap(navigation.customTransitionProvider)
        XCTAssertNotNil(provider(.pop, settings, root))
        navigation.view.bounds.size.width += 120
        XCTAssertNil(provider(.pop, settings, root))
    }

    func testInteractiveSettingsEntryCannotReuseAPreviousTabSnapshot() async throws {
        let (window, root, navigation) = try await makeRoot()
        defer { window.isHidden = true }
        root.selectTab(.settings, animated: true)
        let settings = try XCTUnwrap(navigation.topViewController as? SettingsVC)
        try await waitForNavigation(navigation, on: settings)
        XCTAssertNotNil(navigation.customTransitionProvider?(.pop, settings, root))
        navigation.popViewController(animated: true)
        try await waitForNavigation(navigation, on: root)

        root.selectTab(.explore, animated: false)
        window.layoutIfNeeded()
        let transition = try XCTUnwrap(navigation.beginInteractivePush(settings))
        XCTAssertTrue(try XCTUnwrap(navigation.transitionCoordinator).isInteractive)
        try await Task.sleep(for: .milliseconds(100))
        transition.update(0.6)
        transition.finish()
        try await waitForNavigation(navigation, on: settings)

        XCTAssertNil(navigation.customTransitionProvider?(.pop, settings, root),
                     "A swipe into Settings must not reuse the earlier Wallet header snapshot")
        navigation.popViewController(animated: true)
        try await waitForNavigation(navigation, on: root)
        root.selectTab(.settings, animated: true)
        try await waitForNavigation(navigation, on: settings)
        XCTAssertNotNil(navigation.customTransitionProvider?(.pop, settings, root),
                        "A subsequent button-driven entry captures a fresh source")
    }

    private func makeRoot() async throws -> (UIWindow, TopTabsRootViewController, WNavigationController) {
        guard #available(iOS 26, *), IOS_26_MODE_ENABLED else { throw XCTSkip("The morph requires Liquid Glass") }
        let root = TopTabsRootViewController()
        let navigation = WNavigationController(rootViewController: root)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        try await waitForNavigation(navigation, on: root)
        // A test window lays out the navigation bar's title view when its properties are explicitly updated
        var views = [navigation.navigationBar as UIView]
        while let view = views.popLast() {
            if #available(iOS 26, *) { view.setNeedsUpdateProperties() }
            view.setNeedsLayout()
            views += view.subviews
        }
        if #available(iOS 26, *) { window.updatePropertiesIfNeeded() }
        window.layoutIfNeeded()
        return (window, root, navigation)
    }

    private func waitForNavigation(_ navigation: WNavigationController, on top: UIViewController) async throws {
        // UIKit installs the coordinator and calls appearance callbacks on the next run-loop turn
        try await Task.sleep(for: .milliseconds(50))
        for _ in 0..<200 {
            if navigation.topViewController === top, navigation.transitionCoordinator == nil,
               navigation.delegate === navigation, top.viewIfLoaded?.window != nil { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Navigation did not settle on the expected screen")
    }
}
