import UIKit
import XCTest
import WalletResources
@testable import UIComponents

@MainActor
final class SegmentedControlLensTests: XCTestCase {
    func testPagingWidthsRemainLiveWhileNativeLensLiftsAndLowers() async throws {
        guard #available(iOS 26, *) else { throw XCTSkip("Native lens requires iOS 26") }
        let lens = WSegmentedControlLensView()
        let (window, _) = host(lens)
        defer { window.isHidden = true }
        lens.frame = CGRect(x: 20, y: 100, width: 300, height: 24)
        let native = try XCTUnwrap(descendants(lens).first { String(describing: type(of: $0)) == PrivateAPI.liquidLensView.string })

        for (startWidth, endWidth) in [(CGFloat(80), CGFloat(160)), (160, 80)] {
            var selection = CGRect(x: 0, y: 0, width: startWidth, height: 24)
            lens.update(selectionFrame: selection, isLifted: false, color: .gray, animated: false)
            try await Task.sleep(for: .milliseconds(50))
            lens.update(selectionFrame: selection, isLifted: true, color: .gray, animated: true)
            for tick in 1...40 {
                try await Task.sleep(for: .milliseconds(20))
                let displayed = try XCTUnwrap(native.layer.presentation()).bounds
                // Lift adds the same inset to width and height. Their difference must
                // still follow the pager instead of retaining the width at lift-off.
                XCTAssertEqual(displayed.width - displayed.height, selection.width - selection.height, accuracy: 0.5)
                let progress = min(1, CGFloat(tick) / 30)
                selection = CGRect(x: progress * 100, y: 0, width: startWidth + (endWidth - startWidth) * progress, height: 24)
                if tick == 15 {
                    lens.update(selectionFrame: selection, isLifted: false, color: .gray, animated: true)
                }
                UIView.performWithoutAnimation {
                    lens.update(selectionFrame: selection, isLifted: tick < 15, color: .gray, animated: false)
                }
            }
            XCTAssertEqual(native.bounds.width, endWidth, accuracy: 0.5)
            XCTAssertEqual(native.bounds.height, 24, accuracy: 0.5)
        }
    }

    func testNativeLensIsAvailableAndHandlesRapidLiftChanges() async throws {
        guard #available(iOS 26, *) else { throw XCTSkip("Native lens requires iOS 26") }
        let lens = WSegmentedControlLensView()
        XCTAssertTrue(lens.usesNativeLens)
        let (window, _) = host(lens)
        defer { window.isHidden = true }
        lens.frame = CGRect(x: 20, y: 100, width: 300, height: 34)
        lens.update(selectionFrame: CGRect(x: 0, y: 0, width: 100, height: 34), isLifted: false, color: .gray, animated: false)
        lens.update(selectionFrame: CGRect(x: 100, y: 0, width: 100, height: 34), isLifted: true, color: .gray, animated: true)
        lens.update(selectionFrame: CGRect(x: 200, y: 0, width: 100, height: 34), isLifted: true, color: .gray, animated: true)
        lens.cancelAnimations()
        lens.update(selectionFrame: CGRect(x: 0, y: 0, width: 80, height: 34), isLifted: false, color: .gray, animated: false)
        try await Task.sleep(for: .milliseconds(500))
        let native = try XCTUnwrap(descendants(lens).first { String(describing: type(of: $0)) == PrivateAPI.liquidLensView.string })
        XCTAssertEqual(native.bounds.width, 80, accuracy: 0.5)
        XCTAssertEqual(native.center.x, 40, accuracy: 0.5)
        XCTAssertFalse(lens.isLifted)
    }

    func testFallbackMasksNormalAndSelectedContentAndClearsEmptySelection() {
        let lens = WSegmentedControlLensView(useNativeLens: false)
        lens.frame = CGRect(x: 0, y: 0, width: 300, height: 34)
        lens.update(selectionFrame: CGRect(x: 100, y: 0, width: 100, height: 34), isLifted: true, color: .gray, animated: false)
        XCTAssertFalse(lens.usesNativeLens)
        XCTAssertFalse(lens.isLifted)
        let normal = lens.contentView.layer.mask as! CAShapeLayer
        let selected = lens.selectedContentView.layer.mask as! CAShapeLayer
        XCTAssertFalse(normal.path!.contains(CGPoint(x: 150, y: 17), using: .evenOdd))
        XCTAssertTrue(normal.path!.contains(CGPoint(x: 50, y: 17), using: .evenOdd))
        XCTAssertTrue(selected.path!.contains(CGPoint(x: 150, y: 17)))
        XCTAssertFalse(selected.path!.contains(CGPoint(x: 50, y: 17)))
        lens.update(selectionFrame: nil, isLifted: false, color: .gray, animated: false)
        XCTAssertTrue(lens.selectedContentView.isHidden)
        XCTAssertTrue(normal.path!.contains(CGPoint(x: 150, y: 17), using: .evenOdd))
    }

    func testRTLMirrorsSelectionTitlesAndHitTargetsIncludingSwipeProgress() throws {
        let (control, model) = makeControl()
        let (window, _) = host(control)
        defer { window.isHidden = true }
        control.frame = CGRect(x: 20, y: 100, width: 306, height: 40)
        control.semanticContentAttribute = .forceRightToLeft
        control.layoutIfNeeded()
        let lens = try XCTUnwrap(descendants(control).compactMap { $0 as? WSegmentedControlLensView }.first)
        // The tabs are sized by their titles and run from the trailing edge of the capsule to its leading edge.
        let slots = try XCTUnwrap(control.accessibilityElements as? [UIView]).map { $0.convert($0.bounds, to: lens) }
        XCTAssertEqual(slots[0].maxX, lens.bounds.width, accuracy: 0.5)
        XCTAssertEqual(slots[1].maxX, slots[0].minX, accuracy: 0.5)
        XCTAssertEqual(slots[2].maxX, slots[1].minX, accuracy: 0.5)
        XCTAssertEqual(slots[2].minX, 0, accuracy: 0.5)
        XCTAssertEqual(try XCTUnwrap(lens.selectionFrame).minX, slots[0].minX, accuracy: 0.5)
        let first = try XCTUnwrap(control.hitTest(CGPoint(x: 253, y: 20), with: nil))
        XCTAssertEqual(first.accessibilityLabel, "Wallet")
        XCTAssertTrue(first.accessibilityTraits.contains(.selected))
        XCTAssertEqual(control.hitTest(CGPoint(x: 53, y: 20), with: nil)?.accessibilityLabel, "Explore")

        model.setRawProgress(0.5)
        control.applyPendingModelChangesWithoutAnimation()
        XCTAssertEqual(try XCTUnwrap(lens.selectionFrame).minX, (slots[0].minX + slots[1].minX) / 2, accuracy: 0.5)
        model.setRawProgress(2)
        control.applyPendingModelChangesWithoutAnimation()
        XCTAssertEqual(try XCTUnwrap(lens.selectionFrame).minX, 0, accuracy: 0.5)
        let last = try XCTUnwrap(control.hitTest(CGPoint(x: 53, y: 20), with: nil))
        XCTAssertTrue(last.accessibilityTraits.contains(.selected))
        XCTAssertEqual(control.accessibilityElements?.count, 3)
        XCTAssertTrue(lens.selectedContentView.accessibilityElementsHidden)
    }

    func testOverflowKeepsBothTitleCopiesAlignedAndSelectedTabVisibleInRTL() throws {
        let (control, model) = makeControl(titles: ["A very long wallet title", "A very long market title", "A very long explorer title"])
        let (window, _) = host(control)
        defer { window.isHidden = true }
        control.frame = CGRect(x: 20, y: 100, width: 260, height: 40)
        control.semanticContentAttribute = .forceRightToLeft
        control.layoutIfNeeded()
        control.applyPendingModelChangesWithoutAnimation()
        let scroll = try XCTUnwrap(descendants(control).compactMap { $0 as? UIScrollView }.first)
        XCTAssertTrue(scroll.isScrollEnabled)
        XCTAssertGreaterThan(scroll.contentOffset.x, 0)
        let lens = try XCTUnwrap(descendants(control).compactMap { $0 as? WSegmentedControlLensView }.first)
        let normalLabels = descendants(lens.contentView).compactMap { $0 as? UILabel }
        let selectedLabels = descendants(lens.selectedContentView).compactMap { $0 as? UILabel }
        for label in normalLabels {
            let selected = try XCTUnwrap(selectedLabels.first { $0.text == label.text })
            XCTAssertEqual(label.convert(label.bounds, to: control).midX, selected.convert(selected.bounds, to: control).midX, accuracy: 0.5)
        }
        model.setRawProgress(2)
        control.applyPendingModelChangesWithoutAnimation()
        control.beginReplacementCrossfade()
        control.applyPendingModelChangesWithoutAnimation()
        control.endReplacementCrossfade()
        XCTAssertEqual(scroll.contentOffset.x, 0, accuracy: 0.5)
        XCTAssertEqual(try XCTUnwrap(lens.selectionFrame).minX, 0, accuracy: 1)
    }

    func testReplacementRemovesStaleTitlesAndResetsNativeSelection() async throws {
        let (control, model) = makeControl()
        let (window, _) = host(control)
        defer { window.isHidden = true }
        control.frame = CGRect(x: 20, y: 100, width: 306, height: 40)
        control.layoutIfNeeded()
        let target = try XCTUnwrap(control.hitTest(CGPoint(x: 253, y: 20), with: nil))
        XCTAssertTrue(target.accessibilityActivate())
        control.beginReplacementCrossfade()
        model.setItems(items(["New"]))
        control.applyPendingModelChangesWithoutAnimation()
        control.endReplacementCrossfade()
        try await Task.sleep(for: .milliseconds(400))
        let lens = try XCTUnwrap(descendants(control).compactMap { $0 as? WSegmentedControlLensView }.first)
        XCTAssertEqual(try XCTUnwrap(lens.selectionFrame).width, 300, accuracy: 0.5)
        XCTAssertFalse(lens.isLifted)
        XCTAssertEqual(control.accessibilityElements?.count, 1)
        XCTAssertEqual(control.hitTest(CGPoint(x: 150, y: 20), with: nil)?.accessibilityLabel, "New")
        XCTAssertEqual(descendants(control).compactMap { ($0 as? UILabel)?.text }.filter { $0 != "New" }, [])
    }

    func testResizingFromSpreadTabsToOverflowPreservesSelectionAndMenuAnchor() throws {
        let (control, model) = makeControl()
        let (window, _) = host(control)
        defer { window.isHidden = true }
        model.setRawProgress(2)
        control.frame = CGRect(x: 20, y: 100, width: 306, height: 40)
        control.applyPendingModelChangesWithoutAnimation()
        let lens = try XCTUnwrap(descendants(control).compactMap { $0 as? WSegmentedControlLensView }.first)
        // The tabs that fit share the room their titles leave, so the last one ends at the capsule's edge.
        let spread = try XCTUnwrap(lens.selectionFrame)
        XCTAssertEqual(spread.maxX, lens.bounds.width, accuracy: 0.5)
        control.frame.size.width = 160
        control.layoutIfNeeded()
        let scroll = try XCTUnwrap(descendants(control).compactMap { $0 as? UIScrollView }.first)
        XCTAssertTrue(scroll.isScrollEnabled)
        let anchor = try XCTUnwrap(control.contextMenuActivationView(forItemId: "2"))
        let frame = try XCTUnwrap(lens.selectionFrame)
        XCTAssertEqual(anchor.convert(anchor.bounds, to: lens).minX, frame.minX, accuracy: 0.5)
        XCTAssertEqual(anchor.bounds.width, frame.width, accuracy: 0.5)
        XCTAssertLessThanOrEqual(frame.maxX, lens.bounds.maxX + 1)
        control.frame.size.width = 306
        control.layoutIfNeeded()
        XCTAssertFalse(scroll.isScrollEnabled)
        XCTAssertEqual(try XCTUnwrap(lens.selectionFrame).minX, spread.minX, accuracy: 0.5)
        XCTAssertEqual(try XCTUnwrap(lens.selectionFrame).width, spread.width, accuracy: 0.5)
        XCTAssertEqual(model.selection?.effectiveSelectedItemID, "2")
    }

    private func makeControl(titles: [String] = ["Wallet", "Market", "Explore"]) -> (WSegmentedControl, SegmentedControlModel) {
        _ = WalletResourcesBundle.bundle.load()
        let model = SegmentedControlModel(items: items(titles), selection: .init(item1: "0"), style: .compactRootHeader)
        model.onSelect = { [weak model] in model?.selection = .init(item1: $0.id) }
        return (WSegmentedControl(model: model, isGlassInteractive: true), model)
    }

    private func items(_ titles: [String]) -> [SegmentedControlItem] {
        titles.enumerated().map { .init(id: String($0.offset), title: $0.element, viewController: Content()) }
    }

    private func host(_ view: UIView) -> (UIWindow, UIViewController) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        let controller = UIViewController()
        window.rootViewController = controller
        controller.view.backgroundColor = .systemBackground
        controller.view.addSubview(view)
        window.makeKeyAndVisible()
        return (window, controller)
    }

    private func descendants(_ view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }

    private final class Content: UIViewController, WSegmentedControllerContent {
        var onScroll: ((CGFloat) -> Void)?
        var scrollingView: UIScrollView? { nil }
        func scrollToTop(animated: Bool) {}
        func calculateHeight(isHosted: Bool) -> CGFloat { 800 }
    }
}
