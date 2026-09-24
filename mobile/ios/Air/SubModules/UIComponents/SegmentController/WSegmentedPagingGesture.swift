import UIKit

final class WSegmentedPagingGesture: UIPanGestureRecognizer, UIGestureRecognizerDelegate {
    private weak var controller: WSegmentedController?
    private weak var touchedView: UIView?
    private let isPagingEnabled: () -> Bool
    private let forwardOnly: Bool
    private var startedAtForwardEdge = false
    private var forwardTransition: WInteractivePushTransition?

    init(
        controller: WSegmentedController,
        forwardOnly: Bool = false,
        isPagingEnabled: @escaping () -> Bool
    ) {
        self.controller = controller
        self.forwardOnly = forwardOnly
        self.isPagingEnabled = isPagingEnabled
        super.init(target: nil, action: nil)
        addTarget(self, action: #selector(handlePan))
        delegate = self
        maximumNumberOfTouches = 1
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        startedAtForwardEdge = forwardOnly && view.map { view in
            controller?.isForwardNavigationEdge(touch.location(in: view), in: view.bounds) == true
        } == true
        if forwardOnly {
            guard let scrollView = controller?.scrollView,
                  startedAtForwardEdge || touch.view?.isDescendant(of: scrollView) == true else { return false }
        }
        touchedView = touch.view
        var candidate = touch.view
        while let candidateView = candidate {
            if candidateView is UITextInput || candidateView is UISlider || candidateView is UISwitch {
                return false
            }
            if candidateView === view { break }
            candidate = candidateView.superview
        }
        return isPagingEnabled()
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let controller,
              controller.viewControllers.count > 1,
              controller.scrollView.isScrollEnabled,
              !controller.scrollView.isDragging,
              !controller.scrollView.isDecelerating,
              controller.scrollView.bounds.width > 0,
              isPagingEnabled() else { return false }
        let velocity = velocity(in: view)
        return abs(velocity.x) > abs(velocity.y)
            && (!forwardOnly || controller.canBeginForwardNavigation(velocity: velocity.x, fromEdge: startedAtForwardEdge))
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        guard let view, let otherView = otherGestureRecognizer.view,
              otherView.isDescendant(of: view),
              touchedView?.isDescendant(of: otherView) == true else { return false }
        if startedAtForwardEdge, otherGestureRecognizer is UIPanGestureRecognizer {
            return false
        }
        if forwardOnly, let scrollView = otherView as? UIScrollView,
           otherGestureRecognizer === scrollView.panGestureRecognizer {
            if scrollView === controller?.scrollView { return false }
            // Vertical content keeps its own scrolling; horizontal carousels take priority.
            if scrollView.contentSize.width <= scrollView.bounds.width + 1 && !scrollView.alwaysBounceHorizontal {
                return false
            }
        }
        return otherGestureRecognizer is UIPanGestureRecognizer
            || otherGestureRecognizer is UILongPressGestureRecognizer
            || otherGestureRecognizer is UISwipeGestureRecognizer
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        guard startedAtForwardEdge, let view, let otherView = otherGestureRecognizer.view else { return false }
        return otherGestureRecognizer is UIPanGestureRecognizer && otherView.isDescendant(of: view)
    }

    @objc private func handlePan() {
        if state == .began {
            forwardTransition = controller?.beginForwardNavigation(
                velocity: velocity(in: view),
                fromEdge: startedAtForwardEdge
            )
        }
        if let forwardTransition {
            // The root-only paging gate closes as soon as the navigation push starts.
            // Continue routing this gesture to its transition until the finger lifts.
            forwardTransition.handle(self)
            if state == .ended || state == .cancelled || state == .failed {
                self.forwardTransition = nil
            }
            return
        }
        switch state {
        case .began:
            controller?.beginAdditionalPaging()
            controller?.updateAdditionalPaging(translation: translation(in: view).x)
        case .changed:
            if isPagingEnabled(), controller?.scrollView.isScrollEnabled == true {
                controller?.updateAdditionalPaging(translation: translation(in: view).x)
            } else {
                controller?.endAdditionalPaging(translation: 0, velocity: 0, cancelled: true)
                isEnabled = false
                isEnabled = true
            }
        case .ended, .cancelled, .failed:
            controller?.endAdditionalPaging(
                translation: translation(in: view).x,
                velocity: velocity(in: view).x,
                cancelled: state != .ended || !isPagingEnabled() || controller?.scrollView.isScrollEnabled != true
            )
        default:
            break
        }
    }
}
