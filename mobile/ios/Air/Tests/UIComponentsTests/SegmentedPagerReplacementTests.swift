import UIKit
import XCTest
import WalletResources
@testable import UIComponents

@MainActor
final class SegmentedPagerReplacementTests: XCTestCase {
    func testOffscreenReplacementKeepsNewContentAndResetsSelectionWithoutSnapshot() {
        for placement in [Placement.outsideWindow, .clipped, .hidden, .transparent, .detached] {
            let (window, container, pager) = makePager()
            defer { window.isHidden = true }
            pager.handleSegmentChange(to: 1, animated: false)
            switch placement {
            case .outsideWindow: container.frame.origin.y = window.bounds.maxY + 10
            case .clipped: pager.frame.origin.y = container.bounds.maxY + 10
            case .hidden: container.isHidden = true
            case .transparent: container.alpha = 0
            case .detached: container.removeFromSuperview()
            }
            let originalSubviews = pager.subviews
            let replacement = Content()
            let items = [WSegmentedPagerItem(id: "new", title: "New", viewController: replacement)]
            var starts = 0
            var completions = 0
            pager.onWillStartTransition = { starts += 1 }
            pager.onDidEndScrolling = { completions += 1 }

            pager.replace(items: items, force: true, animated: true)

            XCTAssertEqual(pager.selectedIndex, 0, "\(placement)")
            XCTAssertTrue(pager.viewControllers.first === replacement)
            XCTAssertEqual(pager.subviews, originalSubviews, "\(placement)")
            XCTAssertEqual(starts, 1)
            XCTAssertEqual(completions, 1)
            XCTAssertEqual(pager.pagingGestureView.alpha, 1)
        }
    }

    func testPartiallyVisibleReplacementRetainsCrossfadeAndRemovesSnapshot() async throws {
        let (window, container, pager) = makePager()
        defer { window.isHidden = true }
        pager.frame.origin.y = container.bounds.maxY - 30
        try await Task.sleep(for: .milliseconds(100))
        let originalSubviews = pager.subviews
        var completions = 0
        pager.onDidEndScrolling = { completions += 1 }
        pager.replace(items: [.init(id: "new", title: "New", viewController: Content())], force: true, animated: true)
        XCTAssertEqual(pager.subviews.count, originalSubviews.count + 1)
        try await Task.sleep(for: .milliseconds(700))
        XCTAssertEqual(pager.subviews, originalSubviews)
        XCTAssertEqual(completions, 1)
    }

    private enum Placement { case outsideWindow, clipped, hidden, transparent, detached }

    private func makePager() -> (UIWindow, UIView, WSegmentedPagerView) {
        _ = WalletResourcesBundle.bundle.load()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        let root = UIViewController()
        window.rootViewController = root
        let container = UIView(frame: CGRect(x: 0, y: 100, width: 300, height: 200))
        container.clipsToBounds = true
        root.view.addSubview(container)
        let pager = WSegmentedPagerView(items: [
            .init(id: "first", title: "First", viewController: Content()),
            .init(id: "second", title: "Second", viewController: Content()),
        ])
        pager.translatesAutoresizingMaskIntoConstraints = true
        pager.frame = CGRect(x: 0, y: 0, width: 300, height: 200)
        container.addSubview(pager)
        window.makeKeyAndVisible()
        root.view.layoutIfNeeded()
        pager.layoutIfNeeded()
        return (window, container, pager)
    }

    private final class Content: UIViewController, WSegmentedControllerContent {
        var onScroll: ((CGFloat) -> Void)?
        var scrollingView: UIScrollView? { nil }
        override func loadView() {
            view = UIView()
            view.backgroundColor = .systemBlue
        }
        func scrollToTop(animated: Bool) {}
        func calculateHeight(isHosted: Bool) -> CGFloat { 150 }
    }
}
