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
    private let displayLinkTarget = DisplayLinkTarget()
    private var isApplyingNativeState = false
    private var pendingNativeState: (State, Bool)?
    private var appliedNativeState: State?
    private var generation = 0
    private var contentSize: CGSize?

    private struct State: Equatable {
        var frame: CGRect
        var isLifted: Bool
    }

    private(set) var selectionFrame: CGRect?
    private(set) var isLifted = false
    var usesNativeLens: Bool { nativeLens != nil }

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
        displayLinkTarget.owner = self
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
        self.isLifted = selectionFrame != nil && nativeLens != nil && isLifted && !UIAccessibility.isReduceMotionEnabled
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

    func cancelAnimations() {
        generation += 1
        isApplyingNativeState = false
        pendingNativeState = nil
        appliedNativeState = nil
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
        let inset: CGFloat = state.isLifted ? 6 : 0
        let lensBounds = CGRect(origin: .zero, size: state.frame.insetBy(dx: -inset, dy: -inset).size)
        let center = CGPoint(x: state.frame.midX, y: state.frame.midY)

        if previous?.isLifted != state.isLifted {
            let generation = generation
            var appliedSynchronously = false
            var returned = false
            Native.setLifted(nativeLens, lifted: state.isLifted, animated: animated) { [weak self, weak nativeLens] in
                guard let self, let nativeLens, self.generation == generation else { return }
                nativeLens.bounds = lensBounds
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
            // UIKit's lens owns its size animation; animating those layers again breaks its warp.
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
        if isLifted && window != nil {
            if displayLink == nil {
                let link = CADisplayLink(target: displayLinkTarget, selector: #selector(DisplayLinkTarget.tick))
                link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 120)
                link.add(to: .main, forMode: .common)
                displayLink = link
            }
        } else {
            displayLink?.invalidate()
            displayLink = nil
        }
    }

    @MainActor private final class DisplayLinkTarget: NSObject {
        weak var owner: WSegmentedControlLensView?
        @objc func tick() {
            guard let owner, !owner.isApplyingNativeState, let state = owner.appliedNativeState else { return }
            // UIKit only advances the lifted bounce while its position is being updated.
            owner.nativeLens?.center = CGPoint(x: state.frame.midX, y: state.frame.midY)
        }
    }

    @MainActor private final class RestingBackgroundView: UIVisualEffectView {
        private var isDark: Bool?

        init() {
            super.init(effect: UIBlurEffect(style: .light))
            for subview in subviews where subview.description.contains(String("weivbuStceffElausiV".reversed())) {
                subview.isHidden = true
            }
            clipsToBounds = true
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        func update(isDark: Bool) {
            guard self.isDark != isDark else { return }
            self.isDark = isDark
            guard let sublayer = layer.sublayers?.first, sublayer.filters != nil else { return }
            sublayer.backgroundColor = nil
            sublayer.isOpaque = false
            let makeFilter = Native.selector(":emaNhtiWretlif")
            guard let cls = NSClassFromString(String("retliFAC".reversed())) as? NSObject.Type,
                  cls.responds(to: makeFilter),
                  let filter = cls.perform(makeFilter, with: String("xirtaMroloc".reversed()))?.takeUnretainedValue() as? NSObject else { return }
            var matrix: [Float32] = isDark
                ? [1.082, -0.113, -0.011, 0, 0.135, -0.034, 1.003, -0.011, 0, 0.135, -0.034, -0.113, 1.105, 0, 0.135, 0, 0, 0, 1, 0]
                : [1.185, -0.05, -0.005, 0, -0.2, -0.015, 1.15, -0.005, 0, -0.2, -0.015, -0.05, 1.195, 0, -0.2, 0, 0, 0, 1, 0]
            filter.setValue(NSValue(bytes: &matrix, objCType: "{CAColorMatrix=ffffffffffffffffffff}"), forKey: String("xirtaMroloCtupni".reversed()))
            sublayer.filters = [filter]
            sublayer.setValue(1.0, forKey: String("elacs".reversed()))
        }
    }

    @MainActor private enum Native {
        static let liftedContainer = selector(":weiVreniatnoCdetfiLtes")
        static let liftedContent = selector(":weiVtnetnoCdetfiLtes")
        static let punchout = selector(":weiVtuohcnuPedirrevOtes")
        static let lift = selector(":noitelpmoc:snoitaminAedisgnola:detamina:detfiLtes")
        static let mode = selector(":edoMtnetnoCdetfiLtes")
        static let style = selector(":elytStes")
        static let warp = selector(":woleBtnetnoCspraWtes")
        static let restingColor = selector(":roloCdnuorgkcaBgnitseRtes")

        static func selector(_ reversed: String) -> Selector {
            NSSelectorFromString(String(reversed.reversed()))
        }

        static func makeLens() -> UIView? {
            guard #available(iOS 26, *) else { return nil }
            let initialize = selector(":dnuorgkcaBgnitseRhtiWtini")
            guard let cls = NSClassFromString(String("weiVsneLdiuqiLIU_".reversed())) as? NSObject.Type,
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
