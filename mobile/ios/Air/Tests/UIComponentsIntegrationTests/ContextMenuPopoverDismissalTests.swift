import UIKit
import XCTest
@testable import ContextMenuKit

@MainActor
final class ContextMenuPopoverDismissalTests: XCTestCase {
    func testAnchoredPopoverReceivesOutsideHitsInItsActivePresentationContainer() throws {
        guard #available(iOS 26, *) else { throw XCTSkip("Native popover requires iOS 26") }
        let fixture = makeMenu()
        defer { fixture.cleanUp() }
        let menu = fixture.menu
        let backdrop = try XCTUnwrap(fixture.container.subviews.compactMap { $0 as? UIControl }.first)
        XCTAssertTrue(fixture.outsideHitBeforeAppearance === fixture.underlyingControl)
        XCTAssertTrue(menu.isModalInPresentation)
        XCTAssertNil(menu.preferredTransition)
        XCTAssertTrue(backdrop.superview === fixture.container)
        XCTAssertTrue(fixture.container.subviews.first === backdrop)
        XCTAssertEqual(backdrop.frame, fixture.container.bounds)
        XCTAssertEqual(backdrop.backgroundColor, UIColor.clear)
        XCTAssertFalse(backdrop.isOpaque)
        XCTAssertFalse(backdrop.isAccessibilityElement)
        XCTAssertTrue(fixture.window.hitTest(CGPoint(x: 20, y: 700), with: nil) === backdrop)
        XCTAssertTrue(fixture.container.hitTest(CGPoint(x: 20, y: 700), with: nil) === backdrop)
        XCTAssertTrue(fixture.window.hitTest(CGPoint(x: 100, y: 150), with: nil)?.isDescendant(of: menu.view) == true)
        XCTAssertTrue(fixture.window.hitTest(CGPoint(x: 46, y: 96), with: nil) === fixture.chrome)
        XCTAssertFalse(backdrop.point(inside: CGPoint(x: 46, y: 96), with: nil))
        XCTAssertFalse(backdrop.point(inside: CGPoint(x: 100, y: 150), with: nil))
        XCTAssertFalse(backdrop.point(inside: CGPoint(x: -1, y: 700), with: nil))
        XCTAssertFalse(fixture.window.subviews.contains { $0 === backdrop })
        XCTAssertFalse(menu.presentationController?.containerView?.subviews.contains { $0 === backdrop } == true)
        let activePopover = try XCTUnwrap(menu.activePresentationController as? UIPopoverPresentationController)
        XCTAssertEqual(activePopover.passthroughViews?.count, 1)
        XCTAssertTrue(activePopover.passthroughViews?.first === backdrop)
        XCTAssertTrue(fixture.container.gestureRecognizers?.isEmpty != false)

        let contentScroll = UIScrollView(frame: menu.view.bounds)
        menu.view.addSubview(contentScroll)
        XCTAssertTrue(fixture.window.hitTest(CGPoint(x: 100, y: 150), with: nil) === contentScroll)
        XCTAssertTrue(contentScroll.isScrollEnabled)
        XCTAssertFalse(contentScroll.panGestureRecognizer.view === backdrop)
        contentScroll.removeFromSuperview()

        menu.viewDidAppear(false)
        menu.viewDidLayoutSubviews()
        XCTAssertEqual(fixture.container.subviews.compactMap { $0 as? UIControl }.count, 1)
        fixture.container.bounds.size = CGSize(width: 430, height: 900)
        menu.viewDidLayoutSubviews()
        XCTAssertEqual(backdrop.frame, fixture.container.bounds)
        XCTAssertEqual(menu.dismissalCount, 0)
    }

    func testOutsideBackdropDismissesOnceAndWaitsForSecondaryPresentation() throws {
        guard #available(iOS 26, *) else { throw XCTSkip("Native popover requires iOS 26") }
        let fixture = makeMenu()
        defer { fixture.cleanUp() }
        let menu = fixture.menu
        let backdrop = try XCTUnwrap(fixture.container.subviews.compactMap { $0 as? UIControl }.first)
        menu.testPresentedController = UIViewController()
        try invokeRegisteredOutsideAction(backdrop)
        XCTAssertEqual(menu.dismissalCount, 0)
        menu.testPresentedController = nil
        try invokeRegisteredOutsideAction(backdrop)
        try invokeRegisteredOutsideAction(backdrop)
        XCTAssertEqual(menu.dismissalCount, 1)
        XCTAssertNil(backdrop.superview)
        XCTAssertNil((menu.activePresentationController as? UIPopoverPresentationController)?.passthroughViews)
    }

    func testAnchoredPopoverEscapeAndRowActionsDismissOnceAndRemoveBackdrop() throws {
        guard #available(iOS 26, *) else { throw XCTSkip("Native popover requires iOS 26") }
        let escapeFixture = makeMenu()
        defer { escapeFixture.cleanUp() }
        let escapeMenu = escapeFixture.menu
        let escapeBackdrop = try XCTUnwrap(escapeFixture.container.subviews.compactMap { $0 as? UIControl }.first)
        XCTAssertTrue(escapeMenu.accessibilityPerformEscape())
        XCTAssertTrue(escapeMenu.accessibilityPerformEscape())
        XCTAssertEqual(escapeMenu.dismissalCount, 1)
        XCTAssertNil(escapeBackdrop.superview)

        let rowFixture = makeMenu()
        defer { rowFixture.cleanUp() }
        let rowMenu = rowFixture.menu
        let rowBackdrop = try XCTUnwrap(rowFixture.container.subviews.compactMap { $0 as? UIControl }.first)
        let navigation = try XCTUnwrap(rowMenu.view.subviews.compactMap { $0 as? ContextMenuNavigationView }.first)
        var selections = 0
        let action = ContextMenuActivation(dismissesMenu: true, handler: { selections += 1 })
        rowMenu.navigationView(navigation, didActivate: action)
        rowMenu.navigationView(navigation, didActivate: action)
        XCTAssertEqual(rowMenu.dismissalCount, 1)
        XCTAssertEqual(selections, 1)
        XCTAssertNil(rowBackdrop.superview)
    }

    func testBackdropIsRemovedWhenThePopoverDisappearsOrReplacesContent() throws {
        guard #available(iOS 26, *) else { throw XCTSkip("Native popover requires iOS 26") }
        let fixture = makeMenu()
        defer { fixture.cleanUp() }
        let menu = fixture.menu
        let backdrop = try XCTUnwrap(fixture.container.subviews.compactMap { $0 as? UIControl }.first)
        menu.beginAppearanceTransition(false, animated: false)
        menu.endAppearanceTransition()
        XCTAssertNil(backdrop.superview)

        let replacementFixture = makeMenu()
        defer { replacementFixture.cleanUp() }
        let replacementMenu = replacementFixture.menu
        let replacementBackdrop = try XCTUnwrap(replacementFixture.container.subviews.compactMap { $0 as? UIControl }.first)
        replacementMenu.finishMenuForContentReplacement()
        replacementMenu.viewDidAppear(false)
        try invokeRegisteredOutsideAction(replacementBackdrop)
        XCTAssertNil(replacementBackdrop.superview)
        XCTAssertTrue(replacementFixture.container.subviews.compactMap { $0 as? UIControl }.isEmpty)
        XCTAssertEqual(replacementMenu.dismissalCount, 0)
    }

    func testBackdropExcludesContentWhenPresentedViewIncludesTheWholeWindow() throws {
        guard #available(iOS 26, *) else { throw XCTSkip("Native popover requires iOS 26") }
        let fixture = makeMenu(fullscreenPresentedView: true)
        defer { fixture.cleanUp() }
        let menu = fixture.menu
        let backdrop = try XCTUnwrap(fixture.container.subviews.compactMap { $0 as? UIControl }.first)
        XCTAssertTrue(fixture.window.hitTest(CGPoint(x: 20, y: 700), with: nil) === backdrop)
        XCTAssertTrue(fixture.window.hitTest(CGPoint(x: 100, y: 150), with: nil)?.isDescendant(of: menu.view) == true)
        XCTAssertFalse(backdrop.point(inside: CGPoint(x: 100, y: 150), with: nil))
    }

    func testDefaultPopoverKeepsNativeDismissalAndInstallsNoBackdrop() throws {
        guard #available(iOS 26, *) else { throw XCTSkip("Native popover requires iOS 26") }
        let fixture = makeMenu(disablesInteractiveDismissal: false)
        defer { fixture.cleanUp() }
        let menu = fixture.menu
        XCTAssertFalse(menu.isModalInPresentation)
        XCTAssertNil(menu.preferredTransition)
        XCTAssertTrue(fixture.container.subviews.compactMap { $0 as? UIControl }.isEmpty)
        XCTAssertTrue(fixture.window.hitTest(CGPoint(x: 20, y: 700), with: nil) === fixture.underlyingControl)
    }

    func testBackdropRestoresPassthroughViewsWithoutOverwritingAnotherOwner() throws {
        guard #available(iOS 26, *) else { throw XCTSkip("Native popover requires iOS 26") }
        let previousView = UIView()
        let fixture = makeMenu(passthroughViews: [previousView])
        defer { fixture.cleanUp() }
        let popover = try XCTUnwrap(fixture.menu.activePresentationController as? UIPopoverPresentationController)
        XCTAssertFalse(popover.passthroughViews?.contains { $0 === previousView } == true)
        fixture.menu.finishMenuForContentReplacement()
        XCTAssertEqual(popover.passthroughViews?.count, 1)
        XCTAssertTrue(popover.passthroughViews?.first === previousView)

        let otherFixture = makeMenu(passthroughViews: [previousView])
        defer { otherFixture.cleanUp() }
        let otherPopover = try XCTUnwrap(otherFixture.menu.activePresentationController as? UIPopoverPresentationController)
        let replacementView = UIView()
        otherPopover.passthroughViews = [replacementView]
        otherFixture.menu.finishMenuForContentReplacement()
        XCTAssertEqual(otherPopover.passthroughViews?.count, 1)
        XCTAssertTrue(otherPopover.passthroughViews?.first === replacementView)
    }

    private func invokeRegisteredOutsideAction(_ control: UIControl) throws {
        // Hostless XCTest has no UIApplication to dispatch UIControl.sendActions.
        // Exercise the registered action and its guards; app-host QA covers touch delivery.
        XCTAssertEqual(control.allTargets.count, 1)
        let target = try XCTUnwrap(control.allTargets.first as? NSObject)
        let actions = try XCTUnwrap(control.actions(forTarget: target, forControlEvent: .touchUpInside))
        XCTAssertEqual(actions.count, 1)
        let selector = NSSelectorFromString(try XCTUnwrap(actions.first))
        XCTAssertTrue(target.responds(to: selector))
        _ = target.perform(selector, with: control)
    }

    @available(iOS 26, *)
    private func makeMenu(disablesInteractiveDismissal: Bool = true, fullscreenPresentedView: Bool = false, passthroughViews: [UIView]? = nil) -> MenuFixture {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        let presenting = UIViewController()
        window.rootViewController = presenting
        presenting.view.frame = window.bounds
        window.addSubview(presenting.view)
        window.isHidden = false
        let underlyingControl = UIControl(frame: window.bounds)
        presenting.view.addSubview(underlyingControl)
        let container = PassthroughContainer(frame: window.bounds)
        // Like the real popover, this container is a sibling of the presenting screen.
        window.addSubview(container)
        let chrome = UIView(frame: CGRect(x: 44, y: 94, width: 306, height: 212))
        container.addSubview(chrome)
        let source = UIView(frame: CGRect(x: 20, y: 20, width: 160, height: 40))
        underlyingControl.addSubview(source)
        let outsideHitBeforeAppearance = window.hitTest(CGPoint(x: 20, y: 700), with: nil)
        let menu = TestPopover(
            configuration: ContextMenuConfiguration(
                rootPage: ContextMenuPage(items: [.action(ContextMenuAction(title: "TON"))]),
                popoverDisablesInteractiveDismissal: disablesInteractiveDismissal
            ),
            sourceView: source,
            sourceUserInterfaceStyle: .light,
            sourceUserInterfaceLayoutDirection: .leftToRight
        )
        let presentation = TestPresentation(presentedViewController: menu, presenting: presenting)
        presentation.testContainer = container
        presentation.testPresentedView = fullscreenPresentedView ? container : chrome
        presentation.passthroughViews = passthroughViews
        menu.testActivePresentation = presentation
        let originalPresentation = TestPresentation(presentedViewController: menu, presenting: presenting)
        originalPresentation.testContainer = presenting.view
        originalPresentation.testPresentedView = source
        menu.testPresentation = originalPresentation
        chrome.addSubview(menu.view)
        menu.view.frame = CGRect(x: 6, y: 6, width: 294, height: 200)
        menu.beginAppearanceTransition(true, animated: false)
        menu.endAppearanceTransition()
        return MenuFixture(
            menu: menu,
            window: window,
            container: container,
            chrome: chrome,
            underlyingControl: underlyingControl,
            outsideHitBeforeAppearance: outsideHitBeforeAppearance
        )
    }

    @available(iOS 26, *)
    @MainActor
    private struct MenuFixture {
        let menu: TestPopover
        let window: UIWindow
        let container: UIView
        let chrome: UIView
        let underlyingControl: UIControl
        let outsideHitBeforeAppearance: UIView?

        func cleanUp() {
            menu.finishMenuForContentReplacement()
            menu.testPresentation = nil
            menu.testActivePresentation = nil
            window.isHidden = true
        }
    }

    // Hostless tests exercise public hit-testing with a container that passes empty-area
    // touches to its sibling presenter, as observed in UIKit. Native gesture delivery,
    // interactive dismissal and transition animations still require app-host QA.
    @available(iOS 26, *)
    private final class TestPopover: ContextMenuPopoverViewController {
        var testPresentation: UIPresentationController?
        var testActivePresentation: UIPresentationController?
        var testPresentedController: UIViewController?
        private(set) var dismissalCount = 0

        override var presentationController: UIPresentationController? {
            testPresentation ?? super.presentationController
        }

        override var activePresentationController: UIPresentationController? {
            testActivePresentation
        }

        override var presentedViewController: UIViewController? {
            testPresentedController
        }

        override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
            dismissalCount += 1
            completion?()
        }
    }

    private final class TestPresentation: UIPopoverPresentationController {
        var testContainer: UIView?
        var testPresentedView: UIView?
        override var containerView: UIView? { testContainer }
        override var presentedView: UIView? { testPresentedView }
    }

    private final class PassthroughContainer: UIView {
        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            let hit = super.hitTest(point, with: event)
            return hit === self ? nil : hit
        }
    }
}
