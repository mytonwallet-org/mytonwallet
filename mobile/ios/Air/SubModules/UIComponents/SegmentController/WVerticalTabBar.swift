import SwiftUI
import UIKit
import UIComponentsRuntime
import WalletContext

// Adapts Telegram's tab selection/lens model to UIKit's vertical bar geometry.
// Source attribution: docs/technical/platforms/ios.md, "Duo Top Tabs".
@available(iOS 26.0, *)
@MainActor
public final class WVerticalTabBar: UIView {
    public struct Item {
        public let id: String
        public let title: String
        public let image: UIImage

        public init(id: String, title: String, image: UIImage) {
            self.id = id
            self.title = title
            self.image = image
        }
    }

    public var onSelect: ((Int, Bool) -> Void)?
    /// The expanded surface is reported in bar coordinates inside its layout animation
    public var onExpandedFrameChange: ((CGRect?) -> Void)?
    public var expansionBounds: CGRect? {
        didSet {
            if oldValue != expansionBounds { setNeedsLayout() }
        }
    }
    /// Holding a tab still for the long-press time lifts it, and dragging it along the bar moves it among the others.
    /// The bar shows the new order before it reports the move; a drop never selects. Without a handler a hold only
    /// scrubs the tabs
    public var onReorder: ((_ sourceIndex: Int, _ destinationIndex: Int) -> Void)?
    public private(set) var selectedIndex = 0
    public var itemIds: [String] { items.map(\.id) }
    public var showsSelection = true {
        didSet {
            guard oldValue != showsSelection else { return }
            lens?.isHidden = !showsSelection
            fallbackSelection.isHidden = !showsSelection
            selectedContent.isHidden = !showsSelection
            updateAccessibility()
        }
    }
    public var isOnLeftEdge = false {
        didSet {
            guard oldValue != isOnLeftEdge else { return }
            cancelInteraction()
            setNeedsLayout()
        }
    }

    public override var intrinsicContentSize: CGSize {
        CGSize(width: 48, height: CGFloat(items.count - 1) * 50 + 62)
    }

    private var items: [Item]
    private let surface = UIView()
    private let glass = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let stage = UIView()
    private let normalContent = UIView()
    private let selectedContent = UIView()
    private let fallbackSelection = UIView()
    private let lens: UIView?
    private var usesNativeFlex = false
    private var normalItems: [VerticalTabGlyph] = []
    private var selectedItems: [VerticalTabGlyph] = []
    private var targets: [VerticalTabAccessibilityTarget] = []
    private var scrub: (start: Int, initial: CGPoint, translation: CGPoint, preview: Int)?
    private var showsTitles = false
    private var lastViewportSize = CGSize.zero
    private var reportedExpandedFrame: CGRect?
    private var tracksSelectionMotion = false
    private var holdTimer: Timer?
    private var reorderTimer: Timer?
    /// The lifted tab's index and the place it takes if dropped now
    private var drag: (index: Int, destination: Int)?
    private var layoutAnimator: UIViewPropertyAnimator?
    private var displayLink: CADisplayLink?
    private var currentSelectionFrame = CGRect.zero
    private var appliedLensLifted: Bool?
    private var isApplyingLensLift = false
    private let feedback = UISelectionFeedbackGenerator()
    private let liftFeedback = UIImpactFeedbackGenerator(style: .medium)
    private let trackingSpring = Animation.spring(response: 0.2, dampingFraction: 0.85)
    // UIKit's standard long press: 0.5 s within 10 pt
    private static let reorderHoldDuration: TimeInterval = 0.5
    private static let reorderHoldSlop: CGFloat = 10
    private lazy var scrubRecognizer = VerticalTabScrubRecognizer(target: self, action: #selector(onScrub(_:)))

    public init(items: [Item]) {
        precondition(!items.isEmpty)
        self.items = items
        lens = WMakeLiquidLens()
        super.init(frame: .zero)
        accessibilityIdentifier = "top-tabs.side-tabs"
        clipsToBounds = false
        addSubview(surface)
        surface.cornerConfiguration = .corners(radius: .fixed(30))
        usesNativeFlex = WInstallBarFlex(surface)
        surface.addSubview(glass)
        glass.layer.zPosition = 1
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.scrollsToTop = false
        scrollView.decelerationRate = .fast
        scrollView.delaysContentTouches = false
        scrollView.layer.zPosition = 2
        surface.addSubview(scrollView)
        scrollView.addSubview(contentView)
        contentView.addSubview(stage)
        stage.isUserInteractionEnabled = false
        normalContent.clipsToBounds = true
        selectedContent.clipsToBounds = true
        stage.addSubview(selectedContent)
        if let lens {
            lens.layer.zPosition = 10
            stage.addSubview(lens)
            WConfigureLiquidLens(lens, selectedContent, normalContent)
        } else {
            fallbackSelection.backgroundColor = UIColor.air.thumbBackground
            stage.insertSubview(fallbackSelection, at: 0)
        }
        stage.addSubview(normalContent)
        for (index, item) in items.enumerated() {
            let normal = VerticalTabGlyph(item: item)
            let selected = VerticalTabGlyph(item: item)
            normalContent.addSubview(normal)
            selectedContent.addSubview(selected)
            normalItems.append(normal)
            selectedItems.append(selected)
            let target = VerticalTabAccessibilityTarget()
            target.isAccessibilityElement = true
            target.accessibilityLabel = item.title
            target.accessibilityIdentifier = "top-tabs.side-tab.\(item.id)"
            target.activate = { [weak self, weak target] in
                guard let self, let index = self.targets.firstIndex(where: { $0 === target }) else { return false }
                self.activate(index)
                return true
            }
            target.isUserInteractionEnabled = false
            contentView.addSubview(target)
            targets.append(target)
        }
        scrubRecognizer.delaysTouchesBegan = false
        scrubRecognizer.delaysTouchesEnded = false
        addGestureRecognizer(scrubRecognizer)
        scrubRecognizer.shouldWaitForHold = { [weak self] in
            guard let self else { return false }
            return self.scrollView.contentSize.height > self.scrollView.bounds.height
        }
        scrollView.panGestureRecognizer.require(toFail: scrubRecognizer)
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self, UITraitUserInterfaceStyle.self]) { (bar: WVerticalTabBar, _: UITraitCollection) in
            bar.cancelInteraction()
            bar.setNeedsLayout()
        }
        updateAccessibility()
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        displayLink?.invalidate()
        holdTimer?.invalidate()
        reorderTimer?.invalidate()
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { cancelInteraction() }
    }

    public override func tintColorDidChange() {
        super.tintColorDidChange()
        setNeedsLayout()
    }

    public func select(_ index: Int, animated: Bool = true) {
        guard items.indices.contains(index), selectedIndex != index else { return }
        cancelInteraction()
        selectedIndex = index
        updateSelection(animated: animated)
        centerSelection(animated: animated)
        updateAccessibility()
    }

    public func cancelInteraction() {
        finishScrub(cancelled: true)
        scrubRecognizer.isEnabled = false
        scrubRecognizer.isEnabled = true
    }

    private var labelFont: UIFont {
        UIFontMetrics(forTextStyle: .caption2).scaledFont(for: .systemFont(ofSize: 10, weight: .medium), compatibleWith: traitCollection)
    }

    private var expandedItemHeight: CGFloat { 52 + ceil(labelFont.lineHeight) }
    private var contentSize: CGSize {
        guard showsTitles else { return intrinsicContentSize }
        let longestTitle = items.map { ($0.title as NSString).size(withAttributes: [.font: labelFont]).width }.max() ?? 0
        return CGSize(width: max(72, ceil(longestTitle) + 36), height: CGFloat(items.count) * expandedItemHeight - CGFloat(items.count - 1) * 8 + 8)
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        layoutContents()
    }

    private func layoutContents() {
        let contentSize = self.contentSize
        let size = showsTitles
            ? CGSize(width: contentSize.width, height: min(contentSize.height, max(0, expansionBounds?.height ?? contentSize.height)))
            : CGSize(width: bounds.width, height: min(bounds.height, contentSize.height))
        let hasOverflow = contentSize.height > size.height
        surface.bounds = CGRect(origin: .zero, size: size)
        let x = showsTitles ? (isOnLeftEdge ? size.width / 2 - 12 : bounds.width + 12 - size.width / 2) : bounds.midX
        var top: CGFloat = 0
        if showsTitles, let expansionBounds {
            top = max(expansionBounds.minY, min(top, expansionBounds.maxY - size.height))
        }
        surface.center = CGPoint(x: x, y: top + size.height / 2)
        surface.transform = !usesNativeFlex && scrub != nil && !showsTitles ? CGAffineTransform(scaleX: 1.05513372346085, y: 1.05513372346085) : .identity
        glass.frame = surface.bounds
        glass.cornerConfiguration = surface.cornerConfiguration
        scrollView.frame = surface.bounds
        scrollView.clipsToBounds = !showsTitles || hasOverflow
        scrollView.layer.cornerRadius = scrollView.clipsToBounds ? min(size.width, size.height) / 2 : 0
        scrollView.isScrollEnabled = !showsTitles || hasOverflow
        scrollView.contentSize = contentSize
        contentView.frame = CGRect(origin: .zero, size: contentSize)
        stage.frame = contentView.bounds
        normalContent.frame = contentView.bounds
        selectedContent.frame = contentView.bounds
        if lastViewportSize != size {
            centerSelection(animated: false)
        }
        lastViewportSize = size
        for index in items.indices {
            placeGlyphs(at: index)
            normalItems[index].tintColor = .label
            selectedItems[index].tintColor = tintColor
            targets[index].frame = itemFrame(index)
        }
        if let scrub, tracksSelectionMotion {
            moveScrub(translation: scrub.translation)
        } else {
            updateSelection(animated: false)
        }
        let expandedFrame = showsTitles ? surface.frame : nil
        if reportedExpandedFrame != expandedFrame {
            reportedExpandedFrame = expandedFrame
            onExpandedFrameChange?(expandedFrame)
        }
    }

    private func centerSelection(animated: Bool) {
        guard scrollView.bounds.height > 0 else { return }
        let offset = max(0, min(contentSize.height - scrollView.bounds.height,
                                itemFrame(scrub?.start ?? selectedIndex).midY - scrollView.bounds.height / 2))
        scrollView.setContentOffset(CGPoint(x: 0, y: offset), animated: animated && !UIAccessibility.isReduceMotionEnabled)
    }

    private func placeGlyphs(at index: Int) {
        let frame = glyphFrame(index)
        for glyph in [normalItems[index], selectedItems[index]] {
            glyph.bounds = CGRect(origin: .zero, size: frame.size)
            glyph.center = CGPoint(x: frame.midX, y: frame.midY)
            glyph.layoutGlyph(expanded: showsTitles, font: labelFont)
        }
    }

    /// While a tab is lifted it rides under the finger with the selection, and the tabs between its place and the
    /// one it would take move a place to make room
    private func glyphFrame(_ index: Int) -> CGRect {
        guard let drag else { return itemFrame(index) }
        if index == drag.index { return selectionFrame(lifted: false) }
        var place = index
        if drag.index < index, index <= drag.destination { place -= 1 }
        if drag.destination <= index, index < drag.index { place += 1 }
        return itemFrame(place)
    }

    private func itemFrame(_ index: Int) -> CGRect {
        if showsTitles {
            return CGRect(x: 4, y: 4 + CGFloat(index) * (expandedItemHeight - 8), width: contentSize.width - 8, height: expandedItemHeight)
        }
        return CGRect(x: 2, y: 2 + CGFloat(index) * 50, width: 44, height: 58)
    }

    private func nearestIndex(to centerY: CGFloat) -> Int {
        items.indices.min { abs(itemFrame($0).midY - centerY) < abs(itemFrame($1).midY - centerY) } ?? 0
    }

    private func activate(_ index: Int) {
        let repeated = showsSelection && selectedIndex == index
        select(index)
        onSelect?(index, repeated)
    }

    @objc private func onScrub(_ recognizer: VerticalTabScrubRecognizer) {
        switch recognizer.state {
        case .began: beginScrub(at: recognizer.initial, timestamp: recognizer.initialTimestamp)
        case .changed: moveScrub(translation: recognizer.translation)
        case .ended:
            if scrub == nil { beginScrub(at: recognizer.current, timestamp: recognizer.initialTimestamp) }
            finishScrub(cancelled: false)
        case .failed, .cancelled: finishScrub(cancelled: true)
        default: break
        }
    }

    func beginScrub(at point: CGPoint, timestamp: TimeInterval? = nil) {
        let start = timestamp ?? CACurrentMediaTime()
        scrollView.setContentOffset(scrollView.contentOffset, animated: false)
        let index = nearestIndex(to: convert(point, to: contentView).y)
        scrub = (index, point, .zero, index)
        tracksSelectionMotion = false
        feedback.prepare()
        setLifted(true)
        animateLayout(damping: 0.65)
        holdTimer?.invalidate()
        let remainingDelay = max(0, start + 0.25 - CACurrentMediaTime())
        let timer = Timer(timeInterval: remainingDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.scrub != nil else { return }
                self.showsTitles = true
                self.animateLayout(damping: 0.5)
            }
        }
        holdTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        reorderTimer?.invalidate()
        reorderTimer = nil
        if onReorder != nil, items.count > 1 {
            liftFeedback.prepare()
            let reorderTimer = Timer(
                timeInterval: max(0, start + Self.reorderHoldDuration - CACurrentMediaTime()),
                repeats: false
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.liftScrubbedItem() }
            }
            self.reorderTimer = reorderTimer
            RunLoop.main.add(reorderTimer, forMode: .common)
        }
    }

    private func liftScrubbedItem() {
        reorderTimer = nil
        guard let scrub, drag == nil, onReorder != nil else { return }
        drag = (scrub.start, scrub.start)
        liftFeedback.impactOccurred()
    }

    func moveScrub(translation: CGPoint) {
        guard var scrub else { return }
        if hypot(translation.x, translation.y) > Self.reorderHoldSlop {
            // A finger that slides scrubs the tabs and never lifts one
            reorderTimer?.invalidate()
            reorderTimer = nil
        }
        scrub.translation = translation
        self.scrub = scrub
        if !tracksSelectionMotion { lens?.layer.removeAllAnimations() }
        tracksSelectionMotion = true
        if var drag {
            let destination = nearestIndex(to: selectionFrame(lifted: false).midY)
            let isMoving = destination != drag.destination
            if isMoving { feedback.selectionChanged() }
            drag.destination = destination
            self.drag = drag
            layoutGlyphs(animatingOthers: isMoving)
            updateSelection(animated: false)
            return
        }
        let index = nearestIndex(to: convertScrubPointToContent().y)
        if index != scrub.preview { feedback.selectionChanged() }
        scrub.preview = index
        self.scrub = scrub
        updateSelection(animated: false)
    }

    func finishScrub(cancelled: Bool) {
        holdTimer?.invalidate()
        holdTimer = nil
        reorderTimer?.invalidate()
        reorderTimer = nil
        guard let scrub else { return }
        let drag = self.drag
        let repeated = showsSelection && selectedIndex == scrub.preview
        self.scrub = nil
        self.drag = nil
        tracksSelectionMotion = false
        showsTitles = false
        let move = drag.flatMap { !cancelled && $0.index != $0.destination ? $0 : nil }
        if let move {
            moveItem(from: move.index, to: move.destination)
        } else if drag == nil, !cancelled {
            selectedIndex = scrub.preview
        }
        setLifted(false)
        animateLayout(damping: 0.75)
        centerSelection(animated: true)
        updateAccessibility()
        if let move {
            onReorder?(move.index, move.destination)
        } else if drag == nil, !cancelled {
            onSelect?(scrub.preview, repeated)
        }
    }

    private func moveItem(from source: Int, to destination: Int) {
        items.insert(items.remove(at: source), at: destination)
        normalItems.insert(normalItems.remove(at: source), at: destination)
        selectedItems.insert(selectedItems.remove(at: source), at: destination)
        targets.insert(targets.remove(at: source), at: destination)
        if selectedIndex == source {
            selectedIndex = destination
        } else if source < selectedIndex, selectedIndex <= destination {
            selectedIndex -= 1
        } else if destination <= selectedIndex, selectedIndex < source {
            selectedIndex += 1
        }
    }

    private func layoutGlyphs(animatingOthers: Bool) {
        let placeOthers = {
            for index in self.items.indices where index != self.drag?.index {
                self.placeGlyphs(at: index)
            }
        }
        if animatingOthers, !UIAccessibility.isReduceMotionEnabled {
            UIView.animate(
                withDuration: 0.3,
                delay: 0,
                usingSpringWithDamping: 0.85,
                initialSpringVelocity: 0,
                options: [.beginFromCurrentState, .allowUserInteraction],
                animations: placeOthers
            )
        } else {
            placeOthers()
        }
        if let index = drag?.index {
            UIView.performWithoutAnimation { placeGlyphs(at: index) }
        }
    }

    private func animateLayout(damping: CGFloat) {
        let glyphs = normalItems + selectedItems
        let blurRadii = glyphs.map { $0.titleBlurRadius }
        let velocity = normalItems.first?.titleSpringVelocity(toward: showsTitles ? 1 : 0) ?? 0
        if layoutAnimator?.state == .active {
            layoutAnimator?.stopAnimation(false)
            layoutAnimator?.finishAnimation(at: .current)
        }
        guard !UIAccessibility.isReduceMotionEnabled else {
            layoutContents()
            glyphs.forEach { $0.animateTitleBlur(from: 0, animated: false) }
            return
        }
        let frequency = 2 * CGFloat.pi / 0.4
        let timing = UISpringTimingParameters(mass: 1, stiffness: frequency * frequency, damping: 2 * damping * frequency, initialVelocity: CGVector(dx: velocity, dy: velocity))
        let animator = UIViewPropertyAnimator(duration: 0, timingParameters: timing)
        animator.addAnimations { [weak self] in self?.layoutContents() }
        layoutAnimator = animator
        animator.startAnimation()
        for (glyph, radius) in zip(glyphs, blurRadii) { glyph.animateTitleBlur(from: radius, animated: true) }
    }

    private func selectionFrame(lifted: Bool) -> CGRect {
        var frame = itemFrame(scrub?.preview ?? selectedIndex)
        if scrub != nil, tracksSelectionMotion {
            let center = convertScrubPointToContent().y
            frame.origin.y = max(0, min(contentSize.height - frame.height, center - frame.height / 2))
        }
        return lifted ? frame.insetBy(dx: -10, dy: -10) : frame
    }

    private func convertScrubPointToContent() -> CGPoint {
        guard let scrub else { return .zero }
        return convert(CGPoint(x: scrub.initial.x + scrub.translation.x,
                               y: scrub.initial.y + scrub.translation.y), to: contentView)
    }

    private func updateSelection(animated: Bool) {
        currentSelectionFrame = selectionFrame(lifted: scrub != nil)
        let apply = {
            let target = self.lens ?? self.fallbackSelection
            if let lens = self.lens {
                self.applyLensGeometry(lens, animated: animated)
            } else {
                target.bounds = CGRect(origin: .zero, size: self.currentSelectionFrame.size)
                target.center = CGPoint(x: self.currentSelectionFrame.midX, y: self.currentSelectionFrame.midY)
            }
            target.cornerConfiguration = .corners(radius: .fixed(self.scrub == nil ? 26 : 36))
            self.fallbackSelection.layer.cornerRadius = min(target.bounds.width, target.bounds.height) / 2
            if self.lens == nil {
                let mask = CAShapeLayer()
                mask.path = UIBezierPath(roundedRect: self.currentSelectionFrame, cornerRadius: min(target.bounds.width, target.bounds.height) / 2).cgPath
                self.selectedContent.layer.mask = mask
            }
            for item in self.selectedItems {
                item.transform = self.scrub == nil ? .identity : CGAffineTransform(scaleX: 1.16, y: 1.16)
            }
        }
        if tracksSelectionMotion && !UIAccessibility.isReduceMotionEnabled {
            UIView.animate(trackingSpring, changes: apply)
        } else if animated && !UIAccessibility.isReduceMotionEnabled {
            UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.82, initialSpringVelocity: 0, options: [.beginFromCurrentState, .allowUserInteraction], animations: apply)
        } else { apply() }
    }

    private func applyLensGeometry(_ lens: UIView, animated: Bool) {
        // UIKit can defer the lift callback. Coalesce newer layouts until it has
        // applied its bounds, otherwise the resting background keeps stale geometry.
        guard !isApplyingLensLift else { return }
        // UIKit does not run lift callbacks for a lens in a hidden window.
        let lifted = scrub != nil && window?.isHidden == false
        let frame = currentSelectionFrame
        let bounds = CGRect(origin: .zero, size: frame.size)
        let center = CGPoint(x: frame.midX, y: frame.midY)
        // Finishing an interrupted property animator at .current changes the model
        // geometry, so compare the actual view rather than a cached destination.
        guard lens.bounds != bounds || lens.center != center || appliedLensLifted != lifted else { return }
        if appliedLensLifted != lifted {
            appliedLensLifted = lifted
            isApplyingLensLift = true
            var didApply = false
            var callReturned = false
            let animateLift = animated && window?.isHidden == false && !UIAccessibility.isReduceMotionEnabled
            WSetLiquidLensLifted(lens, lifted, animateLift) { [weak self, weak lens] in
                guard let self, let lens else { return }
                lens.bounds = bounds
                didApply = true
                if callReturned {
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        self.isApplyingLensLift = false
                        self.updateSelection(animated: false)
                    }
                }
            }
            lens.center = center
            callReturned = true
            if didApply { isApplyingLensLift = false }
        } else {
            // The lens owns its bounds animation. A second UIView size animation
            // can leave its internal selection background at an intermediate size.
            lens.layer.removeAllAnimations()
            UIView.performWithoutAnimation { lens.bounds = bounds }
            lens.center = center
        }
    }

    private func setLifted(_ lifted: Bool) {
        updateSelection(animated: true)
        displayLink?.invalidate()
        displayLink = nil
        if lifted {
            displayLink = .makeWeak(owner: self) { bar, link in
                bar.scrollExpandedContent(duration: link.targetTimestamp - link.timestamp)
                bar.refreshLiftedPosition()
            }
        }
    }

    private func scrollExpandedContent(duration: TimeInterval) {
        guard showsTitles, tracksSelectionMotion, let scrub,
              scrollView.contentSize.height > scrollView.bounds.height else { return }
        let point = convertScrubPointToContent()
        let visibleY = point.y - scrollView.contentOffset.y
        let edge = min(40, scrollView.bounds.height / 3)
        guard edge > 0 else { return }
        let speed: CGFloat
        if visibleY < edge {
            speed = -min(1, (edge - visibleY) / edge)
        } else if visibleY > scrollView.bounds.height - edge {
            speed = min(1, (visibleY - scrollView.bounds.height + edge) / edge)
        } else {
            return
        }
        let offset = max(0, min(scrollView.contentSize.height - scrollView.bounds.height,
                                scrollView.contentOffset.y + speed * 300 * duration))
        guard offset != scrollView.contentOffset.y else { return }
        scrollView.contentOffset.y = offset
        moveScrub(translation: scrub.translation)
    }

    fileprivate func refreshLiftedPosition() {
        guard !isApplyingLensLift else { return }
        let center = CGPoint(x: currentSelectionFrame.midX, y: currentSelectionFrame.midY)
        if tracksSelectionMotion && !UIAccessibility.isReduceMotionEnabled {
            UIView.animate(trackingSpring) { self.lens?.center = center }
        } else {
            lens?.center = center
        }
    }

    public override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        surface.bounds.insetBy(dx: -8, dy: 0).contains(convert(point, to: surface))
    }

    private func updateAccessibility() {
        for (index, target) in targets.enumerated() {
            target.accessibilityTraits = showsSelection && index == selectedIndex ? [.button, .selected] : .button
        }
    }
}

@available(iOS 26.0, *)
@MainActor
private final class VerticalTabScrubRecognizer: UIGestureRecognizer {
    var shouldWaitForHold: (() -> Bool)?
    private var holdTimer: Timer?
    private(set) var initial = CGPoint.zero
    private(set) var current = CGPoint.zero
    private(set) var initialTimestamp: TimeInterval = 0
    var translation: CGPoint { CGPoint(x: current.x - initial.x, y: current.y - initial.y) }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard touches.count == 1, let touch = touches.first else { state = .cancelled; return }
        initialTimestamp = touch.timestamp
        initial = touch.location(in: view)
        current = initial
        if shouldWaitForHold?() == true {
            let timer = Timer(timeInterval: 0.25, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.state == .possible else { return }
                    self.state = .began
                }
            }
            holdTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        } else {
            state = .began
        }
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first else { return }
        current = touch.location(in: view)
        if state == .possible {
            if hypot(translation.x, translation.y) > 10 {
                holdTimer?.invalidate()
                state = .failed
            }
        } else {
            state = .changed
        }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        if state == .possible { state = .began }
        state = .ended
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { state = .cancelled }
    override func reset() {
        holdTimer?.invalidate()
        holdTimer = nil
        super.reset()
    }
}

private final class VerticalTabAccessibilityTarget: UIView {
    var activate: (() -> Bool)?
    override func accessibilityActivate() -> Bool { activate?() ?? false }
}

@available(iOS 26.0, *)
private final class VerticalTabGlyph: UIView {
    private let icon: UIImageView
    private let label = UILabel()
    private let titleWrapper = UIView()
    init(item: WVerticalTabBar.Item) {
        icon = UIImageView(image: item.image.withRenderingMode(.alwaysTemplate))
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
        icon.contentMode = .scaleAspectFit
        label.text = item.title
        label.textAlignment = .center
        addSubview(icon)
        addSubview(titleWrapper)
        titleWrapper.addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func tintColorDidChange() {
        super.tintColorDidChange()
        icon.tintColor = tintColor
        label.textColor = tintColor
    }
    var titleBlurRadius: CGFloat { WTitleBlurRadius(titleWrapper) }
    func animateTitleBlur(from radius: CGFloat, animated: Bool) {
        WAnimateTitleBlur(titleWrapper, radius, animated ? titleWrapper.layer.animation(forKey: "opacity") : nil)
    }
    func titleSpringVelocity(toward target: CGFloat) -> CGFloat {
        let layer = titleWrapper.layer
        guard let spring = layer.animation(forKey: "opacity") as? CASpringAnimation,
              let from = spring.fromValue as? NSNumber, let to = spring.toValue as? NSNumber else { return 0 }
        let time = layer.convertTime(CACurrentMediaTime(), from: nil) - spring.beginTime
        guard time >= 0, time < spring.duration else { return 0 }
        let distance = Double(target) - Double(layer.presentation()?.opacity ?? layer.opacity)
        guard abs(distance) > 0.001 else { return 0 }
        // Carry the running spring's velocity into the new target on early release.
        let decay = spring.damping / (2 * spring.mass)
        let frequency = sqrt(spring.stiffness / spring.mass - decay * decay)
        let a = from.doubleValue - to.doubleValue
        let b = (spring.initialVelocity * -a + decay * a) / frequency
        let velocity = exp(-decay * time) * ((b * frequency - decay * a) * cos(frequency * time)
                                            - (a * frequency + decay * b) * sin(frequency * time))
        return CGFloat(velocity / distance)
    }
    func layoutGlyph(expanded: Bool, font: UIFont) {
        label.font = font
        titleWrapper.alpha = expanded ? 1 : 0
        WSetTitleBlur(titleWrapper, expanded ? 0 : 5.0 / 3)
        icon.frame = CGRect(x: bounds.midX - 14, y: expanded ? 11 : bounds.midY - 14, width: 28, height: 28)
        // Keep the text raster fixed while the platter expands and its wrapper fades.
        titleWrapper.bounds = CGRect(origin: .zero, size: CGSize(width: ceil(label.intrinsicContentSize.width), height: ceil(font.lineHeight)))
        titleWrapper.center = CGPoint(x: bounds.midX, y: expanded ? 40 + ceil(font.lineHeight) / 2 : 143.0 / 3)
        UIView.performWithoutAnimation { label.frame = titleWrapper.bounds }
    }
}
