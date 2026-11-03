import Dependencies
import GRDB
import UIKit
import XCTest
import WalletContext
@testable import WalletCore
import WalletResources
@testable import AirAsFramework

@MainActor
final class SplitRootToolbarTabsTests: XCTestCase {
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
            previousTabIds = AppTabManager.shared.orderedTabIds
            AppTabManager.shared.resetToDefault()
        }
    }

    override func tearDown() {
        MainActor.assumeIsolated {
            AppTabManager.shared.setTabIds(previousTabIds)
            SettingsStore.liveValue.clean()
        }
        super.tearDown()
    }

    func testToolbarOrderUpdatesWhenTabsAreHiddenRestoredAndReordered() {
        let tabs = AppTabManager.shared
        XCTAssertEqual(tabs.toolbarTabIds, [.wallet, .market, .agent, .explore])
        var updates: [[AppTabId]] = []
        let observer = NSObject()
        tabs.addObserver(observer) { _ in updates.append(tabs.toolbarTabIds) }
        defer { tabs.removeObserver(observer) }

        tabs.setTabIds([.wallet, .market, .explore, .settings])
        XCTAssertEqual(tabs.toolbarTabIds, [.wallet, .market, .explore])
        XCTAssertEqual(updates.last, [.wallet, .market, .explore])

        tabs.setTabIds([.settings, .explore, .agent, .portfolio, .wallet])
        XCTAssertEqual(tabs.toolbarTabIds, [.explore, .agent, .portfolio, .wallet])
        XCTAssertEqual(updates.last, [.explore, .agent, .portfolio, .wallet])

        tabs.setTabIds([.settings, .wallet])
        XCTAssertEqual(tabs.toolbarTabIds, [.wallet])
        XCTAssertEqual(updates.last, [.wallet])
        XCTAssertEqual(updates.count, 3)
    }

    func testFuturesIsAbsentEvenFromSavedTabOrders() {
        let tabs = AppTabManager.shared
        XCTAssertFalse(tabs.registeredTabIds.contains(.futures))
        XCTAssertEqual(tabs.validatedTabOrder(from: ["futures", "wallet", "settings"]), [.wallet, .settings])
    }

    func testMovingAccountsRemovesAndRestoresTheVerticalHeaderButton() throws {
        guard #available(iOS 27.1, *) else { throw XCTSkip("Vertical navigation requires iOS 27.1") }
        let key = ToolbarSettings.accountsKey
        let previous = UserDefaults.standard.object(forKey: key)
        defer {
            UserDefaults.standard.set(previous, forKey: key)
            ToolbarSettings.notifyDidChange()
        }
        UserDefaults.standard.set(false, forKey: key)
        let toolbar = SplitRootToolbarView(tabIds: AppTabManager.shared.toolbarTabIds)
        XCTAssertFalse(toolbar.accountButton.isHidden)
        for moved in [true, false, true] {
            UserDefaults.standard.set(moved, forKey: key)
            ToolbarSettings.notifyDidChange()
            XCTAssertEqual(toolbar.accountButton.isHidden, moved)
            XCTAssertEqual(toolbar.accountButton.isUserInteractionEnabled, !moved)
        }
        let replacement = SplitRootToolbarView(tabIds: AppTabManager.shared.toolbarTabIds)
        XCTAssertTrue(replacement.accountButton.isHidden)
    }
}
