import Testing
import UIKit
import WalletResources
@testable import UIComponents

@MainActor
@Suite("Additional segmented paging")
struct SegmentedPagingGestureTests {
    @Test
    func `toolbar wiring leaves native gesture ownership and delegate intact`() throws {
        let controller = makeController()
        let scrollView = controller.scrollView!
        let nativePan = scrollView.panGestureRecognizer
        let nativeDelegate = nativePan.delegate
        let contentHost = UIView()
        contentHost.addSubview(controller)
        controller.setForwardNavigation(in: contentHost, beginTransition: { nil }, isEnabled: { true })
        let contentPan = try #require(contentHost.gestureRecognizers?.first as? WSegmentedPagingGesture)
        #expect(contentPan.view === contentHost)
        #expect(contentPan !== nativePan)
        #expect(contentPan.delegate === contentPan)
        let toolbar = UIView()
        controller.setAdditionalPagingGestureView(toolbar)
        let toolbarPan = try #require(toolbar.gestureRecognizers?.first as? WSegmentedPagingGesture)

        #expect(nativePan.view === scrollView)
        #expect(nativePan.delegate === nativeDelegate)
        #expect(toolbarPan !== nativePan)
        #expect(toolbarPan.delegate === toolbarPan)

        let searchHost = UIView()
        searchHost.addSubview(toolbar)
        let navigationHost = UIView()
        navigationHost.addSubview(toolbar)
        #expect(toolbarPan.view === toolbar)

        let replacement = UIView()
        controller.setAdditionalPagingGestureView(replacement)
        #expect(toolbarPan.view == nil)
        controller.setAdditionalPagingGestureView(nil)
        #expect(replacement.gestureRecognizers?.isEmpty != false)
        #expect(nativePan.view === scrollView)
        #expect(nativePan.delegate === nativeDelegate)
    }

    @Test(arguments: [false, true])
    func `slow drag progress and completion respect layout direction`(rtl: Bool) {
        let controller = makeController(rtl: rtl)
        controller.setSelectedIndex(to: 1, animated: false)
        let initialOffset = controller.scrollView.contentOffset.x
        let translation: CGFloat = rtl ? 250 : -250
        controller.beginAdditionalPaging()
        controller.updateAdditionalPaging(translation: translation)
        #expect(controller.scrollView.contentOffset.x == initialOffset - translation)
        #expect(controller.model.selection?.effectiveSelectedItemID == "2")
        controller.endAdditionalPaging(translation: translation, velocity: 0, cancelled: false)
        #expect(controller.selectedIndex == 2)
    }

    @Test
    func `short drag returns to its starting page`() {
        let controller = makeController()
        controller.setSelectedIndex(to: 1, animated: false)
        controller.beginAdditionalPaging()
        controller.updateAdditionalPaging(translation: -40)
        controller.endAdditionalPaging(translation: -40, velocity: 0, cancelled: false)
        #expect(controller.selectedIndex == 1)
    }

    @Test
    func `cancellation restores the starting page after crossing halfway`() {
        let controller = makeController()
        controller.setSelectedIndex(to: 1, animated: false)
        controller.beginAdditionalPaging()
        controller.updateAdditionalPaging(translation: -270)
        controller.endAdditionalPaging(translation: -270, velocity: -900, cancelled: true)
        #expect(controller.selectedIndex == 1)
    }

    @Test
    func `release velocity completes a short flick without skipping a page`() {
        let controller = makeController()
        controller.beginAdditionalPaging()
        controller.updateAdditionalPaging(translation: -50)
        controller.endAdditionalPaging(translation: -50, velocity: -5000, cancelled: false)
        #expect(controller.selectedIndex == 1)
    }

    @Test
    func `native content drag takes over without subsequent toolbar updates`() {
        let controller = makeController()
        controller.setSelectedIndex(to: 1, animated: false)
        controller.beginAdditionalPaging()
        controller.updateAdditionalPaging(translation: -150)
        let offset = controller.scrollView.contentOffset
        controller.scrollViewWillBeginDragging(controller.scrollView)
        controller.updateAdditionalPaging(translation: -300)
        controller.endAdditionalPaging(translation: -300, velocity: -900, cancelled: false)
        #expect(controller.scrollView.contentOffset == offset)
    }

    @Test(arguments: [false, true])
    func `forward navigation starts only beyond the settled last page`(rtl: Bool) {
        let controller = makeController(rtl: rtl)
        let forwardVelocity: CGFloat = rtl ? 300 : -300
        #expect(!controller.canBeginForwardNavigation(velocity: forwardVelocity))
        controller.setSelectedIndex(to: 1, animated: false)
        #expect(!controller.canBeginForwardNavigation(velocity: forwardVelocity))
        controller.setSelectedIndex(to: 2, animated: false)
        #expect(controller.canBeginForwardNavigation(velocity: forwardVelocity))
        #expect(!controller.canBeginForwardNavigation(velocity: -forwardVelocity))
        #expect(!controller.canBeginForwardNavigation(velocity: 0))
        controller.scrollView.contentOffset.x += rtl ? 30 : -30
        #expect(!controller.canBeginForwardNavigation(velocity: forwardVelocity))
    }

    @Test(arguments: [false, true])
    func `forward navigation respects direction and the root availability gate`(rtl: Bool) {
        let controller = makeController(rtl: rtl)
        var enabled = true
        var attempts = 0
        controller.setForwardNavigation(in: UIView(), beginTransition: { attempts += 1; return nil }, isEnabled: { enabled })
        let x: CGFloat = rtl ? 300 : -300
        _ = controller.beginForwardNavigation(velocity: CGPoint(x: x, y: 0))
        #expect(attempts == 0)
        controller.setSelectedIndex(to: 2, animated: false)
        _ = controller.beginForwardNavigation(velocity: CGPoint(x: -x, y: 0))
        _ = controller.beginForwardNavigation(velocity: CGPoint(x: x, y: 500))
        #expect(attempts == 0)
        enabled = false
        _ = controller.beginForwardNavigation(velocity: CGPoint(x: x, y: 0))
        #expect(attempts == 0)
        enabled = true
        _ = controller.beginForwardNavigation(velocity: CGPoint(x: x, y: 0))
        #expect(attempts == 1)
        controller.scrollView.isScrollEnabled = false
        _ = controller.beginForwardNavigation(velocity: CGPoint(x: x, y: 0))
        #expect(attempts == 1)
    }

    @Test(arguments: [false, true])
    func `first page boundary resists overscroll and returns to the first page`(rtl: Bool) {
        let controller = makeController(rtl: rtl)
        let initialOffset = controller.scrollView.contentOffset.x
        let translation: CGFloat = rtl ? -250 : 250
        controller.beginAdditionalPaging()
        controller.updateAdditionalPaging(translation: translation)
        let movement = controller.scrollView.contentOffset.x - initialOffset
        #expect(abs(movement) > 0 && abs(movement) < abs(translation))
        controller.endAdditionalPaging(translation: translation, velocity: 0, cancelled: false)
        #expect(controller.selectedIndex == 0)
    }

    private func makeController(rtl: Bool = false) -> WSegmentedController {
        _ = WalletResourcesBundle.bundle.load()
        let items = (0..<3).map {
            SegmentedControlItem(id: "\($0)", title: "Page \($0)", viewController: PagingTestContent())
        }
        let controller = WSegmentedController(items: items, barHeight: 40)
        controller.semanticContentAttribute = rtl ? .forceRightToLeft : .forceLeftToRight
        controller.frame = CGRect(x: 0, y: 0, width: 400, height: 800)
        NSLayoutConstraint.activate([
            controller.widthAnchor.constraint(equalToConstant: 400),
            controller.heightAnchor.constraint(equalToConstant: 800),
        ])
        controller.layoutIfNeeded()
        controller.setSelectedIndex(to: 0, animated: false)
        return controller
    }
}

@MainActor
private final class PagingTestContent: UIViewController, WSegmentedControllerContent {
    var onScroll: ((CGFloat) -> Void)?
    var scrollingView: UIScrollView? { nil }
    func scrollToTop(animated: Bool) {}
    func calculateHeight(isHosted: Bool) -> CGFloat { 800 }
}
