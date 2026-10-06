import Dependencies
import UIKit
import XCTest
import UIComponents
import WalletCore
import WalletResources
import UISettings
@testable import AirAsFramework

@MainActor
final class SettingsAccountChangeTests: XCTestCase {
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
    }

    func testDelayedAccountChangeKeepsSettingsOnSharedStack() async throws {
        let home = UIViewController()
        let token = UIViewController()
        let settings = SettingsVC()
        let navigation = UINavigationController()
        navigation.setViewControllers([home, token, settings], animated: false)
        settings.loadViewIfNeeded()
        defer { WalletCoreData.remove(observer: settings) }

        settings.walletCore(event: .accountChanged(accountId: "1-mainnet", isNew: false))
        try await Task.sleep(for: .milliseconds(500))

        XCTAssertEqual(navigation.viewControllers, [home, token, settings])
    }

    func testOpeningSettingsDuringAccountRefreshKeepsItVisible() async throws {
        let home = UIViewController()
        let navigation = UINavigationController(rootViewController: home)
        let settings = SettingsVC()
        settings.loadViewIfNeeded()
        defer { WalletCoreData.remove(observer: settings) }

        settings.walletCore(event: .accountChanged(accountId: "1-mainnet", isNew: false))
        try await Task.sleep(for: .milliseconds(100))
        navigation.pushViewController(settings, animated: false)
        try await Task.sleep(for: .milliseconds(500))

        XCTAssertEqual(navigation.viewControllers, [home, settings])
    }

    func testAccountChangeResetsDetailsToSettingsInBothLayouts() async throws {
        for prefix in [[], [UIViewController()]] {
            let settings = SettingsVC()
            let navigation = UINavigationController()
            navigation.setViewControllers(prefix + [settings, UIViewController()], animated: false)
            settings.loadViewIfNeeded()
            defer { WalletCoreData.remove(observer: settings) }

            settings.walletCore(event: .accountChanged(accountId: "1-mainnet", isNew: false))
            try await Task.sleep(for: .milliseconds(500))

            XCTAssertEqual(navigation.viewControllers, prefix + [settings])
        }
    }

    func testExplicitReturnHomeStillRemovesSettingsDuringAccountRefresh() async throws {
        let root = TopTabsRootViewController()
        let navigation = WNavigationController(rootViewController: root)
        XCTAssertTrue(root.selectTab(.settings))
        let settings = try XCTUnwrap(navigation.topViewController as? SettingsVC)
        settings.loadViewIfNeeded()
        defer { WalletCoreData.remove(observer: settings) }

        settings.walletCore(event: .accountChanged(accountId: "1-mainnet", isNew: false))
        root.switchToHome(popToRoot: true)

        XCTAssertEqual(root.currentTabId, .wallet)
        XCTAssertEqual(navigation.viewControllers, [root])
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(root.currentTabId, .wallet)
        XCTAssertEqual(navigation.viewControllers, [root])
    }
}
