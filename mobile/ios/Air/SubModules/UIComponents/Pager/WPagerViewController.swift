import UIKit

/// A full-viewport pager with optional staged preparation of retained, hidden pages.
/// Preparation never sends appearance callbacks; only navigation does.
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

        fileprivate func contains(_ index: Int) -> Bool {
            index == source || index == destination
        }
    }

    public private(set) var selectedIndex: Int
    public var onSelectionChanged: ((Int) -> Void)?
    public var onProgressChanged: ((Progress) -> Void)?
    public var isPagingEnabled = true {
        didSet {
            guard oldValue != isPagingEnabled, isViewLoaded else { return }
            if !isPagingEnabled { settle(at: interruptionIndex) }
            scrollView.isScrollEnabled = isPagingEnabled
            schedulePreparation()
        }
    }

    private let pages: [Page]
    private let preloadsPages: Bool
    private var preparationTimer: Timer?
    private var didReceiveMemoryPressure = false
    private var cachedControllers: [Int: UIViewController] = [:]
    private var hosts: [Int: PagerPageHost] = [:]
    private var slots: [Int] = []
    // Appearance ownership can advance through intermediate pages during a long
    // drag; selection is committed only when scrolling finishes (or a tab is tapped).
    private var appearanceIndex: Int
    private var destination: Int?
    private enum Motion {
        case idle
        case dragging
        case decelerating
        case toolbar(start: CGFloat, origin: Int)
        case animating(target: Int)

        var isIdle: Bool { if case .idle = self { true } else { false } }
    }

    private var motion = Motion.idle
    private var isUpdatingLayout = false
    private var isVisible = false
    private var containerAppearance: (controller: UIViewController, appearing: Bool)?
    private var appearanceTransitionActive = false
    private let animation = PagerAnimation()
    private var layoutSize = CGSize.zero
    private var layoutDirection: UIUserInterfaceLayoutDirection?
    private var additionalPagingGesture: WSegmentedPagingGesture?
    private var contentForwardGesture: WSegmentedPagingGesture?
    private var beginForwardTransition: (() -> WInteractivePushTransition?)?
    private var isForwardNavigationEnabled: () -> Bool = { false }
    private var allowsForwardNavigationFromEdge = false

    // The gesture adapter shares behavior with older pagers without owning their scroll views.
    private let pagingScrollView = PagerScrollView()
    var scrollView: UIScrollView! { pagingScrollView }
    var pageCount: Int { pages.count }
    var canInterruptDeceleration: Bool { true }

    public init(pages: [Page], selectedIndex: Int = 0, preloadsPages: Bool = false) {
        precondition(pages.indices.contains(selectedIndex))
        precondition(Set(pages.map(\.id)).count == pages.count)
        self.pages = pages
        self.preloadsPages = preloadsPages
        self.selectedIndex = selectedIndex
        self.appearanceIndex = selectedIndex
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
        mount(appearanceIndex)
        resetSlots()
        NotificationCenter.default.addObserver(self, selector: #selector(schedulePreparation),
            name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    public override var shouldAutomaticallyForwardAppearanceMethods: Bool { false }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if let controller = cachedControllers[appearanceIndex] {
            controller.beginAppearanceTransition(true, animated: animated)
            containerAppearance = (controller, true)
            layoutPage(controller)
        }
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        containerAppearance?.controller.endAppearanceTransition()
        containerAppearance = nil
        isVisible = true
        schedulePreparation()
    }

    public override func viewWillDisappear(_ animated: Bool) {
        // Finish/cancel the page transition before forwarding the container disappearance.
        settle(at: interruptionIndex)
        isVisible = false
        preparationTimer?.invalidate()
        preparationTimer = nil
        if let controller = cachedControllers[appearanceIndex] {
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
            let index = interruptionIndex
            layoutSize = view.bounds.size
            layoutDirection = direction
            settle(at: index)
        }
        layoutHosts()
    }

    public override var childForStatusBarStyle: UIViewController? { cachedControllers[selectedIndex] }
    public override var childForStatusBarHidden: UIViewController? { cachedControllers[selectedIndex] }

    public override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        didReceiveMemoryPressure = true
        preparationTimer?.invalidate()
        preparationTimer = nil
        // Keep controller-owned state, but shed inactive viewport hosts and stop warming
        // them again. Subsequent navigation falls back to mounting only the active pages.
        for index in Array(hosts.keys) where index != appearanceIndex && index != destination {
            unmount(index)
        }
    }

    private var retainsPreparedPages: Bool { preloadsPages && !didReceiveMemoryPressure }

    private var canPreparePage: Bool {
        retainsPreparedPages && isVisible && isPagingEnabled && viewIfLoaded?.window != nil
            && (view.window?.windowScene?.activationState ?? .foregroundActive) == .foregroundActive
            && motion.isIdle
            && !scrollView.isTracking && !scrollView.isDecelerating
            && layoutSize == scrollView.bounds.size && layoutSize.width > 0
    }

    @objc private func schedulePreparation() {
        preparationTimer?.invalidate()
        preparationTimer = nil
        guard canPreparePage, pages.indices.contains(where: { hosts[$0] == nil }) else { return }
        // One page per idle turn, after the selected page has appeared. Default run-loop
        // mode also postpones work while a nested Home/Market scroll view is tracking.
        let timer = Timer(timeInterval: 0.1, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.prepareNextPage() }
        }
        preparationTimer = timer
        RunLoop.main.add(timer, forMode: .default)
    }

    func prepareNextPage() {
        preparationTimer?.invalidate()
        preparationTimer = nil
        guard canPreparePage, let index = pages.indices.first(where: { hosts[$0] == nil }) else { return }
        UIView.performWithoutAnimation { mount(index) }
        schedulePreparation()
    }

    public func select(index: Int, animated: Bool) {
        guard pages.indices.contains(index) else { return }
        if !isViewLoaded {
            selectedIndex = index
            appearanceIndex = index
            onSelectionChanged?(index)
            return
        }
        let wasIdle = motion.isIdle
        stopMotion()
        guard animated, isVisible, UIView.areAnimationsEnabled, !UIAccessibility.isReduceMotionEnabled,
              view.window != nil, view.bounds.width > 0 else {
            settle(at: index)
            return
        }
        // Keep an interrupted transition's geometry. Reversing a tap or taking over
        // deceleration must start at the rendered position, not the previous selection.
        if !slots.contains(index) {
            settle(at: nearestPage, notify: false)
        }
        if wasIdle, abs(index - selectedIndex) > 1 {
            slots = [selectedIndex, index].sorted()
            if isRTL { slots.reverse() }
            updateScrollGeometry()
        }
        selectedIndex = index
        if abs(scrollView.contentOffset.x - offset(for: appearanceIndex).x) < 0.5, index != appearanceIndex {
            changeDestination(to: index)
        }
        animate(to: index)
    }

    /// Resolve the current input before an owner snapshots or moves this container.
    public func finishPaging() {
        guard isViewLoaded, !motion.isIdle else { return }
        settle(at: interruptionIndex)
    }

    private func stopMotion() {
        motion = .idle
        animation.cancel()
        if scrollView.isDragging || scrollView.isDecelerating {
            scrollView.panGestureRecognizer.isEnabled = false
            scrollView.panGestureRecognizer.isEnabled = isPagingEnabled
        }
        scrollView.setContentOffset(scrollView.contentOffset, animated: false)
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
        let host = PagerPageHost(frame: viewport.bounds)
        host.isHidden = index != appearanceIndex && index != destination
        hosts[index] = host
        addChild(controller)
        viewport.addSubview(host)
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

    private var viewport: UIView { pagingScrollView.viewport }

    private func resetSlots() {
        slots = Array(pages.indices)
        if isRTL { slots.reverse() }
        updateScrollGeometry()
    }

    private func updateScrollGeometry() {
        let wasUpdatingLayout = isUpdatingLayout
        isUpdatingLayout = true
        scrollView.contentSize = CGSize(width: CGFloat(slots.count) * scrollView.bounds.width, height: scrollView.bounds.height)
        scrollView.setContentOffset(offset(for: selectedIndex), animated: false)
        layoutHosts()
        isUpdatingLayout = wasUpdatingLayout
    }

    private func offset(for index: Int) -> CGPoint {
        CGPoint(x: CGFloat(slots.firstIndex(of: index) ?? 0) * scrollView.bounds.width, y: 0)
    }

    /// The same two slots drive both the rendered pages and the tab indicator.
    /// Unlike a delta from the last selection, this remains valid across several
    /// page boundaries and when a new gesture interrupts deceleration.
    private var viewportProgress: Progress {
        guard !slots.isEmpty, scrollView.bounds.width > 0 else {
            return .init(source: selectedIndex, destination: selectedIndex, fraction: 0)
        }
        let width = layoutSize.width > 0 ? layoutSize.width : scrollView.bounds.width
        let position = min(CGFloat(slots.count - 1), max(0, scrollView.contentOffset.x / width))
        let lower = Int(floor(position))
        let upper = Int(ceil(position))
        let fraction = position - CGFloat(lower)
        if slots[lower] > slots[upper] {
            return .init(source: slots[upper], destination: slots[lower], fraction: 1 - fraction)
        }
        return .init(source: slots[lower], destination: slots[upper], fraction: fraction)
    }

    private var interruptionIndex: Int {
        switch motion {
        case .idle: selectedIndex
        case let .animating(target): target
        case .dragging, .decelerating, .toolbar: nearestPage
        }
    }

    private var nearestPage: Int {
        let progress = viewportProgress
        return progress.fraction < 0.5 ? progress.source : progress.destination
    }

    private func layoutHosts(progress: Progress? = nil) {
        pagingScrollView.layoutViewport()
        let progress = progress ?? viewportProgress
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, host) in hosts {
            // Only this common viewport follows the scroll view's bounds. Page model
            // geometry remains fixed, including at a direct-jump route normalization.
            if host.frame != viewport.bounds { host.frame = viewport.bounds }
            let hidden = !progress.contains(index)
            if host.isHidden != hidden { host.isHidden = hidden }
            host.setRenderingOffset(host.isHidden ? 0 : offset(for: index).x - scrollView.contentOffset.x)
            let interactive = index == selectedIndex && motion.isIdle
            if host.isUserInteractionEnabled != interactive { host.isUserInteractionEnabled = interactive }
            if host.accessibilityElementsHidden == interactive { host.accessibilityElementsHidden = !interactive }
        }
        CATransaction.commit()
    }

    private func updateViewport() {
        let progress = viewportProgress
        mount(progress.source)
        if progress.destination != progress.source { mount(progress.destination) }
        layoutHosts(progress: progress)
        // If a fast gesture passes the current pair, complete that pair before
        // starting the next. Appearance and retained-host visibility are independent.
        if !progress.contains(appearanceIndex) {
            let next = destination.flatMap { progress.contains($0) ? $0 : nil } ?? progress.source
            changeDestination(to: next)
            if progress.source != progress.destination {
                finishAppearance(completed: true)
                appearanceIndex = next
                destination = nil
            }
        }
        if progress.contains(appearanceIndex) {
            let other = appearanceIndex == progress.source ? progress.destination : progress.source
            changeDestination(to: other == appearanceIndex ? nil : other)
        }
        if !retainsPreparedPages {
            for index in Array(hosts.keys) where !progress.contains(index) && index != appearanceIndex {
                unmount(index)
            }
        }
        onProgressChanged?(progress)
    }

    private func changeDestination(to index: Int?, animated: Bool = true) {
        guard destination != index else { return }
        if destination != nil {
            finishAppearance(completed: false)
        }
        destination = index
        guard let index else { return }
        mount(index)
        if isVisible {
            cachedControllers[appearanceIndex]?.beginAppearanceTransition(false, animated: animated)
            cachedControllers[index]?.beginAppearanceTransition(true, animated: animated)
            appearanceTransitionActive = true
        }
        if let controller = cachedControllers[index] { layoutPage(controller) }
    }

    private func layoutPage(_ controller: UIViewController) {
        // A retained page may have deferred layout while hidden. Resolve its native
        // safe area after appearance begins, before rendering the first transition frame.
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
    }

    private func finishAppearance(completed: Bool) {
        guard appearanceTransitionActive, let destination else { return }
        if !completed {
            cachedControllers[appearanceIndex]?.beginAppearanceTransition(true, animated: true)
            cachedControllers[destination]?.beginAppearanceTransition(false, animated: true)
        }
        cachedControllers[appearanceIndex]?.endAppearanceTransition()
        cachedControllers[destination]?.endAppearanceTransition()
        appearanceTransitionActive = false
    }

    private func settle(at index: Int, notify: Bool = true) {
        guard isViewLoaded else { return }
        stopMotion()
        isUpdatingLayout = true
        let pendingAppearance = appearanceIndex != index ? containerAppearance : nil
        if let pendingAppearance {
            if pendingAppearance.appearing {
                pendingAppearance.controller.beginAppearanceTransition(false, animated: false)
            }
            pendingAppearance.controller.endAppearanceTransition()
            containerAppearance = nil
        }
        // Normalize geometry before completing appearance. In particular, a bridge
        // jump must not deliver didAppear with the old viewport's safe-area cache.
        selectedIndex = index
        resetSlots()
        mount(index)
        layoutHosts()
        changeDestination(to: index == appearanceIndex ? nil : index, animated: false)
        if let controller = cachedControllers[index] { layoutPage(controller) }
        finishAppearance(completed: index == destination)
        destination = nil
        appearanceIndex = index
        if !retainsPreparedPages {
            for other in Array(hosts.keys) where other != index { unmount(other) }
        }
        if pendingAppearance?.appearing == true, let controller = cachedControllers[index] {
            controller.beginAppearanceTransition(true, animated: false)
            containerAppearance = (controller, true)
            layoutPage(controller)
        }
        isUpdatingLayout = false
        setNeedsStatusBarAppearanceUpdate()
        if notify { onSelectionChanged?(index) }
        schedulePreparation()
    }

    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        // UIKit has already stopped its old deceleration. Do not reset contentOffset
        // here: the new pan's translation is relative to this exact position.
        animation.cancel()
        motion = .dragging
        updateViewport()
    }

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !isUpdatingLayout, !motion.isIdle, scrollView.bounds.width > 0,
              scrollView.bounds.size == layoutSize,
              layoutDirection == view.effectiveUserInterfaceLayoutDirection else { return }
        updateViewport()
    }

    public func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard case .dragging = motion else { return }
        if decelerate {
            motion = .decelerating
        } else {
            settle(at: nearestPage)
        }
    }

    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        guard case .decelerating = motion, !scrollView.isTracking else { return }
        settle(at: nearestPage)
    }

    private func animate(to index: Int) {
        let start = scrollView.contentOffset.x
        let end = offset(for: index).x
        guard abs(start - end) > 0.5 else {
            settle(at: index)
            return
        }
        motion = .animating(target: index)
        animation.start(duration: 0.3) { [weak self] progress in
            self?.scrollView.contentOffset.x = start + (end - start) * progress
        } completion: { [weak self] in
            self?.settle(at: index)
        }
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
        isPagingEnabled && motion.isIdle
            && (selectedIndex == pages.count - 1 || (fromEdge && allowsForwardNavigationFromEdge))
            && velocity * (isRTL ? 1 : -1) > 0
    }

    func beginForwardNavigation(velocity: CGPoint, fromEdge: Bool = false) -> WInteractivePushTransition? {
        guard abs(velocity.x) > abs(velocity.y), canBeginForwardNavigation(velocity: velocity.x, fromEdge: fromEdge),
              isForwardNavigationEnabled() else { return nil }
        return beginForwardTransition?()
    }

    func beginAdditionalPaging() {
        let origin = nearestPage
        stopMotion()
        motion = .toolbar(start: scrollView.contentOffset.x, origin: origin)
        updateViewport()
    }

    func updateAdditionalPaging(translation: CGFloat) {
        guard case let .toolbar(start, _) = motion else { return }
        let proposed = start - translation
        let maxOffset = max(0, scrollView.contentSize.width - scrollView.bounds.width)
        let limited = min(maxOffset, max(0, proposed))
        let overshoot = proposed - limited
        let resistance = 1 + abs(overshoot) * 0.55 / max(1, scrollView.bounds.width)
        scrollView.contentOffset.x = limited + overshoot * 0.55 / resistance
    }

    func endAdditionalPaging(translation: CGFloat, velocity: CGFloat, cancelled: Bool) {
        guard case let .toolbar(start, origin) = motion, scrollView.bounds.width > 0 else { return }
        // Match native paging: velocity may advance one page beyond the release
        // position, but a short flick must not skip an unseen intermediate page.
        let width = scrollView.bounds.width
        let release = (start - translation) / width
        let projection = release - velocity * 0.2 / width
        let slot = Int(min(ceil(release), max(floor(release), projection.rounded())))
        let target = cancelled ? origin : slots[min(slots.count - 1, max(0, slot))]
        if !UIView.areAnimationsEnabled || UIAccessibility.isReduceMotionEnabled || view.window == nil {
            settle(at: target)
        } else {
            animate(to: target)
        }
    }
}

private final class PagerScrollView: UIScrollView {
    let viewport = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(viewport)
    }

    override var bounds: CGRect {
        didSet { layoutViewport() }
    }

    override func layoutSubviews() {
        layoutViewport()
        super.layoutSubviews()
    }

    func layoutViewport() {
        if viewport.frame != bounds { viewport.frame = bounds }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

private final class PagerPageHost: UIView {
    private let pageMask = CAShapeLayer()
    private var renderingOffset: CGFloat?
    private var maskBounds: CGRect?

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.mask = pageMask
    }

    func setRenderingOffset(_ offset: CGFloat) {
        if maskBounds != bounds {
            maskBounds = bounds
            // The sublayer transform also moves the mask. Keep its path in page
            // coordinates so adjacent pages meet without clipping the translation twice.
            pageMask.path = CGPath(rect: bounds, transform: nil)
        }
        guard renderingOffset != offset else { return }
        renderingOffset = offset
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
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
