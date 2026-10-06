import UIKit
import XCTest
@testable import AirAsFramework

@MainActor
final class SplitSearchSidebarLayoutTests: XCTestCase {
    @available(iOS 17.0, *)
    func testCoverFollowsTiledAndFloatingSidebarsWithoutRevealingHiddenSidebar() async throws {
        for behavior: UISplitViewController.SplitBehavior in [.tile, .overlay] {
            let sidebar = SplitRootSidebarNavigationController(rootViewController: UIViewController())
            let detail = UIViewController()
            let split = UISplitViewController(style: .doubleColumn)
            split.traitOverrides.horizontalSizeClass = .regular
            split.preferredSplitBehavior = behavior
            split.preferredDisplayMode = behavior == .tile ? .oneBesideSecondary : .oneOverSecondary
            split.minimumPrimaryColumnWidth = 300
            split.maximumPrimaryColumnWidth = 360
            split.setViewController(sidebar, for: .primary)
            split.setViewController(detail, for: .secondary)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1210, height: 834))
            window.rootViewController = split
            window.makeKeyAndVisible()
            defer { window.isHidden = true }
            try await settle(window)
            sidebar.setSearchVisible(true, coordinator: nil)
            let cover = try XCTUnwrap(sidebar.view.subviews.first { $0.accessibilityIdentifier == "SearchSidebarDismissOverlay" } as? UIControl)
            XCTAssertEqual(cover.frame, sidebar.view.bounds)
            let center = CGPoint(x: cover.bounds.midX, y: cover.bounds.midY)
            XCTAssertTrue(window.hitTest(cover.convert(center, to: window), with: nil) === cover)
            XCTAssertEqual(split.displayMode, behavior == .tile ? .oneBesideSecondary : .oneOverSecondary)

            split.hide(.primary)
            try await settle(window)
            XCTAssertEqual(split.displayMode, .secondaryOnly)
            sidebar.setSearchVisible(false, coordinator: nil)
            sidebar.setSearchVisible(true, coordinator: nil)
            try await settle(window)
            XCTAssertEqual(split.displayMode, .secondaryOnly)
            let detailCenter = CGPoint(x: detail.view.bounds.midX, y: detail.view.bounds.midY)
            XCTAssertFalse(window.hitTest(detail.view.convert(detailCenter, to: window), with: nil) === cover)

            split.show(.primary)
            try await settle(window)
            XCTAssertFalse(cover.isHidden)
            XCTAssertTrue(window.hitTest(cover.convert(center, to: window), with: nil) === cover)
            sidebar.setSearchVisible(false, coordinator: nil)
            XCTAssertTrue(cover.isHidden)
            XCTAssertFalse(sidebar.navigationBar.accessibilityElementsHidden)
        }
    }

    private func settle(_ window: UIWindow) async throws {
        try await Task.sleep(for: .milliseconds(500))
        window.layoutIfNeeded()
    }
}
