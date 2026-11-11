import UIKit
import XCTest
@testable import UIComponents

@available(iOS 26.0, *)
@MainActor
final class VerticalTabBarTests: XCTestCase {
    func testCancelledExpandedDragPreservesCommittedSelection() async throws {
        let (window, bar) = makeBar()
        defer { bar.cancelInteraction(); window.isHidden = true }
        var selections: [Int] = []
        bar.onSelect = { index, _ in selections.append(index) }
        bar.beginScrub(at: CGPoint(x: 24, y: 31))
        try await Task.sleep(for: .milliseconds(300))
        bar.moveScrub(translation: CGPoint(x: 0, y: 100))

        XCTAssertEqual(bar.selectedIndex, 0, "Dragging must only preview a destination")
        XCTAssertTrue(selections.isEmpty)
        bar.finishScrub(cancelled: true)
        XCTAssertEqual(bar.selectedIndex, 0)
        XCTAssertTrue(selections.isEmpty)
        XCTAssertTrue(target("wallet", in: bar).accessibilityTraits.contains(.selected))
    }

    func testExternalSelectionCancelsPendingHoldAndDoesNotEmitUserAction() async throws {
        let (window, bar) = makeBar()
        defer { bar.cancelInteraction(); window.isHidden = true }
        var userActions = 0
        bar.onSelect = { _, _ in userActions += 1 }
        bar.beginScrub(at: CGPoint(x: 24, y: 31))
        bar.select(1, animated: false)
        try await Task.sleep(for: .milliseconds(400))
        bar.finishScrub(cancelled: false)

        XCTAssertEqual(bar.selectedIndex, 1)
        XCTAssertEqual(userActions, 0)
        XCTAssertFalse(bar.point(inside: CGPoint(x: 24, y: 175), with: nil), "The cancelled timer must not leave an expanded hit area")
        XCTAssertTrue(target("market", in: bar).accessibilityTraits.contains(.selected))
    }

    func testHoldDragCommitsOnceAndAccessibilitySupportsReselection() async throws {
        let (window, bar) = makeBar()
        defer { bar.cancelInteraction(); window.isHidden = true }
        var selections: [(Int, Bool)] = []
        bar.onSelect = { selections.append(($0, $1)) }
        bar.beginScrub(at: CGPoint(x: 24, y: 31))
        try await Task.sleep(for: .milliseconds(300))
        bar.moveScrub(translation: CGPoint(x: 0, y: 100))
        bar.finishScrub(cancelled: false)

        XCTAssertEqual(selections.count, 1)
        XCTAssertEqual(selections.first?.0, 2)
        XCTAssertEqual(selections.first?.1, false)
        XCTAssertTrue(target("explore", in: bar).accessibilityActivate())
        XCTAssertEqual(selections.count, 2)
        XCTAssertEqual(selections.last?.1, true)
    }

    func testHoldingATabStillLiftsItAndDraggingMovesItWithoutSelecting() async throws {
        let (window, bar) = makeBar()
        defer { bar.cancelInteraction(); window.isHidden = true }
        var selections: [Int] = []
        var moves: [(Int, Int)] = []
        bar.onSelect = { index, _ in selections.append(index) }
        bar.onReorder = { moves.append(($0, $1)) }
        bar.beginScrub(at: CGPoint(x: 24, y: 31))
        try await Task.sleep(for: .milliseconds(650))
        bar.moveScrub(translation: CGPoint(x: 0, y: 100))
        bar.finishScrub(cancelled: false)

        XCTAssertEqual(moves.map { $0.0 }, [0])
        XCTAssertEqual(moves.map { $0.1 }, [2])
        XCTAssertEqual(bar.itemIds, ["market", "explore", "wallet"])
        XCTAssertTrue(selections.isEmpty, "A drop must not select the lifted tab")
        XCTAssertEqual(bar.selectedIndex, 2, "The selected tab keeps its selection in its new place")
        XCTAssertTrue(target("wallet", in: bar).accessibilityTraits.contains(.selected))
        XCTAssertTrue(target("market", in: bar).accessibilityActivate())
        XCTAssertEqual(selections, [0])
    }

    func testDraggingAnotherTabToTheFirstPlaceMovesTheSelectionAlong() async throws {
        let (window, bar) = makeBar()
        defer { bar.cancelInteraction(); window.isHidden = true }
        var moves: [(Int, Int)] = []
        bar.onReorder = { moves.append(($0, $1)) }
        bar.beginScrub(at: CGPoint(x: 24, y: 131))
        try await Task.sleep(for: .milliseconds(650))
        bar.moveScrub(translation: CGPoint(x: 0, y: -200))
        bar.finishScrub(cancelled: false)

        XCTAssertEqual(moves.map { $0.0 }, [2])
        XCTAssertEqual(moves.map { $0.1 }, [0])
        XCTAssertEqual(bar.itemIds, ["explore", "wallet", "market"])
        XCTAssertEqual(bar.selectedIndex, 1)
    }

    func testSlidingBeforeTheHoldOrCancellingTheDragKeepsTheOrder() async throws {
        let (window, bar) = makeBar()
        defer { bar.cancelInteraction(); window.isHidden = true }
        var selections: [Int] = []
        var moves = 0
        bar.onSelect = { index, _ in selections.append(index) }
        bar.onReorder = { _, _ in moves += 1 }
        bar.beginScrub(at: CGPoint(x: 24, y: 31))
        try await Task.sleep(for: .milliseconds(300))
        bar.moveScrub(translation: CGPoint(x: 0, y: 100))
        try await Task.sleep(for: .milliseconds(400))
        bar.finishScrub(cancelled: false)
        XCTAssertEqual(selections, [2], "A finger that slid before the hold only scrubs")

        bar.beginScrub(at: CGPoint(x: 24, y: 31))
        try await Task.sleep(for: .milliseconds(650))
        bar.moveScrub(translation: CGPoint(x: 0, y: 100))
        bar.finishScrub(cancelled: true)

        XCTAssertEqual(moves, 0)
        XCTAssertEqual(selections, [2])
        XCTAssertEqual(bar.itemIds, ["wallet", "market", "explore"])
        XCTAssertEqual(bar.selectedIndex, 2)
    }

    func testLocalizedTitleKeepsItsTextBoundsAcrossInterruptedHolds() async throws {
        let title = "Kryptowährungsmarkt"
        let (window, bar) = makeBar(titles: ["Wallet", title, "Explore"])
        defer { bar.cancelInteraction(); window.isHidden = true }
        func labels(in view: UIView) -> [UILabel] {
            (view as? UILabel).map { [$0] } ?? view.subviews.flatMap { labels(in: $0) }
        }
        let titles = labels(in: bar).filter { $0.text == title }
        XCTAssertEqual(titles.count, 2, "Both normal and lifted content need stable text bounds")
        let initialBounds = titles.map(\.bounds)
        XCTAssertTrue(titles.allSatisfy { $0.bounds.width >= $0.intrinsicContentSize.width })

        for leftEdge in [false, true] {
            bar.isOnLeftEdge = leftEdge
            bar.layoutIfNeeded()
            bar.beginScrub(at: CGPoint(x: 24, y: 31))
            try await Task.sleep(for: .milliseconds(350))
            XCTAssertEqual(titles.map(\.bounds), initialBounds)
            XCTAssertTrue(titles.allSatisfy { $0.superview?.alpha == 1 })
            bar.finishScrub(cancelled: true)
            try await Task.sleep(for: .milliseconds(500))
            XCTAssertEqual(titles.map(\.bounds), initialBounds)
            XCTAssertTrue(titles.allSatisfy { $0.superview?.alpha == 0 })
            XCTAssertEqual(bar.selectedIndex, 0)
        }
    }

    func testReturningFromSettingsIsNotTabReselection() {
        let (window, bar) = makeBar()
        defer { window.isHidden = true }
        var selections: [(Int, Bool)] = []
        bar.onSelect = { selections.append(($0, $1)) }
        bar.showsSelection = false
        XCTAssertFalse(target("wallet", in: bar).accessibilityTraits.contains(.selected))
        XCTAssertTrue(target("wallet", in: bar).accessibilityActivate())
        XCTAssertEqual(selections.last?.1, false, "Returning to Wallet must preserve its navigation stack")
        bar.showsSelection = true
        XCTAssertTrue(target("wallet", in: bar).accessibilityTraits.contains(.selected))
        XCTAssertTrue(target("wallet", in: bar).accessibilityActivate())
        XCTAssertEqual(selections.last?.1, true)
    }

    func testNativeSelectionSettlesAfterRapidTabChangesAndReparenting() async throws {
        let (window, bar) = makeBar()
        defer { bar.cancelInteraction(); window.isHidden = true }
        let root = try XCTUnwrap(window.rootViewController?.view)
        let alternateHost = UIView(frame: root.bounds)
        root.addSubview(alternateHost)
        bar.onSelect = { [weak bar, weak root, weak alternateHost] _, _ in
            guard let bar, let root, let alternateHost else { return }
            let destination = bar.superview === root ? alternateHost : root
            bar.removeFromSuperview()
            destination.addSubview(bar)
            bar.setNeedsLayout()
            bar.layoutIfNeeded()
        }
        for index in [2, 0, 1, 2, 0] {
            bar.beginScrub(at: CGPoint(x: 24, y: 31 + CGFloat(index) * 50))
            try await Task.sleep(for: .milliseconds(40))
            bar.finishScrub(cancelled: false)
            try await Task.sleep(for: .milliseconds(60))
        }
        try await Task.sleep(for: .seconds(1))
        XCTAssertEqual(bar.selectedIndex, 0)
        func findSelection(in view: UIView) -> UIView? {
            if String(describing: type(of: view)) == "_UITabSelectionView" { return view }
            return view.subviews.lazy.compactMap { findSelection(in: $0) }.first
        }
        let selection = try XCTUnwrap(findSelection(in: bar))
        let frame = selection.convert(selection.bounds, to: bar)
        let selectedTarget = target("wallet", in: bar)
        let expected = selectedTarget.convert(selectedTarget.bounds, to: bar)
        XCTAssertEqual(frame.minX, expected.minX, accuracy: 0.5)
        XCTAssertEqual(frame.minY, expected.minY, accuracy: 0.5)
        XCTAssertEqual(frame.width, expected.width, accuracy: 0.5)
        XCTAssertEqual(frame.height, expected.height, accuracy: 0.5)
    }

    private func makeBar(titles: [String] = ["Wallet", "Market", "Explore"]) -> (UIWindow, WVerticalTabBar) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 466, height: 678))
        let controller = UIViewController()
        window.rootViewController = controller
        let bar = WVerticalTabBar(items: zip(["wallet", "market", "explore"], titles).map { id, title in
            .init(id: id, title: title, image: UIImage(systemName: "circle")!)
        })
        controller.view.addSubview(bar)
        bar.frame = CGRect(origin: CGPoint(x: 394, y: 88), size: bar.intrinsicContentSize)
        // State tests do not need a scene; real glass visibility is covered by the app UI test.
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()
        bar.layoutIfNeeded()
        return (window, bar)
    }

    private func target(_ id: String, in view: UIView) -> UIView {
        func find(_ view: UIView) -> UIView? {
            if view.accessibilityIdentifier == "top-tabs.side-tab.\(id)" { return view }
            return view.subviews.lazy.compactMap(find).first
        }
        return find(view)!
    }
}
