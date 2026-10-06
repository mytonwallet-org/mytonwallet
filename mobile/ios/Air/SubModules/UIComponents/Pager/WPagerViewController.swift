import UIKit

/// A full-viewport pager. Controllers are created on demand and retained, but only the
/// selected page (and a transition destination) participate in containment and layout.
@MainActor
public final class WPagerViewController: UIViewController, UIScrollViewDelegate {
    public struct Page {
        public let id: String
        let makeViewController: () -> UIViewController

        public init(id: String, makeViewController: @escaping () -> UIViewController) {
            self.id = id
            self.makeViewController = makeViewController
        }
    }

    public struct Progress {
        public let source: Int
        public let destination: Int
        public let fraction: CGFloat

        public var logicalOffset: CGFloat {
            CGFloat(source) + CGFloat(destination - source) * fraction
        }
    }

    public private(set) var selectedIndex: Int
    public var onSelectionChanged: ((Int) -> Void)?
    public var onProgressChanged: ((Progress) -> Void)?
    public var isPagingEnabled = true {
        didSet {
            guard oldValue != isPagingEnabled, isViewLoaded else { return }
            if !isPagingEnabled { settle(at: selectedIndex) }
            scrollView.isScrollEnabled = isPagingEnabled
        }
    }

    private let pages: [Page]
    private var cachedControllers: [Int: UIViewController] = [:]
    private var hosts: [Int: PagerPageHost] = [:]
    private var slots: [Int] = []
    private var settledIndex: Int
    private var destination: Int?
    private var isProgrammatic = false
    private var isUpdatingLayout = false
    private var isVisible = false
    private var containerAppearance: (controller: UIViewController, appearing: Bool)?
    private var appearanceTransitionActive = false
    private let animation = PagerAnimation()
    private var layoutSize = CGSize.zero
    private var layoutDirection: UIUserInterfaceLayoutDirection?
    private var additionalPagingStart: CGFloat?
    private var additionalPagingGesture: WSegmentedPagingGesture?
    private var contentForwardGesture: WSegmentedPagingGesture?
    private var beginForwardTransition: (() -> WInteractivePushTransition?)?
    private var isForwardNavigationEnabled: () -> Bool = { false }
    private var allowsForwardNavigationFromEdge = false

    // The gesture adapter shares behavior with older pagers without owning their scroll views.
    private(set) var scrollView: UIScrollView! = UIScrollView()
    var pageCount: Int { pages.count }

    public init(pages: [Page], selectedIndex: Int = 0) {
        precondition(pages.indices.contains(selectedIndex))
        precondition(Set(pages.map(\.id)).count == pages.count)
        self.pages = pages
        self.selectedIndex = selectedIndex
        self.settledIndex = selectedIndex
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.clipsToBounds = true
        view.addSubview(scrollView)
        scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrollView.frame = view.bounds
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.isPagingEnabled = true
        scrollView.isScrollEnabled = isPagingEnabled
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.scrollsToTop = false
        scrollView.delaysContentTouches = false
        scrollView.canCancelContentTouches = true
        scrollView.alwaysBounceVertical = false
        scrollView.delegate = self
        if #available(iOS 26.0, *) {
            scrollView.topEdgeEffect.isHidden = true
            scrollView.bottomEdgeEffect.isHidden = true
            scrollView.leftEdgeEffect.isHidden = true
            scrollView.rightEdgeEffect.isHidden = true
        }
        mount(settledIndex)
        resetSlots()
    }

    public override var shouldAutomaticallyForwardAppearanceMethods: Bool { false }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if let controller = cachedControllers[settledIndex] {
            controller.beginAppearanceTransition(true, animated: animated)
            containerAppearance = (controller, true)
        }
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        containerAppearance?.controller.endAppearanceTransition()
        containerAppearance = nil
        isVisible = true
    }

    public override func viewWillDisappear(_ animated: Bool) {
        // Finish/cancel the page transition before forwarding the container disappearance.
        settle(at: selectedIndex)
        isVisible = false
        if let controller = cachedControllers[settledIndex] {
            controller.beginAppearanceTransition(false, animated: animated)
            containerAppearance = (controller, false)
        }
        super.viewWillDisappear(animated)
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        containerAppearance?.controller.endAppearanceTransition()
        containerAppearance = nil
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let direction = view.effectiveUserInterfaceLayoutDirection
        if layoutSize != view.bounds.size || layoutDirection != direction {
            layoutSize = view.bounds.size
            layoutDirection = direction
            cancelNativeDrag()
            settle(at: selectedIndex)
        }
        layoutHosts()
    }

    public override var childForStatusBarStyle: UIViewController? { cachedControllers[selectedIndex] }
    public override var childForStatusBarHidden: UIViewController? { cachedControllers[selectedIndex] }

    public func select(index: Int, animated: Bool) {
        guard pages.indices.contains(index) else { return }
        if !isViewLoaded {
            selectedIndex = index
            settledIndex = index
            onSelectionChanged?(index)
            return
        }
        cancelNativeDrag()
        // Retire the old transition synchronously. No old animation completion can select a page.
        settle(at: selectedIndex, notify: false)
        guard index != settledIndex else {
            onSelectionChanged?(index)
            return
        }
        selectedIndex = index
        guard animated, isVisible, UIView.areAnimationsEnabled, !UIAccessibility.isReduceMotionEnabled,
              view.window != nil, view.bounds.width > 0 else {
            changeDestination(to: index, animated: false)
            settle(at: index)
            return
        }
        isProgrammatic = true
        slots = [settledIndex, index].sorted()
        if isRTL { slots.reverse() }
        updateScrollGeometry()
        changeDestination(to: index)
        animate(to: index)
    }

    private func cancelNativeDrag() {
        guard scrollView.isDragging || scrollView.isDecelerating else { return }
        scrollView.panGestureRecognizer.isEnabled = false
        scrollView.panGestureRecognizer.isEnabled = isPagingEnabled
    }

    private var isRTL: Bool { view.effectiveUserInterfaceLayoutDirection == .rightToLeft }

    private func controller(at index: Int) -> UIViewController {
        if let controller = cachedControllers[index] { return controller }
        let controller = pages[index].makeViewController()
        precondition(controller.parent == nil, "A pager page must not already belong to another container")
        cachedControllers[index] = controller
        return controller
    }

    private func mount(_ index: Int) {
        guard hosts[index] == nil else { return }
        let controller = controller(at: index)
        let host = PagerPageHost(frame: scrollView.bounds)
        hosts[index] = host
        addChild(controller)
        scrollView.addSubview(host)
        controller.view.frame = host.bounds
        controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.addSubview(controller.view)
        controller.didMove(toParent: self)
        layoutHosts()
        controller.view.layoutIfNeeded()
    }

    private func unmount(_ index: Int) {
        guard let host = hosts.removeValue(forKey: index), let controller = cachedControllers[index] else { return }
        controller.willMove(toParent: nil)
        controller.view.removeFromSuperview()
        controller.removeFromParent()
        host.removeFromSuperview()
    }

    private func resetSlots() {
        slots = Array(max(0, settledIndex - 1)...min(pages.count - 1, settledIndex + 1))
        if isRTL { slots.reverse() }
        updateScrollGeometry()
    }

    private func updateScrollGeometry() {
        isUpdatingLayout = true
        scrollView.contentSize = CGSize(width: CGFloat(slots.count) * scrollView.bounds.width, height: scrollView.bounds.height)
        scrollView.setContentOffset(offset(for: settledIndex), animated: false)
        isUpdatingLayout = false
        layoutHosts()
    }

    private func offset(for index: Int) -> CGPoint {
        CGPoint(x: CGFloat(slots.firstIndex(of: index) ?? 0) * scrollView.bounds.width, y: 0)
    }

    private func layoutHosts() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, host) in hosts {
            // Layout always occupies the viewport. Moving a controller's actual frame outside
            // it changes UIKit's inherited safe area and minimum margins during every swipe.
            // Translate the rendered subtree instead; leave all layout guides and child insets
            // under UIKit's ownership. At rest the translation is identity.
            host.frame = scrollView.bounds
            host.setRenderingOffset(offset(for: index).x - scrollView.contentOffset.x)
            host.isUserInteractionEnabled = destination == nil && additionalPagingStart == nil && !scrollView.isDragging && !scrollView.isDecelerating
            host.accessibilityElementsHidden = index != selectedIndex || destination != nil
        }
        CATransaction.commit()
    }

    private func changeDestination(to index: Int?, animated: Bool = true) {
        guard destination != index else { return }
        if let previous = destination {
            finishAppearance(completed: false)
            unmount(previous)
        }
        destination = index
        guard let index else { return }
        mount(index)
        if isVisible {
            cachedControllers[settledIndex]?.beginAppearanceTransition(false, animated: animated)
            cachedControllers[index]?.beginAppearanceTransition(true, animated: animated)
            appearanceTransitionActive = true
        }
    }

    private func finishAppearance(completed: Bool) {
        guard appearanceTransitionActive, let destination else { return }
        if !completed {
            cachedControllers[settledIndex]?.beginAppearanceTransition(true, animated: true)
            cachedControllers[destination]?.beginAppearanceTransition(false, animated: true)
        }
        cachedControllers[settledIndex]?.endAppearanceTransition()
        cachedControllers[destination]?.endAppearanceTransition()
        appearanceTransitionActive = false
    }

    private func settle(at index: Int, notify: Bool = true) {
        guard isViewLoaded else { return }
        animation.cancel()
        isUpdatingLayout = true
        scrollView.setContentOffset(scrollView.contentOffset, animated: false)
        additionalPagingStart = nil
        let pendingAppearance = settledIndex != index ? containerAppearance : nil
        if let pendingAppearance {
            if pendingAppearance.appearing {
                pendingAppearance.controller.beginAppearanceTransition(false, animated: false)
            }
            pendingAppearance.controller.endAppearanceTransition()
            containerAppearance = nil
        }
        let completed = destination == index
        finishAppearance(completed: completed)
        isProgrammatic = false
        destination = nil
        selectedIndex = index
        settledIndex = index
        mount(index)
        if pendingAppearance?.appearing == true, let controller = cachedControllers[index] {
            controller.beginAppearanceTransition(true, animated: false)
            containerAppearance = (controller, true)
        }
        for other in Array(hosts.keys) where other != index { unmount(other) }
        isUpdatingLayout = false
        resetSlots()
        setNeedsStatusBarAppearanceUpdate()
        if notify { onSelectionChanged?(index) }
    }

    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        settle(at: selectedIndex, notify: false)
    }

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !isUpdatingLayout, scrollView.bounds.width > 0 else { return }
        if isProgrammatic, let destination {
            let start = offset(for: settledIndex).x
            let distance = offset(for: destination).x - start
            let fraction = distance == 0 ? 1 : (scrollView.contentOffset.x - start) / distance
            onProgressChanged?(.init(source: settledIndex, destination: destination, fraction: min(1, max(0, fraction))))
        } else {
            let delta = (scrollView.contentOffset.x - offset(for: settledIndex).x) / scrollView.bounds.width
            let step = delta > 0 ? 1 : -1
            let target = settledIndex + step * (isRTL ? -1 : 1)
            let next = abs(delta) > 0.0001 && pages.indices.contains(target) ? target : nil
            changeDestination(to: next)
            onProgressChanged?(.init(source: settledIndex, destination: next ?? settledIndex, fraction: min(1, abs(delta))))
        }
        layoutHosts()
    }

    public func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { finishScrolling() }
    }

    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { finishScrolling() }

    private func animate(to index: Int) {
        let start = scrollView.contentOffset.x
        let end = offset(for: index).x
        animation.start(duration: 0.3) { [weak self] progress in
            self?.scrollView.contentOffset.x = start + (end - start) * progress
        } completion: { [weak self] in
            self?.settle(at: index)
        }
    }

    private func finishScrolling() {
        guard !animation.isRunning, scrollView.bounds.width > 0 else { return }
        let slot = min(slots.count - 1, max(0, Int((scrollView.contentOffset.x / scrollView.bounds.width).rounded())))
        settle(at: isProgrammatic ? selectedIndex : slots[slot])
    }
}

extension WPagerViewController: WSegmentedPagingGestureTarget {
    public func setAdditionalPagingGestureView(_ view: UIView?, isEnabled: @escaping () -> Bool = { true }) {
        if let gesture = additionalPagingGesture {
            endAdditionalPaging(translation: 0, velocity: 0, cancelled: true)
            gesture.isEnabled = false
            gesture.view?.removeGestureRecognizer(gesture)
        }
        additionalPagingGesture = view.map {
            let gesture = WSegmentedPagingGesture(controller: self, isPagingEnabled: isEnabled)
            $0.addGestureRecognizer(gesture)
            return gesture
        }
    }

    public func setForwardNavigation(in view: UIView, allowsEdgeNavigation: Bool = false,
                                     beginTransition: @escaping () -> WInteractivePushTransition?, isEnabled: @escaping () -> Bool) {
        beginForwardTransition = beginTransition
        isForwardNavigationEnabled = isEnabled
        allowsForwardNavigationFromEdge = allowsEdgeNavigation
        if let gesture = contentForwardGesture {
            gesture.isEnabled = false
            gesture.view?.removeGestureRecognizer(gesture)
        }
        let gesture = WSegmentedPagingGesture(controller: self, forwardOnly: true, isPagingEnabled: isEnabled)
        view.addGestureRecognizer(gesture)
        scrollView.panGestureRecognizer.require(toFail: gesture)
        contentForwardGesture = gesture
    }

    func isForwardNavigationEdge(_ point: CGPoint, in bounds: CGRect) -> Bool {
        guard allowsForwardNavigationFromEdge, bounds.contains(point) else { return false }
        return isRTL ? point.x <= bounds.minX + 20 : point.x >= bounds.maxX - 20
    }

    func canBeginForwardNavigation(velocity: CGFloat, fromEdge: Bool = false) -> Bool {
        isPagingEnabled && destination == nil && additionalPagingStart == nil
            && (selectedIndex == pages.count - 1 || (fromEdge && allowsForwardNavigationFromEdge))
            && velocity * (isRTL ? 1 : -1) > 0
    }

    func beginForwardNavigation(velocity: CGPoint, fromEdge: Bool = false) -> WInteractivePushTransition? {
        guard abs(velocity.x) > abs(velocity.y), canBeginForwardNavigation(velocity: velocity.x, fromEdge: fromEdge),
              isForwardNavigationEnabled() else { return nil }
        return beginForwardTransition?()
    }

    func beginAdditionalPaging() {
        settle(at: selectedIndex, notify: false)
        additionalPagingStart = scrollView.contentOffset.x
    }

    func updateAdditionalPaging(translation: CGFloat) {
        guard let start = additionalPagingStart else { return }
        let proposed = start - translation
        let maxOffset = max(0, scrollView.contentSize.width - scrollView.bounds.width)
        let limited = min(maxOffset, max(0, proposed))
        let overshoot = proposed - limited
        let resistance = 1 + abs(overshoot) * 0.55 / max(1, scrollView.bounds.width)
        scrollView.contentOffset.x = limited + overshoot * 0.55 / resistance
    }

    func endAdditionalPaging(translation: CGFloat, velocity: CGFloat, cancelled: Bool) {
        guard let start = additionalPagingStart, scrollView.bounds.width > 0 else { return }
        additionalPagingStart = nil
        let projectedSlot = Int(((start - translation - velocity * 0.2) / scrollView.bounds.width).rounded())
        let target = cancelled ? settledIndex : slots[min(slots.count - 1, max(0, projectedSlot))]
        let targetOffset = offset(for: target)
        if !UIView.areAnimationsEnabled || UIAccessibility.isReduceMotionEnabled || view.window == nil || abs(scrollView.contentOffset.x - targetOffset.x) < 0.5 {
            if target != settledIndex { changeDestination(to: target) }
            settle(at: target)
        } else {
            animate(to: target)
        }
    }
}

private final class PagerPageHost: UIView {
    private let pageMask = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.mask = pageMask
    }

    func setRenderingOffset(_ offset: CGFloat) {
        // Only the presentation tree moves. Model transforms must stay identity, including
        // while a nested UIKit/SwiftUI controller recalculates its safe area after reattachment.
        if offset == 0 {
            layer.removeAnimation(forKey: "pageTranslation")
        } else {
            let translation = CABasicAnimation(keyPath: "sublayerTransform.translation.x")
            translation.fromValue = offset
            translation.toValue = offset
            translation.duration = 1
            translation.speed = 0
            translation.fillMode = .both
            translation.isRemovedOnCompletion = false
            layer.add(translation, forKey: "pageTranslation")
        }
        // The sublayer transform also moves the mask. Its path stays in page coordinates;
        // adding the offset here would clip twice and expose a gap between adjacent pages.
        pageMask.path = CGPath(rect: bounds, transform: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
