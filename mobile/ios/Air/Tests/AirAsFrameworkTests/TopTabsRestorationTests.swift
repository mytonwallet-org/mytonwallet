import CoreText
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
        for name in ["SFCompactRoundedBold", "SFCompactDisplayMedium"] {
            if let url = WalletResourcesBundle.bundle.url(forResource: name, withExtension: "otf") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
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

    @available(iOS 17.0, *)
    private func changeLayout(of controller: AdaptiveRootViewController, to sizeClass: UIUserInterfaceSizeClass) {
        let previousTraits = controller.traitCollection
        controller.traitOverrides.horizontalSizeClass = sizeClass
        controller.traitCollectionDidChange(previousTraits)
    }
}
