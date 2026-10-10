import UIKit
import XCTest
import WalletResources
@testable import UIComponents

@MainActor
final class PagerSelectionProgressTests: XCTestCase {
    func testRootPagingProgressPerformance() {
        _ = WalletResourcesBundle.bundle.load()
        let model = SegmentedControlModel(items: makeItems(), selection: .init(item1: "0"), style: .compactRootHeader)
        let control = WSegmentedControl(model: model, isGlassInteractive: true)
        let window = host(UIViewController(), control: control)
        defer { window.isHidden = true }
        control.layoutIfNeeded()
        measure(metrics: [XCTClockMetric()]) {
            for frame in 0..<240 {
                control.setPagingProgress(CGFloat(frame % 120) / 60)
            }
        }
    }

    func testRootPagingProgressAllowsSubsequentModelChangesAndResizing() async throws {
        for rtl in [false, true] {
            _ = WalletResourcesBundle.bundle.load()
            let model = SegmentedControlModel(items: makeItems(), selection: .init(item1: "0"), style: .compactRootHeader)
            let control = WSegmentedControl(model: model, isGlassInteractive: true)
            let window = host(UIViewController(), control: control, rtl: rtl)
            defer { window.isHidden = true }
            let lens = try XCTUnwrap(descendants(control).compactMap { $0 as? WSegmentedControlLensView }.first)
            control.setPagingProgress(0.5)
            XCTAssertEqual(try XCTUnwrap(lens.selectionFrame).minX, rtl ? 150 : 50, accuracy: 0.5)
            // A model change arriving before the pager's queued observation must win.
            model.selection = .init(item1: "2")
            try await Task.sleep(for: .milliseconds(30))
            XCTAssertEqual(try XCTUnwrap(lens.selectionFrame).minX, rtl ? 0 : 200, accuracy: 0.5)

            control.frame.size.width = 606
            control.setPagingProgress(1.25)
            XCTAssertEqual(try XCTUnwrap(lens.selectionFrame).minX, rtl ? 150 : 250, accuracy: 0.5)
            model.setItems(Array(makeItems().prefix(2)))
            control.setPagingProgress(0.5)
            try await Task.sleep(for: .milliseconds(30))
            XCTAssertEqual(try XCTUnwrap(lens.selectionFrame).minX, 150, accuracy: 0.5)
            XCTAssertEqual(control.accessibilityElements?.count, 2)
        }
    }

    func testRootPagerDrivesTheEntireNonAdjacentLensMovement() async throws {
        for rtl in [false, true] {
            _ = WalletResourcesBundle.bundle.load()
            let items = makeItems()
            let model = SegmentedControlModel(items: items, selection: .init(item1: "0"), style: .compactRootHeader)
            let control = WSegmentedControl(model: model, isGlassInteractive: true)
            let pager = WPagerViewController(pages: items.map { item in
                .init(id: item.id) { item.viewController as! UIViewController }
            }, preloadsPages: true)
            pager.onProgressChanged = { [weak control] in control?.setPagingProgress($0.logicalOffset) }
            pager.onSelectionChanged = { [weak control] in control?.setPagingProgress(CGFloat($0)) }
            model.onSelect = { [weak pager] in pager?.select(index: Int($0.id)!, animated: true) }
            let root = UIViewController()
            root.addChild(pager)
            root.view.addSubview(pager.view)
            pager.view.frame = CGRect(x: 0, y: 150, width: 402, height: 600)
            pager.didMove(toParent: root)
            let window = host(root, control: control, rtl: rtl)
            defer { window.isHidden = true }
            // Host appearance completes before a tab can animate.
            try await Task.sleep(for: .milliseconds(350))
            XCTAssertEqual(pager.children.count, 3)
            for (source, target) in [(0, 2), (2, 0)] {
                try activate(target, in: control)
                XCTAssertEqual(model.rawProgress, CGFloat(source))
                try await checkMovement(control, source: source, target: target, rtl: rtl)
                XCTAssertEqual(pager.selectedIndex, target)
                XCTAssertEqual(pager.children.filter { $0.view.superview?.isHidden == false }.count, 1)
            }
        }
    }

    func testRootLensAndVisibleContentStayTogetherDuringRepeatedInterruptedSwipes() throws {
        for rtl in [false, true] {
            _ = WalletResourcesBundle.bundle.load()
            let items = makeItems()
            let model = SegmentedControlModel(items: items, selection: .init(item1: "0"), style: .compactRootHeader)
            let control = WSegmentedControl(model: model, isGlassInteractive: true)
            let pager = WPagerViewController(pages: items.map { item in
                .init(id: item.id) { item.viewController as! UIViewController }
            }, preloadsPages: true)
            pager.onProgressChanged = { [weak control] in control?.setPagingProgress($0.logicalOffset) }
            pager.onSelectionChanged = { [weak control] in control?.setPagingProgress(CGFloat($0)) }
            let root = UIViewController()
            root.addChild(pager)
            root.view.addSubview(pager.view)
            pager.view.frame = CGRect(x: 0, y: 150, width: 402, height: 600)
            pager.didMove(toParent: root)
            let window = host(root, control: control, rtl: rtl)
            defer { window.isHidden = true }
            let scroll = pager.scrollView!
            let width = scroll.bounds.width
            let initial = scroll.contentOffset.x
            let sign: CGFloat = rtl ? -1 : 1
            for position in [0.75, 1.6, 0.4, 1.85, 0.9, 0.1, 1.4] {
                pager.scrollViewWillBeginDragging(scroll)
                scroll.contentOffset.x = initial + sign * position * width
                pager.scrollViewDidEndDragging(scroll, willDecelerate: true)
                control.setNeedsLayout()
                control.layoutIfNeeded()
                XCTAssertEqual(try XCTUnwrap(model.rawProgress), position, accuracy: 0.001)
                let visible = items.indices.filter {
                    (items[$0].viewController as! UIViewController).viewIfLoaded?.superview?.isHidden == false
                }
                XCTAssertEqual(visible, [Int(floor(position)), Int(ceil(position))])
                let before = scroll.contentOffset
                pager.scrollViewWillBeginDragging(scroll)
                XCTAssertEqual(try XCTUnwrap(model.rawProgress), position, accuracy: 0.001)
                XCTAssertEqual(scroll.contentOffset, before)
            }
            scroll.contentOffset.x = initial + sign * 2 * width
            pager.scrollViewDidEndDragging(scroll, willDecelerate: false)
            XCTAssertEqual(pager.selectedIndex, 2)
            XCTAssertEqual(model.rawProgress, 2)
            XCTAssertTrue((items[0].viewController as! UIViewController).view.superview!.isHidden)
            XCTAssertTrue((items[1].viewController as! UIViewController).view.superview!.isHidden)
            XCTAssertFalse((items[2].viewController as! UIViewController).view.superview!.isHidden)
        }
    }

    func testWalletAssetsBridgeOffsetNeverBecomesTheLensOffset() async throws {
        for rtl in [false, true] {
            _ = WalletResourcesBundle.bundle.load()
            let items = makeItems()
            let pager = WSegmentedPagerView(items: items.map {
                .init(id: $0.id, title: $0.title, viewController: $0.viewController)
            }, style: .compactRootHeader)
            let root = UIViewController()
            root.view.addSubview(pager)
            pager.translatesAutoresizingMaskIntoConstraints = true
            pager.frame = CGRect(x: 20, y: 100, width: 306, height: 500)
            pager.semanticContentAttribute = rtl ? .forceRightToLeft : .forceLeftToRight
            pager.segmentedControl.semanticContentAttribute = pager.semanticContentAttribute
            let window = host(root, rtl: rtl)
            defer { window.isHidden = true }
            pager.layoutIfNeeded()
            let scroll = try XCTUnwrap(pager.pagingGestureView as? UIScrollView)
            var heightRequests: [(CGFloat, Bool)] = []
            pager.onScrollProgressChanged = { heightRequests.append(($0, $1)) }
            for (source, target) in [(0, 2), (2, 0)] {
                heightRequests.removeAll()
                try activate(target, in: pager.segmentedControl)
                XCTAssertEqual(pager.model.rawProgress, CGFloat(source))
                XCTAssertEqual(scroll.contentOffset.x / scroll.bounds.width, 1, accuracy: 0.001)
                XCTAssertEqual(heightRequests.first?.0, CGFloat(target))
                XCTAssertEqual(heightRequests.first?.1, true)
                try await checkMovement(pager.segmentedControl, source: source, target: target, rtl: rtl)
                XCTAssertEqual(pager.selectedIndex, target)
                XCTAssertTrue(heightRequests.allSatisfy { $0.0 == CGFloat(target) })
            }
        }
    }

    func testWalletAssetsReturningToSourceCancelsAnInFlightJump() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let pager = WSegmentedPagerView(items: makeItems().map {
            .init(id: $0.id, title: $0.title, viewController: $0.viewController)
        })
        let root = UIViewController()
        root.view.addSubview(pager)
        pager.translatesAutoresizingMaskIntoConstraints = true
        pager.frame = CGRect(x: 0, y: 100, width: 306, height: 500)
        let window = host(root)
        defer { window.isHidden = true }
        pager.layoutIfNeeded()
        pager.handleSegmentChange(to: 2, animated: true)
        pager.handleSegmentChange(to: 0, animated: true)
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(pager.selectedIndex, 0)
        XCTAssertEqual(pager.model.rawProgress, 0)
    }

    private func checkMovement(_ control: WSegmentedControl, source: Int, target: Int, rtl: Bool) async throws {
        let lens = try XCTUnwrap(descendants(control).compactMap { $0 as? WSegmentedControlLensView }.first)
        let native = descendants(lens).first { String(describing: type(of: $0)) == String("weiVsneLdiuqiLIU_".reversed()) }
        var previous = CGFloat(source)
        var intermediateCount = 0
        for _ in 0..<24 {
            try await Task.sleep(for: .milliseconds(25))
            // A normal layout pass must not snap the selection ahead of the page.
            control.setNeedsLayout()
            control.layoutIfNeeded()
            let logical = try XCTUnwrap(control.model.rawProgress)
            XCTAssertGreaterThanOrEqual((logical - previous) * CGFloat(target - source), -0.001)
            XCTAssertGreaterThanOrEqual(logical, 0)
            XCTAssertLessThanOrEqual(logical, 2)
            if logical > 0.01, logical < 1.99 { intermediateCount += 1 }
            let frame = try XCTUnwrap(lens.selectionFrame)
            let expectedX = (rtl ? 2 - logical : logical) * 100
            XCTAssertEqual(frame.minX, expectedX, accuracy: 0.5)
            if let native { XCTAssertEqual(native.center.x, frame.midX, accuracy: 0.5) }
            previous = logical
        }
        XCTAssertGreaterThan(intermediateCount, 2)
        XCTAssertEqual(control.model.rawProgress, CGFloat(target))
    }

    private func activate(_ index: Int, in control: WSegmentedControl) throws {
        let targets = try XCTUnwrap(control.accessibilityElements as? [UIView])
        XCTAssertTrue(targets[index].accessibilityActivate())
    }

    private func makeItems() -> [SegmentedControlItem] {
        (0..<3).map { .init(id: String($0), title: "Page", viewController: Content()) }
    }

    private func host(_ root: UIViewController, control: WSegmentedControl? = nil, rtl: Bool = false) -> UIWindow {
        root.view.semanticContentAttribute = rtl ? .forceRightToLeft : .forceLeftToRight
        if #available(iOS 17.0, *) {
            root.traitOverrides.layoutDirection = rtl ? .rightToLeft : .leftToRight
        }
        if let control {
            root.view.addSubview(control)
            control.frame = CGRect(x: 20, y: 100, width: 306, height: 40)
            control.semanticContentAttribute = root.view.semanticContentAttribute
        }
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = root
        window.makeKeyAndVisible()
        root.view.layoutIfNeeded()
        return window
    }

    private func descendants(_ view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }

    private final class Content: UIViewController, WSegmentedControllerContent {
        var onScroll: ((CGFloat) -> Void)?
        var scrollingView: UIScrollView? { nil }
        func scrollToTop(animated: Bool) {}
        func calculateHeight(isHosted: Bool) -> CGFloat { 400 }
    }
}
