import ContextMenuKit
import UIKit
import XCTest
import WalletResources
@testable import UIComponents

@MainActor
final class SegmentedControlContextMenuTests: XCTestCase {
    func testActiveTabTapAndVoiceOverOpenTheWholeBarMenuWithoutReselecting() throws {
        guard #available(iOS 26, *) else { throw XCTSkip("Native popover requires iOS 26") }
        for style in [SegmentedControlStyle.compactRootHeader, .colorHeader] {
            let (control, model) = makeControl(style: style)
            let (window, controller) = host(control)
            defer {
                controller.dismiss(animated: false)
                window.isHidden = true
            }
            var selections: [String] = []
            model.onSelect = { [weak model] item in
                selections.append(item.id)
                model?.selection = .init(item1: item.id)
            }
            var menuRequests = 0
            control.longPressContextMenuProvider = SegmentedControlContextMenuProvider {
                menuRequests += 1
                return Self.configuration()
            }
            let targets = try XCTUnwrap(control.accessibilityElements as? [UIView])
            let active = targets[0]
            XCTAssertEqual(active.gestureRecognizers?.filter { $0 is UITapGestureRecognizer }.count, 1)
            let tap = NSSelectorFromString("handleSelectionTap")
            XCTAssertTrue(active.responds(to: tap))
            _ = active.perform(tap)
            XCTAssertNotNil(controller.presentedViewController)
            XCTAssertEqual(menuRequests, 1)
            XCTAssertTrue(selections.isEmpty)
            controller.dismiss(animated: false)

            XCTAssertTrue(targets[3].accessibilityActivate())
            control.applyPendingModelChangesWithoutAnimation()
            XCTAssertEqual(selections, ["3"])
            XCTAssertNil(controller.presentedViewController)
            XCTAssertTrue(targets[3].accessibilityActivate())
            XCTAssertNotNil(controller.presentedViewController)
            XCTAssertEqual(menuRequests, 2)
            XCTAssertEqual(selections, ["3"])
            controller.dismiss(animated: false)

            XCTAssertTrue(control.presentLongPressContextMenu())
            XCTAssertEqual(menuRequests, 3)
            controller.dismiss(animated: false)
            control.longPressContextMenuProvider = nil
            XCTAssertFalse(targets[3].gestureRecognizers?.contains { $0 is UITapGestureRecognizer } == true)
        }
    }

    func testWholeBarMenuPreservesOverflowScrollingAndItemTapMenu() throws {
        let (control, model) = makeControl(withItemMenu: true)
        let (window, _) = host(control)
        defer { window.isHidden = true }
        let scroll = try XCTUnwrap(descendants(control).compactMap { $0 as? UIScrollView }.first)
        let pan = scroll.panGestureRecognizer
        let panDelegate = pan.delegate
        let targets = try XCTUnwrap(control.accessibilityElements as? [UIView])

        for rtl in [false, true] {
            control.semanticContentAttribute = rtl ? .forceRightToLeft : .forceLeftToRight
            control.setNeedsLayout()
            control.layoutIfNeeded()
            control.longPressContextMenuAccessibilityLabel = "All Tabs"
            control.longPressContextMenuProvider = provider()
            let hold = try XCTUnwrap(control.gestureRecognizers?.compactMap { $0 as? UILongPressGestureRecognizer }.first)
            let selectedTap = try XCTUnwrap(targets[0].gestureRecognizers?.first { $0 is UITapGestureRecognizer })
            XCTAssertEqual(hold.minimumPressDuration, 0.25)
            XCTAssertEqual(control.gestureRecognizers?.filter { $0 is UILongPressGestureRecognizer }.count, 1)
            XCTAssertTrue(scroll.isScrollEnabled)
            XCTAssertTrue(scroll.panGestureRecognizer === pan)
            XCTAssertTrue(pan.delegate === panDelegate)
            XCTAssertFalse(hold.delegate?.gestureRecognizer?(hold, shouldRecognizeSimultaneouslyWith: pan) ?? true)
            XCTAssertTrue(hold.delegate?.gestureRecognizer?(hold, shouldBeRequiredToFailBy: selectedTap) ?? false)

            let tappedItem = try XCTUnwrap(targets[1].gestureRecognizers?.first { $0 is UITapGestureRecognizer })
            XCTAssertTrue(hold.delegate?.gestureRecognizer?(hold, shouldBeRequiredToFailBy: tappedItem) ?? false)
            // An item menu still opens on the selected tab; unselected tabs only select.
            XCTAssertTrue(targets[0].gestureRecognizers?.contains { $0 is UITapGestureRecognizer } == true)
            XCTAssertEqual(targets[1].gestureRecognizers?.filter { $0 is UITapGestureRecognizer }.count, 1)

            for progress: CGFloat in [0, 2.5, 4, 1, 0] {
                control.setPagingProgress(progress)
                XCTAssertEqual(model.rawProgress, progress)
            }
            scroll.contentOffset.x = min(80, scroll.contentSize.width - scroll.bounds.width)
            let offset = scroll.contentOffset
            control.longPressContextMenuProvider = provider()
            XCTAssertEqual(scroll.contentOffset, offset)
            XCTAssertNil(hold.view)
            XCTAssertEqual(control.gestureRecognizers?.filter { $0 is UILongPressGestureRecognizer }.count, 1)

            control.longPressContextMenuProvider = nil
            XCTAssertFalse(control.gestureRecognizers?.contains { $0 is UILongPressGestureRecognizer } == true)
            XCTAssertTrue(scroll.isScrollEnabled)
            XCTAssertTrue(pan.delegate === panDelegate)
            XCTAssertTrue(targets.allSatisfy { $0.accessibilityCustomActions == nil })
        }
    }

    func testVoiceOverSelectionAndWholeBarPresentationRestoreSourceAndLens() async throws {
        guard #available(iOS 26, *) else { throw XCTSkip("Native popover requires iOS 26") }
        let (control, model) = makeControl()
        let (window, controller) = host(control)
        defer {
            controller.dismiss(animated: false)
            window.isHidden = true
        }
        let targets = try XCTUnwrap(control.accessibilityElements as? [UIView])
        let scroll = try XCTUnwrap(descendants(control).compactMap { $0 as? UIScrollView }.first)
        let barPan = scroll.panGestureRecognizer
        let barPanDelegate = barPan.delegate
        XCTAssertNil(control.longPressContextMenuProvider)
        XCTAssertTrue(targets[4].accessibilityActivate())
        control.applyPendingModelChangesWithoutAnimation()
        control.layoutIfNeeded()
        XCTAssertEqual(model.selectedItem?.id, "4")
        let selectedOffset = CGPoint(x: scroll.contentSize.width - scroll.bounds.width, y: 0)
        XCTAssertGreaterThan(selectedOffset.x, 0)
        // A discrete selection schedules its normal scroll after syncFromModel returns.
        try await waitUntil("Explore scroll settles before installing the menu") {
            scroll.contentOffset == selectedOffset
                && (scroll.layer.presentation()?.bounds.origin ?? scroll.bounds.origin) == selectedOffset
                && scroll.layer.animationKeys()?.isEmpty != false
        }
        XCTAssertEqual(scroll.contentOffset, selectedOffset)
        let selectedFrame = targets[4].convert(targets[4].bounds, to: scroll)
        XCTAssertGreaterThanOrEqual(selectedFrame.minX, scroll.bounds.minX - 0.5)
        XCTAssertLessThanOrEqual(selectedFrame.maxX, scroll.bounds.maxX + 0.5)
        XCTAssertNil(controller.presentedViewController)

        var menuRequests = 0
        control.longPressContextMenuAccessibilityLabel = "All Tabs"
        control.longPressContextMenuProvider = SegmentedControlContextMenuProvider {
            menuRequests += 1
            var configuration = Self.configuration()
            configuration.popoverUsesSourceViewBounds = true
            configuration.popoverDisablesInteractiveDismissal = true
            XCTAssertNil(configuration.popoverBackgroundMaterial)
            return configuration
        }
        XCTAssertTrue(targets.allSatisfy { $0.accessibilityCustomActions?.first?.name == "All Tabs" })
        XCTAssertEqual(menuRequests, 0)

        let lens = try XCTUnwrap(descendants(control).compactMap { $0 as? WSegmentedControlLensView }.first)
        let glass = try XCTUnwrap(descendants(control).compactMap { $0 as? UIVisualEffectView }.first {
            $0.effect is UIGlassEffect && lens.isDescendant(of: $0)
        })
        let originalGlassSuperview = glass.superview
        let scrollOffset = scroll.contentOffset
        let originalSuperview = control.superview
        let sourceFrame = control.frame
        XCTAssertEqual(glass.convert(glass.bounds, to: control), control.bounds)
        XCTAssertGreaterThan(control.intrinsicContentSize.width, control.bounds.width)
        let action = try XCTUnwrap(targets[4].accessibilityCustomActions?.first)
        let actionHandler = try XCTUnwrap(action.actionHandler)
        XCTAssertTrue(actionHandler(action))
        let menu = try XCTUnwrap(controller.presentedViewController)
        XCTAssertEqual(menuRequests, 1)
        XCTAssertTrue(menu.isModalInPresentation)
        XCTAssertTrue(menu.view.subviews.compactMap { $0 as? UIVisualEffectView }.isEmpty)
        XCTAssertNil(menu.preferredTransition)
        XCTAssertFalse(menu.view.gestureRecognizers?.contains {
            $0 is UIPanGestureRecognizer && $0.delegate === menu
        } == true)
        XCTAssertTrue(scroll.panGestureRecognizer === barPan)
        XCTAssertTrue(barPan.delegate === barPanDelegate)
        XCTAssertTrue(scroll.isScrollEnabled)
        let sourceItem = try XCTUnwrap(menu.popoverPresentationController?.sourceItem as? UIBarButtonItem)
        XCTAssertTrue(sourceItem.customView === glass)
        XCTAssertEqual(sourceItem.width, control.bounds.width)
        XCTAssertTrue(glass.superview === originalGlassSuperview)
        XCTAssertEqual(glass.convert(glass.bounds, to: control), control.bounds)
        XCTAssertTrue(control.superview === originalSuperview)
        XCTAssertEqual(control.frame, sourceFrame)
        XCTAssertEqual(scroll.contentOffset, scrollOffset)
        XCTAssertFalse(lens.isLifted)

        controller.dismiss(animated: false)
        XCTAssertNil(controller.presentedViewController)
        XCTAssertTrue(scroll.panGestureRecognizer === barPan)
        XCTAssertTrue(barPan.delegate === barPanDelegate)
        XCTAssertTrue(scroll.isScrollEnabled)
        XCTAssertTrue(control.superview === originalSuperview)
        XCTAssertEqual(control.frame, sourceFrame)
        XCTAssertTrue(glass.superview === originalGlassSuperview)
        XCTAssertEqual(scroll.contentOffset, scrollOffset)
        XCTAssertFalse(lens.isLifted)
        XCTAssertTrue(targets[0].accessibilityActivate())
        control.applyPendingModelChangesWithoutAnimation()
        XCTAssertEqual(model.selectedItem?.id, "0")
        XCTAssertEqual(menuRequests, 1)

        // Retain the first menu to prove disappearance cleared the interaction's session.
        XCTAssertTrue(actionHandler(action))
        XCTAssertEqual(menuRequests, 2)
        let reopenedMenu = try XCTUnwrap(controller.presentedViewController)
        XCTAssertFalse(reopenedMenu === menu)
        controller.dismiss(animated: false)
        XCTAssertNil(controller.presentedViewController)

        control.longPressContextMenuProvider = nil
        XCTAssertTrue(targets.allSatisfy { $0.accessibilityCustomActions == nil })
    }

    func testFundPopoverUsesSystemMaterialAndGlassSourceWithIndependentTheme() async throws {
        guard #available(iOS 27, *) else { throw XCTSkip("Color-header UIKit glass requires iOS 27") }
        let (control, _) = makeControl(style: .colorHeader)
        control.overrideUserInterfaceStyle = .dark
        control.glassUserInterfaceStyle = .dark
        let (window, controller) = host(control)
        defer {
            controller.dismiss(animated: false)
            window.isHidden = true
        }
        control.longPressContextMenuAccessibilityLabel = "All Chains"
        control.longPressContextMenuProvider = SegmentedControlContextMenuProvider {
            ContextMenuConfiguration(
                rootPage: ContextMenuPage(items: [.action(ContextMenuAction(title: "TON"))]),
                userInterfaceStyle: .light,
                popoverUsesSourceViewBounds: true,
                popoverDisablesInteractiveDismissal: true,
                popoverBackgroundMaterial: .systemMaterial
            )
        }
        let targets = try XCTUnwrap(control.accessibilityElements as? [UIView])
        let action = try XCTUnwrap(targets[0].accessibilityCustomActions?.first)
        let actionHandler = try XCTUnwrap(action.actionHandler)
        XCTAssertTrue(actionHandler(action))
        let menu = try XCTUnwrap(controller.presentedViewController)
        XCTAssertEqual(menu.view.traitCollection.userInterfaceStyle, .light)
        XCTAssertEqual(menu.view.backgroundColor, UIColor.clear)
        XCTAssertNil(menu.popoverPresentationController?.backgroundColor)
        XCTAssertFalse(menu.view.isOpaque)
        XCTAssertTrue(menu.isModalInPresentation)
        XCTAssertNil(menu.preferredTransition)
        menu.view.layoutIfNeeded()
        let material = try XCTUnwrap(menu.view.subviews.compactMap { $0 as? UIVisualEffectView }.first)
        XCTAssertTrue(material.effect is UIBlurEffect)
        XCTAssertFalse(material.isUserInteractionEnabled)
        XCTAssertEqual(material.frame, menu.view.bounds)
        XCTAssertEqual(material.traitCollection.userInterfaceStyle, .light)
        XCTAssertEqual(control.overrideUserInterfaceStyle, .dark)
        let lens = try XCTUnwrap(descendants(control).compactMap { $0 as? WSegmentedControlLensView }.first)
        let glass = try XCTUnwrap(descendants(control).compactMap { $0 as? UIVisualEffectView }.first {
            $0.effect is UIGlassEffect && lens.isDescendant(of: $0)
        })
        let sourceItem = try XCTUnwrap(menu.popoverPresentationController?.sourceItem as? UIBarButtonItem)
        XCTAssertTrue(sourceItem.customView === glass)
        XCTAssertEqual(sourceItem.width, control.bounds.width)

        XCTAssertEqual(glass.overrideUserInterfaceStyle, .dark)
        XCTAssertEqual(glass.traitCollection.userInterfaceStyle, .dark)
        XCTAssertEqual(lens.traitCollection.userInterfaceStyle, .dark)
        control.overrideUserInterfaceStyle = .light
        try await Task.sleep(for: .milliseconds(50))
        control.overrideUserInterfaceStyle = .dark
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(menu.view.traitCollection.userInterfaceStyle, .light)
        XCTAssertEqual(glass.traitCollection.userInterfaceStyle, .dark)
        XCTAssertEqual(lens.traitCollection.userInterfaceStyle, .dark)

        controller.dismiss(animated: false)
        XCTAssertNil(controller.presentedViewController)

        control.glassUserInterfaceStyle = .light
        XCTAssertEqual(glass.overrideUserInterfaceStyle, .light)
        control.glassUserInterfaceStyle = .dark
        XCTAssertEqual(glass.overrideUserInterfaceStyle, .dark)
        let originalSuperview = try XCTUnwrap(glass.superview)
        let originalIndex = try XCTUnwrap(originalSuperview.subviews.firstIndex(of: glass))
        let originalFrame = glass.frame
        let lightHost = UIView(frame: controller.view.bounds)
        lightHost.overrideUserInterfaceStyle = .light
        controller.view.addSubview(lightHost)
        defer {
            originalSuperview.insertSubview(glass, at: originalIndex)
            glass.frame = originalFrame
            lightHost.removeFromSuperview()
        }
        // Model the source being extracted from its wrapper during UIKit's transition.
        lightHost.addSubview(glass)
        XCTAssertEqual(lightHost.traitCollection.userInterfaceStyle, .light)
        XCTAssertEqual(glass.traitCollection.userInterfaceStyle, .dark)
        XCTAssertEqual(lens.traitCollection.userInterfaceStyle, .dark)
    }

    func testExplicitTintModeSurvivesGlassExtractionAndAutomaticRestoresInheritance() throws {
        guard #available(iOS 26, *) else { throw XCTSkip("Native glass requires iOS 26") }
        let (control, model) = makeControl()
        model.primaryColor = .tintColor
        model.selection = .init(item1: "3")
        let (window, controller) = host(control)
        defer { window.isHidden = true }
        window.tintColor = .systemTeal
        control.applyPendingModelChangesWithoutAnimation()
        let lens = try XCTUnwrap(descendants(control).compactMap { $0 as? WSegmentedControlLensView }.first)
        let glass = try XCTUnwrap(descendants(control).compactMap { $0 as? UIVisualEffectView }.first {
            $0.effect is UIGlassEffect && lens.isDescendant(of: $0)
        })
        let primaryLabel = try XCTUnwrap(descendants(lens.selectedContentView).compactMap { $0 as? UILabel }.first {
            $0.text == "Agent"
        })
        func selectedTitleColor() -> UIColor? {
            primaryLabel.textColor?.resolvedColor(with: primaryLabel.traitCollection)
        }
        func inheritedTint() -> UIColor {
            window.tintColor.resolvedColor(with: window.traitCollection)
        }

        // An untouched control still follows normal UIKit dimming.
        controller.view.tintAdjustmentMode = .dimmed
        XCTAssertEqual(control.tintAdjustmentMode, .dimmed)
        XCTAssertEqual(glass.tintAdjustmentMode, .dimmed)
        XCTAssertNotEqual(selectedTitleColor(), inheritedTint())
        controller.view.tintAdjustmentMode = .normal
        XCTAssertEqual(control.tintAdjustmentMode, .normal)
        XCTAssertEqual(glass.tintAdjustmentMode, .normal)
        XCTAssertEqual(selectedTitleColor(), inheritedTint())

        // Set normal while it is already the effective value, then change the parent.
        // Skipping this apparently redundant assignment would fail after extraction.
        control.tintAdjustmentMode = .normal
        controller.view.tintAdjustmentMode = .dimmed
        XCTAssertEqual(control.tintAdjustmentMode, .normal)
        XCTAssertEqual(glass.tintAdjustmentMode, .normal)
        XCTAssertEqual(selectedTitleColor(), inheritedTint())

        let originalSuperview = try XCTUnwrap(glass.superview)
        let originalIndex = try XCTUnwrap(originalSuperview.subviews.firstIndex(of: glass))
        let originalFrame = glass.frame
        let extractedHost = UIView(frame: controller.view.bounds)
        extractedHost.tintAdjustmentMode = .dimmed
        controller.view.addSubview(extractedHost)
        defer {
            originalSuperview.insertSubview(glass, at: originalIndex)
            glass.frame = originalFrame
            extractedHost.removeFromSuperview()
        }
        extractedHost.addSubview(glass)
        XCTAssertEqual(extractedHost.tintAdjustmentMode, .dimmed)
        XCTAssertEqual(glass.tintAdjustmentMode, .normal)
        XCTAssertEqual(lens.tintAdjustmentMode, .normal)
        XCTAssertEqual(selectedTitleColor(), inheritedTint())

        // Keep the app's inherited color, including changes while the source is detached.
        // Expectations use the window's current tint, not a fixed RGB or a cached blue.
        for tint in [UIColor.systemPurple, UIColor.systemOrange] {
            window.tintColor = tint
            XCTAssertEqual(control.tintColor, window.tintColor)
            XCTAssertEqual(glass.tintColor, window.tintColor)
            XCTAssertEqual(lens.tintColor, window.tintColor)
            XCTAssertEqual(selectedTitleColor(), inheritedTint())
        }

        // Resetting automatic must remove the explicit override from the detached source.
        control.tintAdjustmentMode = .automatic
        XCTAssertEqual(control.tintAdjustmentMode, .dimmed)
        XCTAssertEqual(glass.tintAdjustmentMode, .dimmed)
        XCTAssertEqual(glass.tintColor, extractedHost.tintColor)
        XCTAssertEqual(selectedTitleColor(), control.tintColor.resolvedColor(with: control.traitCollection))
        XCTAssertNotEqual(selectedTitleColor(), inheritedTint())
        extractedHost.tintAdjustmentMode = .normal
        XCTAssertEqual(glass.tintAdjustmentMode, .normal)
        XCTAssertEqual(glass.tintColor, window.tintColor)
        extractedHost.tintAdjustmentMode = .dimmed
        XCTAssertEqual(glass.tintAdjustmentMode, .dimmed)
    }

    func testExplicitSourcePortalKeepsItsSourceForInteractiveGlassControl() async throws {
        guard #available(iOS 26, *) else { throw XCTSkip("Native popover requires iOS 26") }
        let (control, _) = makeControl()
        let (window, controller) = host(control)
        defer {
            controller.dismiss(animated: false)
            window.isHidden = true
        }
        control.longPressContextMenuProvider = SegmentedControlContextMenuProvider(
            sourcePortal: ContextMenuSourcePortal(sourceViewProvider: { [weak control] in control }),
            configuration: Self.configuration
        )
        XCTAssertTrue(control.presentLongPressContextMenu())
        let menu = try XCTUnwrap(controller.presentedViewController)
        XCTAssertTrue((menu.popoverPresentationController?.sourceItem as? UIBarButtonItem)?.customView === control)
        controller.dismiss(animated: false)
        XCTAssertNil(controller.presentedViewController)
    }

    private func makeControl(withItemMenu: Bool = false, isGlassInteractive: Bool = true, style: SegmentedControlStyle = .compactRootHeader) -> (WSegmentedControl, SegmentedControlModel) {
        _ = WalletResourcesBundle.bundle.load()
        let itemMenu = withItemMenu ? provider() : nil
        let model = SegmentedControlModel(
            items: ["Wallet", "Market", "Futures", "Agent", "Explore"].enumerated().map {
                SegmentedControlItem(id: String($0.offset), title: $0.element, contextMenuProvider: itemMenu, viewController: Content())
            },
            selection: .init(item1: "0"),
            style: style
        )
        model.onSelect = { [weak model] in model?.selection = .init(item1: $0.id) }
        return (WSegmentedControl(model: model, isGlassInteractive: isGlassInteractive), model)
    }

    private func provider() -> SegmentedControlContextMenuProvider {
        SegmentedControlContextMenuProvider { Self.configuration() }
    }

    private static func configuration() -> ContextMenuConfiguration {
        ContextMenuConfiguration(rootPage: ContextMenuPage(items: [.action(ContextMenuAction(title: "Fixture option"))]))
    }

    private func host(_ control: WSegmentedControl) -> (UIWindow, PresentationHost) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        let controller = PresentationHost()
        window.rootViewController = controller
        controller.view.backgroundColor = .systemBackground
        controller.view.addSubview(control)
        control.frame = CGRect(x: 20, y: 100, width: 234, height: 40)
        window.makeKeyAndVisible()
        control.layoutIfNeeded()
        return (window, controller)
    }

    private func descendants(_ view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }

    private func waitUntil(
        _ description: String,
        file: StaticString = #filePath,
        line: UInt = #line,
        condition: () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while !condition() {
            guard ContinuousClock.now < deadline else {
                XCTFail("Timed out waiting for \(description)", file: file, line: line)
                throw WaitFailure.timeout
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private enum WaitFailure: Error { case timeout }

    // Hostless package tests cannot complete UIKit's modal presentation lifecycle.
    // Embed the real menu to check its structural contract and disappearance cleanup;
    // native modal animation is verified separately in the MyLab app host.
    private final class PresentationHost: UIViewController {
        private var menuController: UIViewController?

        override var presentedViewController: UIViewController? { menuController }
        override var shouldAutomaticallyForwardAppearanceMethods: Bool { false }

        override func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)? = nil) {
            XCTAssertNil(menuController)
            addChild(viewControllerToPresent)
            viewControllerToPresent.loadViewIfNeeded()
            viewControllerToPresent.beginAppearanceTransition(true, animated: false)
            viewControllerToPresent.view.frame = CGRect(origin: .zero, size: viewControllerToPresent.preferredContentSize)
            view.addSubview(viewControllerToPresent.view)
            viewControllerToPresent.didMove(toParent: self)
            viewControllerToPresent.view.setNeedsLayout()
            viewControllerToPresent.view.layoutIfNeeded()
            viewControllerToPresent.endAppearanceTransition()
            menuController = viewControllerToPresent
            completion?()
        }

        override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
            guard let menuController else {
                completion?()
                return
            }
            menuController.willMove(toParent: nil)
            menuController.beginAppearanceTransition(false, animated: false)
            menuController.view.removeFromSuperview()
            menuController.endAppearanceTransition()
            menuController.removeFromParent()
            self.menuController = nil
            completion?()
        }
    }

    private final class Content: UIViewController, WSegmentedControllerContent {
        var onScroll: ((CGFloat) -> Void)?
        var scrollingView: UIScrollView? { nil }
        func scrollToTop(animated: Bool) {}
        func calculateHeight(isHosted: Bool) -> CGFloat { 0 }
    }
}
