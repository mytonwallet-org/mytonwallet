import UIKit

// Mirrors Telegram's LiquidLensView, with optional runtime entry points and a masked fallback.
// https://github.com/TelegramMessenger/Telegram-iOS/blob/6ad963e5b62d354da79040f388ae2b9132fb17b8/submodules/TelegramUI/Components/LiquidLens/Sources/LiquidLensView.swift
@MainActor
final class WSegmentedControlLensView: UIView {
    let contentView = UIView()
    let selectedContentView = UIView()

    private let containerView = UIView()
    private let restingBackgroundView = RestingBackgroundView()
    private let fallbackSelectionView = UIView()
    private let normalMask = CAShapeLayer()
    private let selectedMask = CAShapeLayer()
    private let nativeLens: UIView?
    private weak var liftedContainer: UIView?
    private var displayLink: CADisplayLink?
    private var isApplyingNativeState = false
    private var pendingNativeState: (State, Bool)?
    private var appliedNativeState: State?
    private var generation = 0
    private var contentSize: CGSize?
    private var liftInset: CGFloat = 0
    private var liftTransition: (from: CGFloat, to: CGFloat, startTime: CFTimeInterval)?

    private struct State: Equatable {
        var frame: CGRect
        var isLifted: Bool
    }

    private var renderedAppearance: UIUserInterfaceStyle?

    private(set) var selectionFrame: CGRect?
    private(set) var isLifted = false
    var usesNativeLens: Bool { nativeLens != nil }

    /// The tint the system lens rests its selection on, for a copy of the tabs: the same color matrix over what lies
    /// behind it, the glass and the selected items alike, in the appearance of the window it shows in
    static func makeRestingBackgroundCopy() -> UIView {
        let view = RestingBackgroundView()
        view.isUserInteractionEnabled = false
        view.followsWindowAppearance = true
        return view
    }

    init(useNativeLens: Bool = true) {
        nativeLens = useNativeLens ? Native.makeLens() : nil
        super.init(frame: .zero)
        addSubview(containerView)
        containerView.isUserInteractionEnabled = false
        selectedContentView.accessibilityElementsHidden = true

        if let nativeLens {
            containerView.layer.zPosition = 1
            nativeLens.layer.zPosition = 10
            selectedContentView.addSubview(restingBackgroundView)
            containerView.addSubview(selectedContentView)
            containerView.addSubview(nativeLens)
            containerView.addSubview(contentView)
            Native.setObject(nativeLens, Native.liftedContainer, containerView)
            Native.setObject(nativeLens, Native.liftedContent, selectedContentView)
            Native.setObject(nativeLens, Native.punchout, contentView)
        } else {
            fallbackSelectionView.isUserInteractionEnabled = false
            fallbackSelectionView.layer.cornerCurve = .continuous
            containerView.addSubview(fallbackSelectionView)
            containerView.addSubview(contentView)
            containerView.addSubview(selectedContentView)
            normalMask.fillRule = .evenOdd
            normalMask.fillColor = UIColor.black.cgColor
            selectedMask.fillColor = UIColor.black.cgColor
            contentView.layer.mask = normalMask
            selectedContentView.layer.mask = selectedMask
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    deinit {
        displayLink?.invalidate()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateDisplayLink()
    }

    func setLiftedContainer(_ view: UIView?) {
        guard liftedContainer !== view else { return }
        liftedContainer = view
        if let nativeLens {
            Native.setObject(nativeLens, Native.liftedContainer, view ?? containerView)
        }
    }

    func update(selectionFrame: CGRect?, isLifted: Bool, color: UIColor, animated: Bool) {
        let geometryChanged = self.selectionFrame != selectionFrame || contentSize != bounds.size
        self.selectionFrame = selectionFrame
        let animated = animated && UIView.areAnimationsEnabled && !UIAccessibility.isReduceMotionEnabled
        let wasLifted = self.isLifted
        self.isLifted = selectionFrame != nil && nativeLens != nil && isLifted && !UIAccessibility.isReduceMotionEnabled
        if self.isLifted != wasLifted {
            advanceLiftTransition()
            let targetInset: CGFloat = self.isLifted ? 6 : 0
            if animated {
                liftTransition = (liftInset, targetInset, CACurrentMediaTime())
            } else {
                liftTransition = nil
                liftInset = targetInset
            }
        }
        containerView.frame = bounds
        if contentSize != bounds.size {
            contentSize = bounds.size
            contentView.frame = bounds
            selectedContentView.frame = bounds
        }
        selectedContentView.isHidden = selectionFrame == nil
        nativeLens?.isHidden = selectionFrame == nil
        fallbackSelectionView.isHidden = selectionFrame == nil
        fallbackSelectionView.backgroundColor = color

        let frame = selectionFrame ?? .zero
        if nativeLens != nil {
            restingBackgroundView.frame = CGRect(origin: .zero, size: bounds.size)
            // Rounded as the tabs' capsule, so a selection scrolled partly out of view doesn't show square corners
            // past the capsule's ends
            restingBackgroundView.layer.cornerRadius = bounds.height / 2
            restingBackgroundView.layer.cornerCurve = .continuous
            restingBackgroundView.update(isDark: traitCollection.userInterfaceStyle == .dark)
            let restingAlpha: CGFloat = self.isLifted ? 0 : 1
            if restingBackgroundView.alpha != restingAlpha {
                animate(animated) { self.restingBackgroundView.alpha = restingAlpha }
            }
            applyNativeState(State(frame: frame, isLifted: self.isLifted), animated: animated)
        } else if geometryChanged {
            let normalPath = UIBezierPath(rect: bounds)
            if selectionFrame != nil {
                normalPath.append(UIBezierPath(roundedRect: frame, cornerRadius: frame.height / 2))
            }
            let selectedPath = UIBezierPath(roundedRect: frame, cornerRadius: frame.height / 2)
            updateMask(normalMask, path: normalPath.cgPath, animated: animated)
            updateMask(selectedMask, path: selectedPath.cgPath, animated: animated)
            animate(animated) {
                self.fallbackSelectionView.frame = frame
                self.fallbackSelectionView.layer.cornerRadius = frame.height / 2
            }
        }
        updateDisplayLink()
    }

    /// Makes the selection redraw for the current light or dark appearance. The system lens keeps drawing the selected
    /// content and its resting background as it last rendered them until its state changes, as a touch changes it, so
    /// after a change of appearance it would keep the old colors.
    func refreshAppearance() {
        let style = traitCollection.userInterfaceStyle
        guard renderedAppearance != style else { return }
        renderedAppearance = style
        guard let nativeLens else { return }
        restingBackgroundView.invalidateAppearance()
        restingBackgroundView.update(isDark: style == .dark)
        Native.setObject(nativeLens, Native.restingColor, UIColor(white: 0, alpha: 0.1))
        Native.setObject(nativeLens, Native.liftedContent, selectedContentView)
        guard !isApplyingNativeState, let state = appliedNativeState else { return }
        appliedNativeState = nil
        applyNativeState(state, animated: false)
    }

    func cancelAnimations() {
        generation += 1
        isApplyingNativeState = false
        pendingNativeState = nil
        appliedNativeState = nil
        liftTransition = nil
        liftInset = isLifted ? 6 : 0
        for view in [nativeLens, restingBackgroundView, fallbackSelectionView, selectedContentView, contentView] {
            view?.layer.removeAllAnimations()
        }
        normalMask.removeAllAnimations()
        selectedMask.removeAllAnimations()
    }

    private func applyNativeState(_ state: State, animated: Bool) {
        guard let nativeLens else { return }
        if isApplyingNativeState {
            pendingNativeState = (state, animated)
            return
        }
        guard appliedNativeState != state else { return }
        isApplyingNativeState = true
        let previous = appliedNativeState
        appliedNativeState = state
        let lensBounds = nativeBounds(for: state)
        let center = CGPoint(x: state.frame.midX, y: state.frame.midY)

        if previous?.isLifted != state.isLifted {
            let generation = generation
            var appliedSynchronously = false
            var returned = false
            Native.setLifted(nativeLens, lifted: state.isLifted, animated: animated) { [weak self, weak nativeLens] in
                guard let self, let nativeLens, self.generation == generation else { return }
                // UIKit otherwise captures the tab width for the whole lift animation,
                // hiding pager width updates until it ends and then snapping to them.
                UIView.performWithoutAnimation {
                    nativeLens.bounds = self.nativeBounds(for: state)
                }
                appliedSynchronously = true
                if returned {
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.generation == generation else { return }
                        self.finishNativeUpdate()
                    }
                }
            }
            animate(animated) { nativeLens.center = center }
            returned = true
            if appliedSynchronously {
                finishNativeUpdate()
            }
        } else {
            let previousWidth = nativeLens.bounds.width
            // Pager frames supply their own geometry; only discrete selections animate position.
            nativeLens.layer.removeAllAnimations()
            nativeLens.bounds = lensBounds
            animate(animated) { nativeLens.center = center }
            if animated {
                let animation = CASpringAnimation(keyPath: "position.x")
                animation.fromValue = (lensBounds.width - previousWidth) * 0.5
                animation.toValue = 0
                animation.isAdditive = true
                animation.mass = 1
                animation.stiffness = 380
                animation.damping = 35
                animation.duration = 0.32
                nativeLens.layer.add(animation, forKey: "widthOffset")
            }
            finishNativeUpdate()
        }
    }

    private func finishNativeUpdate() {
        isApplyingNativeState = false
        if let (state, animated) = pendingNativeState {
            pendingNativeState = nil
            applyNativeState(state, animated: animated)
        }
    }

    private func nativeBounds(for state: State) -> CGRect {
        CGRect(origin: .zero, size: state.frame.insetBy(dx: -liftInset, dy: -liftInset).size)
    }

    private func advanceLiftTransition() {
        guard let transition = liftTransition else { return }
        let progress = min(1, (CACurrentMediaTime() - transition.startTime) / 0.32)
        let eased = 1 - pow(1 - progress, 3)
        liftInset = transition.from + (transition.to - transition.from) * eased
        if progress >= 1 {
            liftTransition = nil
        }
    }

    private func updateMask(_ mask: CAShapeLayer, path: CGPath, animated: Bool) {
        let previous = mask.presentation()?.path ?? mask.path
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        mask.frame = bounds
        mask.path = path
        CATransaction.commit()
        if animated, let previous {
            let animation = CABasicAnimation(keyPath: "path")
            animation.fromValue = previous
            animation.toValue = path
            animation.duration = 0.32
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            mask.add(animation, forKey: "selection")
        } else {
            mask.removeAllAnimations()
        }
    }

    private func animate(_ animated: Bool, _ body: @escaping () -> Void) {
        if animated {
            UIView.animate(withDuration: 0.32, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0,
                           options: [.beginFromCurrentState, .allowUserInteraction], animations: body)
        } else {
            UIView.performWithoutAnimation(body)
        }
    }

    private func updateDisplayLink() {
        if (isLifted || liftTransition != nil) && window != nil {
            if displayLink == nil {
                displayLink = .makeWeak(
                    owner: self,
                    frameRateRange: CAFrameRateRange(minimum: 30, maximum: 120, preferred: 120)
                ) { owner, _ in owner.advanceNativeLens() }
            }
        } else {
            displayLink?.invalidate()
            displayLink = nil
        }
    }

    private func advanceNativeLens() {
        guard !isApplyingNativeState, let state = appliedNativeState else { return }
        advanceLiftTransition()
        UIView.performWithoutAnimation {
            nativeLens?.bounds = nativeBounds(for: state)
        }
        // UIKit only advances the lifted bounce while its position is being updated.
        nativeLens?.center = CGPoint(x: state.frame.midX, y: state.frame.midY)
        updateDisplayLink()
    }

    @MainActor private final class RestingBackgroundView: UIVisualEffectView {
        private var isDark: Bool?
        /// Takes the appearance of each window it moves into, for a copy that no lens updates
        var followsWindowAppearance = false

        init() {
            super.init(effect: UIBlurEffect(style: .light))
            for subview in subviews where subview.description.contains(PrivateAPI.visualEffectSubview.string) {
                subview.isHidden = true
            }
            clipsToBounds = true
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard followsWindowAppearance, window != nil else { return }
            invalidateAppearance()
            update(isDark: traitCollection.userInterfaceStyle == .dark)
        }

        func invalidateAppearance() {
            isDark = nil
        }

        func update(isDark: Bool) {
            guard self.isDark != isDark else { return }
            self.isDark = isDark
            guard let sublayer = layer.sublayers?.first, sublayer.filters != nil else { return }
            sublayer.backgroundColor = nil
            sublayer.isOpaque = false
            guard let filter = PrivateAPI.makeFilter(PrivateAPI.colorMatrixFilterType.string) else { return }
            var matrix: [Float32] = isDark
                ? [1.082, -0.113, -0.011, 0, 0.135, -0.034, 1.003, -0.011, 0, 0.135, -0.034, -0.113, 1.105, 0, 0.135, 0, 0, 0, 1, 0]
                : [1.185, -0.05, -0.005, 0, -0.2, -0.015, 1.15, -0.005, 0, -0.2, -0.015, -0.05, 1.195, 0, -0.2, 0, 0, 0, 1, 0]
            filter.setValue(NSValue(bytes: &matrix, objCType: "{CAColorMatrix=ffffffffffffffffffff}"), forKey: PrivateAPI.inputColorMatrix.string)
            sublayer.filters = [filter]
            sublayer.setValue(1.0, forKey: "scale")
        }
    }

    @MainActor private enum Native {
        static let liftedContainer = PrivateAPI.liquidLensSetLiftedContainerView.selector
        static let liftedContent = PrivateAPI.liquidLensSetLiftedContentView.selector
        static let punchout = PrivateAPI.liquidLensSetOverridePunchoutView.selector
        static let lift = PrivateAPI.liquidLensSetLifted.selector
        static let mode = PrivateAPI.liquidLensSetLiftedContentMode.selector
        static let style = PrivateAPI.liquidLensSetStyle.selector
        static let warp = PrivateAPI.liquidLensSetWarpsContentBelow.selector
        static let restingColor = PrivateAPI.liquidLensSetRestingBackgroundColor.selector

        static func makeLens() -> UIView? {
            guard #available(iOS 26, *) else { return nil }
            let initialize = PrivateAPI.liquidLensInitWithRestingBackground.selector
            guard let cls = PrivateAPI.liquidLensView.objectClass,
                  let method = class_getInstanceMethod(cls, initialize),
                  [liftedContainer, liftedContent, punchout, lift, mode, style, warp, restingColor]
                    .allSatisfy({ class_getInstanceMethod(cls, $0) != nil }),
                  let allocated = cls.perform(NSSelectorFromString("alloc")) else { return nil }
            typealias Initialize = @convention(c) (UnsafeMutableRawPointer, Selector, UIView) -> Unmanaged<AnyObject>?
            let function = unsafeBitCast(method_getImplementation(method), to: Initialize.self)
            guard let view = function(allocated.toOpaque(), initialize, UIView())?.takeRetainedValue() as? UIView else { return nil }
            typealias SetInteger = @convention(c) (UIView, Selector, Int32) -> Void
            for selector in [mode, style] {
                unsafeBitCast(view.method(for: selector), to: SetInteger.self)(view, selector, 1)
            }
            typealias SetBoolean = @convention(c) (UIView, Selector, Bool) -> Void
            unsafeBitCast(view.method(for: warp), to: SetBoolean.self)(view, warp, true)
            setObject(view, restingColor, UIColor(white: 0, alpha: 0.1))
            return view
        }

        static func setObject(_ view: UIView, _ selector: Selector, _ object: AnyObject) {
            view.perform(selector, with: object)
        }

        static func setLifted(_ view: UIView, lifted: Bool, animated: Bool, alongside: @escaping () -> Void) {
            typealias Block = @convention(block) () -> Void
            typealias SetLifted = @convention(c) (UIView, Selector, Bool, Bool, Block, Block?) -> Void
            unsafeBitCast(view.method(for: lift), to: SetLifted.self)(view, lift, lifted, animated, alongside, nil)
        }
    }
}
