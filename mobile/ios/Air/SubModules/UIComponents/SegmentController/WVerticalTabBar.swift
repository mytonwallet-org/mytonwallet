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
    public private(set) var selectedIndex = 0
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

    private let items: [Item]
    private let surface = UIView()
    private let glass = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
    private let stage = UIView()
    private let normalContent = UIView()
    private let selectedContent = UIView()
    private let fallbackSelection = UIView()
    private let lens: UIView?
    private var usesNativeFlex = false
    private var normalItems: [VerticalTabGlyph] = []
    private var selectedItems: [VerticalTabGlyph] = []
    private var targets: [VerticalTabAccessibilityTarget] = []
    private var scrub: (start: Int, offset: CGFloat, preview: Int)?
    private var showsTitles = false
    private var tracksSelectionMotion = false
    private var holdTimer: Timer?
    private var layoutAnimator: UIViewPropertyAnimator?
    private var displayLink: CADisplayLink?
    private var currentSelectionFrame = CGRect.zero
    private var appliedLensLifted: Bool?
    private var isApplyingLensLift = false
    private let feedback = UISelectionFeedbackGenerator()
    private let trackingSpring = Animation.spring(response: 0.2, dampingFraction: 0.85)
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
        surface.addSubview(stage)
        stage.layer.zPosition = 2
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
            target.activate = { [weak self] in self?.activate(index); return true }
            target.isUserInteractionEnabled = false
            surface.addSubview(target)
            targets.append(target)
        }
        scrubRecognizer.delaysTouchesBegan = false
        scrubRecognizer.delaysTouchesEnded = false
        addGestureRecognizer(scrubRecognizer)
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
    private var surfaceSize: CGSize {
        guard showsTitles else { return intrinsicContentSize }
        let longestTitle = items.map { ($0.title as NSString).size(withAttributes: [.font: labelFont]).width }.max() ?? 0
        return CGSize(width: max(72, ceil(longestTitle) + 36), height: CGFloat(items.count) * expandedItemHeight - CGFloat(items.count - 1) * 8 + 8)
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        layoutContents()
    }

    private func layoutContents() {
        let size = surfaceSize
        surface.bounds = CGRect(origin: .zero, size: size)
        // Expand downwards from the upper rail. Long localized titles grow inward.
        let x = showsTitles ? (isOnLeftEdge ? size.width / 2 - 12 : bounds.width + 12 - size.width / 2) : bounds.midX
        surface.center = CGPoint(x: x, y: size.height / 2 - (showsTitles ? 4 : 0))
        surface.transform = !usesNativeFlex && scrub != nil ? CGAffineTransform(scaleX: 1.05513372346085, y: 1.05513372346085) : .identity
        glass.frame = surface.bounds
        glass.cornerConfiguration = surface.cornerConfiguration
        stage.frame = surface.bounds
        normalContent.frame = surface.bounds
        selectedContent.frame = surface.bounds
        for index in items.indices {
            let frame = itemFrame(index)
            for glyph in [normalItems[index], selectedItems[index]] {
                glyph.bounds = CGRect(origin: .zero, size: frame.size)
                glyph.center = CGPoint(x: frame.midX, y: frame.midY)
                glyph.layoutGlyph(expanded: showsTitles, font: labelFont)
            }
            normalItems[index].tintColor = .label
            selectedItems[index].tintColor = tintColor
            targets[index].frame = frame
        }
        updateSelection(animated: false)
    }

    private func itemFrame(_ index: Int) -> CGRect {
        if showsTitles {
            return CGRect(x: 4, y: 4 + CGFloat(index) * (expandedItemHeight - 8), width: surfaceSize.width - 8, height: expandedItemHeight)
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
        case .began: beginScrub(at: recognizer.current, timestamp: recognizer.initialTimestamp)
        case .changed: moveScrub(translation: recognizer.translation)
        case .ended: finishScrub(cancelled: false)
        case .failed, .cancelled: finishScrub(cancelled: true)
        default: break
        }
    }

    func beginScrub(at point: CGPoint, timestamp: TimeInterval? = nil) {
        let start = timestamp ?? CACurrentMediaTime()
        let index = nearestIndex(to: convert(point, to: surface).y)
        scrub = (index, 0, index)
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
    }

    func moveScrub(translation: CGPoint) {
        guard var scrub else { return }
        scrub.offset = translation.y.rounded()
        let index = nearestIndex(to: itemFrame(scrub.start).midY + scrub.offset)
        if index != scrub.preview { feedback.selectionChanged() }
        scrub.preview = index
        self.scrub = scrub
        if !tracksSelectionMotion { lens?.layer.removeAllAnimations() }
        tracksSelectionMotion = true
        updateSelection(animated: false)
    }

    func finishScrub(cancelled: Bool) {
        holdTimer?.invalidate()
        holdTimer = nil
        guard let scrub else { return }
        let repeated = showsSelection && selectedIndex == scrub.preview
        self.scrub = nil
        tracksSelectionMotion = false
        showsTitles = false
        if !cancelled { selectedIndex = scrub.preview }
        setLifted(false)
        animateLayout(damping: 0.75)
        updateAccessibility()
        if !cancelled { onSelect?(scrub.preview, repeated) }
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
        if let scrub {
            let center = itemFrame(scrub.start).midY + scrub.offset
            frame.origin.y = max(0, min(surfaceSize.height - frame.height, center - frame.height / 2))
        }
        return lifted ? frame.insetBy(dx: -10, dy: -10) : frame
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
        if lifted, lens != nil {
            displayLink = .makeWeak(owner: self) { bar, _ in bar.refreshLiftedPosition() }
        }
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
    private var initial = CGPoint.zero
    private(set) var current = CGPoint.zero
    private(set) var initialTimestamp: TimeInterval = 0
    var translation: CGPoint { CGPoint(x: current.x - initial.x, y: current.y - initial.y) }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard touches.count == 1, let touch = touches.first else { state = .cancelled; return }
        initialTimestamp = touch.timestamp
        initial = touch.location(in: view)
        current = initial
        state = .began
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first else { return }
        current = touch.location(in: view)
        state = .changed
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) { state = .ended }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { state = .cancelled }
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
