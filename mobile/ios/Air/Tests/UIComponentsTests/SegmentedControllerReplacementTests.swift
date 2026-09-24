import UIKit
import XCTest
import WalletResources
@testable import UIComponents

@MainActor
final class SegmentedControllerReplacementTests: XCTestCase {
    func testReplacementSynchronizesPagesAndSelectionBeforeReturning() {
        let controller = makeController()
        controller.setSelectedIndex(to: 2, animated: false)

        controller.replace(items: items(["ton"]))

        XCTAssertEqual(controller.model.items.map(\.id), ["ton"])
        XCTAssertEqual(controller.model.selection?.effectiveSelectedItemID, "ton")
        XCTAssertEqual(controller.model.rawProgress, 0)
        XCTAssertEqual(controller.selectedIndex, 0)
        XCTAssertEqual(controller.scrollView.contentOffset.x, 0)
    }

    func testReplacementPreservesAvailableChainAtItsNewIndex() {
        let controller = makeController()
        controller.setSelectedIndex(to: 2, animated: false)
        let replacement = items(["solana", "ethereum"])

        controller.replace(items: replacement)

        XCTAssertEqual(controller.model.selection?.effectiveSelectedItemID, "ethereum")
        XCTAssertEqual(controller.selectedIndex, 1)
        XCTAssertEqual(controller.scrollView.contentOffset.x, 400)
        XCTAssertTrue(controller.viewControllers[1] === replacement[1].viewController)
    }

    func testRapidReplacementsDoNotReplayAnOlderAccountOnNextRunLoop() async throws {
        let controller = makeController()
        controller.setSelectedIndex(to: 2, animated: false)
        controller.replace(items: items(["ton", "ethereum"]))
        controller.replace(items: items(["solana"]))
        controller.replace(items: items(["ton", "solana", "ethereum"]))

        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(controller.model.items.map(\.id), ["ton", "solana", "ethereum"])
        XCTAssertEqual(controller.model.selection?.effectiveSelectedItemID, "solana")
        XCTAssertEqual(controller.selectedIndex, 1)
        XCTAssertEqual(controller.scrollView.contentOffset.x, 400)
    }

    func testReplacementCancelsPreviousPageAnimation() async throws {
        let controller = makeController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let root = UIViewController()
        window.rootViewController = root
        root.view.addSubview(controller)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        root.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))

        controller.setSelectedIndex(to: 2, animated: true)
        try await Task.sleep(for: .milliseconds(50))
        controller.replace(items: items(["ton"]))
        controller.replace(items: items(["ton", "solana"]))
        try await Task.sleep(for: .milliseconds(600))

        XCTAssertEqual(controller.model.selection?.effectiveSelectedItemID, "ton")
        XCTAssertEqual(controller.model.rawProgress, 0)
        XCTAssertEqual(controller.selectedIndex, 0)
        XCTAssertEqual(controller.scrollView.contentOffset.x, 0)
        XCTAssertTrue(controller.scrollView.layer.animationKeys()?.isEmpty != false)
    }

    func testReplacementCancelsAdditionalPagingWithoutMovingNewPages() {
        let controller = makeController()
        controller.beginAdditionalPaging()
        controller.updateAdditionalPaging(translation: -250)
        controller.replace(items: items(["ethereum"]))

        controller.updateAdditionalPaging(translation: -500)
        controller.endAdditionalPaging(translation: -500, velocity: -900, cancelled: false)

        XCTAssertEqual(controller.model.selection?.effectiveSelectedItemID, "ethereum")
        XCTAssertEqual(controller.selectedIndex, 0)
        XCTAssertEqual(controller.scrollView.contentOffset.x, 0)
    }

    func testEmptyReplacementClearsSelectionAndCanRecover() {
        let controller = makeController()
        controller.setSelectedIndex(to: 2, animated: false)
        controller.replace(items: [])

        XCTAssertNil(controller.model.selection)
        XCTAssertNil(controller.selectedIndex)
        XCTAssertEqual(controller.scrollView.contentOffset.x, 0)

        controller.replace(items: items(["solana"]))

        XCTAssertEqual(controller.model.selection?.effectiveSelectedItemID, "solana")
        XCTAssertEqual(controller.selectedIndex, 0)
    }

    private func items(_ ids: [String]) -> [SegmentedControlItem] {
        ids.map { SegmentedControlItem(id: $0, title: $0, viewController: Content()) }
    }

    private func makeController() -> WSegmentedController {
        _ = WalletResourcesBundle.bundle.load()
        let controller = WSegmentedController(items: items(["ton", "solana", "ethereum"]))
        controller.frame = CGRect(x: 0, y: 0, width: 400, height: 800)
        NSLayoutConstraint.activate([
            controller.widthAnchor.constraint(equalToConstant: 400),
            controller.heightAnchor.constraint(equalToConstant: 800),
        ])
        controller.layoutIfNeeded()
        return controller
    }

    private final class Content: UIViewController, WSegmentedControllerContent {
        var onScroll: ((CGFloat) -> Void)?
        var scrollingView: UIScrollView? { nil }
        func scrollToTop(animated: Bool) {}
        func calculateHeight(isHosted: Bool) -> CGFloat { 800 }
    }
}
