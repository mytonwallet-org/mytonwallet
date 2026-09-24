import UIKit
import XCTest
import UIComponents
import WalletResources
@testable import UIAssets

@MainActor
final class WalletAssetsAccountTransitionTests: XCTestCase {
    func testReplacementFadesOldContentWithoutResizingIt() async throws {
        let (window, view) = makeVisibleAssets()
        defer { window.isHidden = true }
        try await Task.sleep(for: .milliseconds(100))

        view.prepareAccountTransition(animated: true)
        let snapshot = try XCTUnwrap(view.subviews.last)
        XCTAssertFalse(snapshot === view.tabsContainer)
        let originalFrame = snapshot.frame
        UIView.performWithoutAnimation {
            view.backgroundColor = .blue
            view.frame.size.height = 160
            view.layoutIfNeeded()
        }
        view.animateAccountTransition()
        try await Task.sleep(for: .milliseconds(80))

        let opacity = try XCTUnwrap(snapshot.layer.presentation()?.opacity)
        XCTAssertGreaterThan(opacity, 0)
        XCTAssertLessThan(opacity, 1)
        XCTAssertEqual(snapshot.frame, originalFrame)
        XCTAssertFalse(snapshot.isUserInteractionEnabled)
        XCTAssertTrue(snapshot.accessibilityElementsHidden)
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertNil(snapshot.superview)
        XCTAssertEqual(view.subviews.count, 1)
    }

    func testInterruptedReplacementKeepsOnlyTheLatestOverlay() async throws {
        let (window, view) = makeVisibleAssets()
        defer { window.isHidden = true }
        try await Task.sleep(for: .milliseconds(100))
        view.prepareAccountTransition(animated: true)
        let first = try XCTUnwrap(view.subviews.last)
        view.animateAccountTransition()
        try await Task.sleep(for: .milliseconds(80))

        view.prepareAccountTransition(animated: true)
        let second = try XCTUnwrap(view.subviews.last)
        XCTAssertFalse(first === second)
        XCTAssertNil(first.superview)
        XCTAssertEqual(view.subviews.count, 2)
        // The old animation's completion must not discard the pending replacement.
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertTrue(second.superview === view)
        view.animateAccountTransition()
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertLessThan(try XCTUnwrap(second.layer.presentation()?.opacity), 1)
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(view.subviews.count, 1)
    }

    func testNonanimatedOrClippedReplacementDoesNotKeepASnapshot() async throws {
        let (window, view) = makeVisibleAssets()
        defer { window.isHidden = true }
        try await Task.sleep(for: .milliseconds(100))
        view.prepareAccountTransition(animated: true)
        XCTAssertEqual(view.subviews.count, 2)
        view.prepareAccountTransition(animated: false)
        XCTAssertEqual(view.subviews.count, 1)

        view.superview?.clipsToBounds = true
        view.frame.origin.y = 1000
        view.prepareAccountTransition(animated: true)
        XCTAssertEqual(view.subviews.count, 1)
        view.removeFromSuperview()
        view.prepareAccountTransition(animated: true)
        XCTAssertEqual(view.subviews.count, 1)
    }

    private func makeVisibleAssets() -> (UIWindow, WalletAssetsView) {
        _ = WalletResourcesBundle.bundle.load()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let root = UIViewController()
        window.rootViewController = root
        let view = WalletAssetsView(walletCollectiblesView: Content())
        view.translatesAutoresizingMaskIntoConstraints = true
        view.frame = CGRect(x: 0, y: 100, width: 400, height: 260)
        root.view.addSubview(view)
        window.makeKeyAndVisible()
        root.view.layoutIfNeeded()
        return (window, view)
    }

    private final class Content: UIViewController, WSegmentedControllerContent {
        var onScroll: ((CGFloat) -> Void)?
        var scrollingView: UIScrollView? { nil }
        func scrollToTop(animated: Bool) {}
        func calculateHeight(isHosted: Bool) -> CGFloat { 240 }
    }
}
