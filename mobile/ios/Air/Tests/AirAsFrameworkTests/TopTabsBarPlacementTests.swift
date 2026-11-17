import Dependencies
import GRDB
import ObjectiveC
import UIKit
import UIComponents
import WalletContext
@testable import WalletCore
import WalletResources
import XCTest
@testable import AirAsFramework

@MainActor
final class TopTabsBarPlacementTests: XCTestCase {
    override func invokeTest() {
        withDependencies { $0.context = .live } operation: { super.invokeTest() }
    }

    func testNavigationContainerOwnsPlacementWhileRootIsDetached() throws {
        guard #available(iOS 27.1, *) else { throw XCTSkip("Vertical bars require iOS 27.1") }
        _ = WalletResourcesBundle.bundle.load()
        let database = try DatabaseQueue()
        try makeMigrator().migrate(database)
        SettingsStore.liveValue.use(db: database)
        defer { SettingsStore.liveValue.clean() }
        let restoreBarEdge = try installBarEdgeFixture()
        defer { restoreBarEdge() }

        let root = TopTabsRootViewController()
        let navigation = WNavigationController(rootViewController: root)
        navigation.traitOverrides.horizontalSizeClass = .compact
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 466, height: 678))
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        window.layoutIfNeeded()
        let detail = WViewController()
        navigation.pushViewController(detail, animated: false)
        window.layoutIfNeeded()
        XCTAssertNil(root.view.window)

        // A detached root can have a different bar context from its navigation container
        root.traitOverrides.horizontalSizeClass = .regular
        root.viewDidLayoutSubviews()
        XCTAssertTrue(root.hideNavigationBar)
        XCTAssertFalse(navigation.isNavigationBarHidden)
        let bar = try XCTUnwrap(root.view.subviews.compactMap { $0 as? WVerticalTabBar }.first)

        for direction in [UITraitEnvironmentLayoutDirection.leftToRight, .rightToLeft] {
            navigation.traitOverrides.layoutDirection = direction
            navigation.view.updateTraitsIfNeeded()
            root.viewDidLayoutSubviews()
            XCTAssertTrue(root.hideNavigationBar)
            XCTAssertEqual(bar.isOnLeftEdge, direction == .rightToLeft)
            navigation.popViewController(animated: false)
            window.layoutIfNeeded()
            XCTAssertTrue(navigation.isNavigationBarHidden)
            XCTAssertEqual(root.currentTabId, .wallet)
            navigation.pushViewController(detail, animated: false)
            window.layoutIfNeeded()
        }

        navigation.traitOverrides.horizontalSizeClass = .regular
        root.traitOverrides.horizontalSizeClass = .compact
        navigation.view.updateTraitsIfNeeded()
        root.viewDidLayoutSubviews()
        XCTAssertFalse(root.hideNavigationBar)
        navigation.popViewController(animated: false)
        window.layoutIfNeeded()
        XCTAssertFalse(navigation.isNavigationBarHidden)
        XCTAssertNotNil(root.navigationItem.titleView)
        XCTAssertTrue(bar.isHidden)
    }

    @available(iOS 27.1, *)
    private func installBarEdgeFixture() throws -> () -> Void {
        let method = try XCTUnwrap(class_getInstanceMethod(
            UITraitCollection.self, #selector(getter: UITraitCollection.verticalBarEdge)
        ))
        // The fixture supplies a device-independent bar context through an ordinary inherited trait
        let getter: @convention(block) (UITraitCollection) -> Int = { traits in
            traits.horizontalSizeClass == .compact ? UIVerticalBarEdge.trailing.rawValue : UIVerticalBarEdge.unspecified.rawValue
        }
        let implementation = imp_implementationWithBlock(getter)
        let original = method_setImplementation(method, implementation)
        return {
            method_setImplementation(method, original)
            imp_removeBlock(implementation)
        }
    }
}
