import UIKit
import XCTest
@testable import UIComponents

@available(iOS 26.0, *)
@MainActor
final class VerticalTabBarTests: XCTestCase {
    func testConstrainedBarCentersSelectionAndKeepsManualScrollUntilSelectionOrResize() throws {
        let (window, bar) = makeBar(titles: ["Wallet", "Market", "Explore", "Agent", "Futures", "More"])
        defer { bar.cancelInteraction(); window.isHidden = true }
        bar.frame.size.height = 122
        bar.layoutIfNeeded()
        let scrollView = try XCTUnwrap(findScrollView(in: bar))
        XCTAssertEqual(scrollView.bounds.height, 122)
        XCTAssertEqual(scrollView.contentSize.height, 312)
        bar.select(3, animated: false)
        XCTAssertEqual(scrollView.contentOffset.y, 120, accuracy: 0.5)
        let selectedTarget = target("tab-3", in: bar)
        XCTAssertEqual(selectedTarget.convert(selectedTarget.bounds, to: bar).midY, bar.bounds.midY, accuracy: 0.5)

        scrollView.contentOffset.y = 170
        bar.setNeedsLayout()
        bar.layoutIfNeeded()
        XCTAssertEqual(scrollView.contentOffset.y, 170, accuracy: 0.5)
        bar.frame.size.height = 162
        bar.layoutIfNeeded()
        XCTAssertEqual(scrollView.contentOffset.y, 100, accuracy: 0.5)
        bar.select(5, animated: false)
        XCTAssertEqual(scrollView.contentOffset.y, 150, accuracy: 0.5)
        bar.select(0, animated: false)
        XCTAssertEqual(scrollView.contentOffset.y, 0, accuracy: 0.5)
    }

    func testTapAfterScrollingSelectsTheVisibleTab() throws {
        let (window, bar) = makeBar(titles: ["Wallet", "Market", "Explore", "Agent", "Futures"])
        defer { bar.cancelInteraction(); window.isHidden = true }
        bar.frame.size.height = 122
        bar.layoutIfNeeded()
        let scrollView = try XCTUnwrap(findScrollView(in: bar))
        scrollView.contentOffset.y = 100
        var selections: [Int] = []
        bar.onSelect = { index, _ in selections.append(index) }
        bar.beginScrub(at: CGPoint(x: 24, y: 81))
        bar.finishScrub(cancelled: false)
        XCTAssertEqual(bar.selectedIndex, 3)
        XCTAssertEqual(selections, [3])
    }

    func testConstrainedHoldRevealsEveryTabAndRestoresViewportOnCancellation() async throws {
        let (window, bar) = makeBar(titles: ["Wallet", "Market", "Explore", "Agent", "Futures", "More"])
        defer { bar.cancelInteraction(); window.isHidden = true }
        bar.frame.size.height = 122
        bar.expansionBounds = CGRect(x: -394, y: -64, width: 466, height: 430)
        bar.layoutIfNeeded()
        bar.select(3, animated: false)
        let scrollView = try XCTUnwrap(findScrollView(in: bar))
        var expandedFrames: [CGRect?] = []
        bar.onExpandedFrameChange = { expandedFrames.append($0) }
        bar.beginScrub(at: CGPoint(x: 24, y: 61))
        try await Task.sleep(for: .milliseconds(350))

        let expandedFrame = try XCTUnwrap(expandedFrames.last ?? nil)
        XCTAssertGreaterThan(expandedFrame.height, bar.bounds.height)
        XCTAssertGreaterThanOrEqual(expandedFrame.minY, -64)
        XCTAssertLessThanOrEqual(expandedFrame.maxY, 366)
        XCTAssertEqual(scrollView.bounds.height, scrollView.contentSize.height)
        XCTAssertEqual(scrollView.contentOffset.y, 0)
        XCTAssertFalse(scrollView.isScrollEnabled)
        for id in bar.itemIds {
            let item = target(id, in: bar)
            XCTAssertTrue(expandedFrame.contains(item.convert(item.bounds, to: bar)))
        }

        bar.finishScrub(cancelled: true)
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertNil(expandedFrames.last!)
        XCTAssertEqual(bar.selectedIndex, 3)
        XCTAssertEqual(scrollView.bounds.height, 122)
        XCTAssertEqual(scrollView.contentOffset.y, 120, accuracy: 0.5)
        XCTAssertTrue(scrollView.isScrollEnabled)
    }

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

    func testExpandedDragAfterScrollingTargetsTheRowUnderTheFinger() async throws {
        for isReordering in [false, true] {
            let (window, bar) = makeBar(titles: ["Wallet", "Market", "Explore", "Agent", "Futures", "More"])
            defer { bar.cancelInteraction(); window.isHidden = true }
            bar.frame.size.height = 122
            bar.expansionBounds = CGRect(x: -394, y: -64, width: 466, height: 430)
            bar.layoutIfNeeded()
            bar.select(3, animated: false)
            var moves: [(Int, Int)] = []
            var selections: [Int] = []
            bar.onSelect = { index, _ in selections.append(index) }
            if isReordering { bar.onReorder = { moves.append(($0, $1)) } }
            let initial = CGPoint(x: 24, y: 61)
            bar.beginScrub(at: initial)
            try await Task.sleep(for: .milliseconds(650))
            let destination = target("market", in: bar)
            let point = destination.convert(CGPoint(x: destination.bounds.midX, y: destination.bounds.midY), to: bar)
            bar.moveScrub(translation: CGPoint(x: point.x - initial.x, y: point.y - initial.y))
            bar.finishScrub(cancelled: false)

            if isReordering {
                XCTAssertEqual(moves.map { $0.0 }, [3])
                XCTAssertEqual(moves.map { $0.1 }, [1])
                XCTAssertEqual(bar.itemIds[1], "tab-3")
                XCTAssertTrue(selections.isEmpty)
            } else {
                XCTAssertEqual(selections, [1])
                XCTAssertEqual(bar.selectedIndex, 1)
            }
        }
    }

    func testOversizedExpandedListStaysInBoundsAndScrollsToBothEnds() async throws {
        let (window, bar) = makeBar(titles: (0..<10).map { "Tab \($0)" })
        defer { bar.cancelInteraction(); window.isHidden = true }
        bar.frame.size.height = 122
        let expansionBounds = CGRect(x: -394, y: -64, width: 466, height: 180)
        bar.expansionBounds = expansionBounds
        bar.layoutIfNeeded()
        bar.select(4, animated: false)
        let scrollView = try XCTUnwrap(findScrollView(in: bar))
        var expandedFrame: CGRect?
        bar.onExpandedFrameChange = { expandedFrame = $0 }
        let initial = CGPoint(x: 24, y: 61)
        bar.beginScrub(at: initial)
        try await Task.sleep(for: .milliseconds(650))

        let frame = try XCTUnwrap(expandedFrame)
        XCTAssertGreaterThanOrEqual(frame.minY, expansionBounds.minY)
        XCTAssertLessThanOrEqual(frame.maxY, expansionBounds.maxY)
        XCTAssertEqual(scrollView.bounds.height, expansionBounds.height)
        XCTAssertTrue(scrollView.clipsToBounds)
        XCTAssertTrue(scrollView.isScrollEnabled)
        XCTAssertGreaterThan(scrollView.contentOffset.y, 0)

        let top = scrollView.convert(CGPoint(x: scrollView.bounds.midX, y: scrollView.bounds.minY + 1), to: bar)
        bar.moveScrub(translation: CGPoint(x: top.x - initial.x, y: top.y - initial.y))
        try await Task.sleep(for: .seconds(1))
        XCTAssertEqual(scrollView.contentOffset.y, 0, accuracy: 0.5)
        let bottom = scrollView.convert(CGPoint(x: scrollView.bounds.midX, y: scrollView.bounds.maxY - 1), to: bar)
        bar.moveScrub(translation: CGPoint(x: bottom.x - initial.x, y: bottom.y - initial.y))
        try await Task.sleep(for: .seconds(2))
        XCTAssertEqual(scrollView.contentOffset.y, scrollView.contentSize.height - scrollView.bounds.height, accuracy: 0.5)
        bar.finishScrub(cancelled: false)
        XCTAssertEqual(bar.selectedIndex, 9)
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
        let ids = ["wallet", "market", "explore"]
        let bar = WVerticalTabBar(items: titles.enumerated().map { index, title in
            .init(id: index < ids.count ? ids[index] : "tab-\(index)", title: title, image: UIImage(systemName: "circle")!)
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

    private func findScrollView(in view: UIView) -> UIScrollView? {
        if let scrollView = view as? UIScrollView { return scrollView }
        return view.subviews.lazy.compactMap { self.findScrollView(in: $0) }.first
    }
}
