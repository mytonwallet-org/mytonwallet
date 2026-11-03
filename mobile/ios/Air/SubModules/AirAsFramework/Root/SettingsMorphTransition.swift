import UIKit
import UIKit.UIGestureRecognizerSubclass
import UIComponents
import UISettings
import WalletCore

enum SettingsMorphTiming {
    static let response: Double = 0.37
    static let launchVelocity: Double = 1
    static let slideDamping: Double = 1
    static let parallax: CGFloat = 0.3
    static let glassDamping: Double = 0.82
    static let glassSwell: CGFloat = 0.5
    static let swellResponse: Double = 0.25
    static let swellDamping: Double = 0.42
    static let glassMinGap: CGFloat = 10
    static let glassMergeSpacing: CGFloat = 10
    static let dropSpring = (response: 0.42, damping: 0.72, launch: 0.0)
    static let growSpring = (response: 0.4, damping: 0.85, launch: 0.5)
    static let riseSpring = (response: 0.22, damping: 1.0, launch: 0.7)
    static let shrinkSpring = (response: 0.28, damping: 1.0, launch: 0.6)

    static let labelsOut: (delay: Double, duration: Double) = (0, 0.1)
    static let labelsIn: (delay: Double, duration: Double) = (0.07, 0.16)
    static let iconsIn: (delay: Double, duration: Double) = (0.1, 0.18)
    static let iconsOut: (delay: Double, duration: Double) = (0, 0.06)
    static let iconsStartScale: CGFloat = 0.6
    static let blurRadius: CGFloat = 6
    static let avatarSwap: (delay: Double, duration: Double) = (0.02, 0.16)
    static let avatarSwapBack: (delay: Double, duration: Double) = (0.08, 0.16)

    static let pressGlow: (avatar: CGFloat, glass: CGFloat, duration: Double) = (0.35, 0.6, 0.22)

    static let keyframeCount = 90
}


/// Geometry captured while the horizontal root header is visible
struct SettingsMorphSource {
    var segmentedFrame: CGRect
    var segmentedSnapshot: UIView
    var avatarGlassFrame: CGRect
    var avatarFrame: CGRect
    var containerSize: CGSize
    var safeAreaInsets: UIEdgeInsets
    var layoutDirection: UIUserInterfaceLayoutDirection
    var pressLift: CGFloat = 1

    @MainActor
    func matches(_ view: UIView) -> Bool {
        containerSize == view.bounds.size && safeAreaInsets == view.safeAreaInsets
            && layoutDirection == view.effectiveUserInterfaceLayoutDirection
    }
}

@available(iOS 26, *)
@MainActor
final class SettingsMorphTransition: NSObject, UIViewControllerAnimatedTransitioning {
    private let isPush: Bool
    private let source: SettingsMorphSource
    private weak var navigationController: UINavigationController?
    private var cleanup: (() -> Void)?

    private static let slide = MorphSpring(response: SettingsMorphTiming.response,
                                          damping: SettingsMorphTiming.slideDamping,
                                          launch: SettingsMorphTiming.launchVelocity)
    private static let glass = MorphSpring(response: SettingsMorphTiming.response,
                                          damping: SettingsMorphTiming.glassDamping,
                                          launch: SettingsMorphTiming.launchVelocity)

    private var vertical: MorphSpring {
        MorphSpring(isPush ? SettingsMorphTiming.dropSpring : SettingsMorphTiming.riseSpring)
    }

    private var scale: MorphSpring {
        MorphSpring(isPush ? SettingsMorphTiming.growSpring : SettingsMorphTiming.shrinkSpring)
    }

    init(isPush: Bool, source: SettingsMorphSource, navigationController: UINavigationController) {
        self.isPush = isPush
        self.source = source
        self.navigationController = navigationController
    }

    func transitionDuration(using transitionContext: (any UIViewControllerContextTransitioning)?) -> TimeInterval {
        max(Self.slide.settlingDuration, vertical.settlingDuration, scale.settlingDuration,
            Self.swellCurve(of: Self.glass, from: 0).duration,
            Self.swellCurve(of: Self.glass, from: source.pressLift - 1).duration)
    }

    func animateTransition(using context: any UIViewControllerContextTransitioning) {
        guard let navigationController,
              let fromVC = context.viewController(forKey: .from),
              let toVC = context.viewController(forKey: .to),
              let fromView = context.view(forKey: .from),
              let toView = context.view(forKey: .to),
              let settings = (isPush ? toVC : fromVC) as? SettingsVC else {
            context.completeTransition(false)
            return
        }
        let container = context.containerView
        let navView = navigationController.view!
        let bar = navigationController.navigationBar
        toView.frame = context.finalFrame(for: toVC)
        if isPush {
            container.addSubview(toView)
        } else {
            container.insertSubview(toView, belowSubview: fromView)
        }
        toView.layoutIfNeeded()

        let overlay = UIView(frame: navView.bounds)
        overlay.accessibilityIdentifier = "settings_morph_overlay"
        overlay.isUserInteractionEnabled = false
        overlay.accessibilityElementsHidden = true
        navView.addSubview(overlay)
        // Mask the contents without changing the navigation bar's safe-area contribution
        let barContents = bar.subviews.map { (view: $0, mask: $0.layer.mask) }
        barContents.forEach { $0.view.layer.mask = CALayer() }

        let barMidY = source.avatarGlassFrame.midY
        let isRTL = source.layoutDirection == .rightToLeft
        let leadingMargin = isRTL ? bar.layoutMargins.right : bar.layoutMargins.left
        let trailingMargin = isRTL ? bar.layoutMargins.left : bar.layoutMargins.right
        let width = navView.bounds.width
        let backFrame = CGRect(x: isRTL ? width - leadingMargin - 44 : leadingMargin,
                               y: barMidY - 22, width: 44, height: 44)
        let trailingFrame = CGRect(x: isRTL ? trailingMargin : width - trailingMargin - 100,
                                   y: barMidY - 22, width: 100, height: 44)

        let glassEffect = UIGlassContainerEffect()
        glassEffect.spacing = SettingsMorphTiming.glassMergeSpacing
        let glassContainer = UIVisualEffectView(effect: glassEffect)
        glassContainer.frame = overlay.bounds
        overlay.addSubview(glassContainer)
        let tabsGlass = makeGlass()
        let accountGlass = makeGlass()
        glassContainer.contentView.addSubview(tabsGlass)
        glassContainer.contentView.addSubview(accountGlass)

        let labels = makeContent(source.segmentedSnapshot)
        labels.layer.anchorPoint = CGPoint(x: isRTL ? 1 : 0, y: 0.5)
        labels.frame = source.segmentedFrame
        overlay.addSubview(labels)
        let symbol = UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold, scale: .large)
        let chevron = makeIcon(UIImage(systemName: isRTL ? "chevron.right" : "chevron.left", withConfiguration: symbol))
        let qr = makeIcon(UIImage.airBundle("QRIcon").withRenderingMode(.alwaysTemplate))
        let more = makeIcon(UIImage(systemName: "ellipsis", withConfiguration: symbol))
        let icons = [chevron, qr, more]
        tabsGlass.contentView.addSubview(chevron)
        accountGlass.contentView.addSubview(qr)
        accountGlass.contentView.addSubview(more)
        let layoutContent: (CGRect, CGRect) -> Void = { [source] tabsFrame, accountFrame in
            chevron.center = CGPoint(x: backFrame.midX - tabsFrame.minX, y: tabsFrame.height / 2)
            qr.center = CGPoint(x: (isRTL ? trailingFrame.minX + 77 : trailingFrame.maxX - 77) - accountFrame.minX,
                                y: accountFrame.height / 2)
            more.center = CGPoint(x: (isRTL ? trailingFrame.minX + 23 : trailingFrame.maxX - 23) - accountFrame.minX,
                                  y: accountFrame.height / 2)
            let remaining = isRTL ? source.segmentedFrame.maxX - tabsFrame.minX : tabsFrame.maxX - source.segmentedFrame.minX
            let fold = min(max(remaining / max(source.segmentedFrame.width, 1), 0.3), 1)
            labels.transform = CGAffineTransform(scaleX: fold, y: 1)
        }

        let largeAvatar = settings.morphAvatarView
        let avatarState = settings.morphAvatarState(
            navigationBarMidY: navView.convert(CGPoint(x: 0, y: barMidY), to: settings.view).y
        )
        let largeFrame = settings.view.convert(avatarState.frame, to: navView)
        let largeContent = IconView(size: largeFrame.width)
        largeContent.config(with: AccountStore.account)
        let smallContent = IconView(size: source.avatarFrame.width)
        smallContent.config(with: AccountStore.account)
        let flyer = WBlurredContentView()
        flyer.translatesAutoresizingMaskIntoConstraints = true
        flyer.bounds = CGRect(origin: .zero, size: largeFrame.size)
        flyer.addSubview(largeContent)
        flyer.addSubview(smallContent)
        NSLayoutConstraint.activate([
            largeContent.centerXAnchor.constraint(equalTo: flyer.centerXAnchor),
            largeContent.centerYAnchor.constraint(equalTo: flyer.centerYAnchor),
            smallContent.centerXAnchor.constraint(equalTo: flyer.centerXAnchor),
            smallContent.centerYAnchor.constraint(equalTo: flyer.centerYAnchor),
        ])
        flyer.layoutIfNeeded()
        let smallScale = source.avatarFrame.width / largeFrame.width
        smallContent.transform = CGAffineTransform(scaleX: 1 / smallScale, y: 1 / smallScale)
        overlay.addSubview(flyer)
        let wasAvatarHidden = largeAvatar.isHidden
        largeAvatar.isHidden = true

        let fromTransform = fromView.transform
        let toTransform = toView.transform
        let fromTabs = isPush ? source.segmentedFrame : backFrame
        let toTabs = isPush ? backFrame : source.segmentedFrame
        let fromAccount = isPush ? source.avatarGlassFrame : trailingFrame
        let toAccount = isPush ? trailingFrame : source.avatarGlassFrame
        let T = SettingsMorphTiming.self
        let direction: CGFloat = isRTL ? -1 : 1
        let screenWidth = container.bounds.width * direction
        cleanup = {
            overlay.removeFromSuperview()
            barContents.forEach { $0.view.layer.mask = $0.mask }
            largeAvatar.isHidden = wasAvatarHidden
            fromView.transform = fromTransform
            toView.transform = toTransform
        }
        var pendingPieces = 3
        let pieceDone = { [self] in
            pendingPieces -= 1
            guard pendingPieces == 0 else { return }
            finish()
            context.completeTransition(!context.transitionWasCancelled)
        }
        animateLiquid(tabsGlass, accountGlass,
                      from: (fromTabs, fromAccount), to: (toTabs, toAccount), spring: Self.glass,
                      lifts: isPush ? (0, source.pressLift - 1) : (source.pressLift - 1, 0),
                      isRTL: isRTL, width: width, layout: layoutContent, completion: pieceDone)

        setIcons(icons, visible: !isPush)
        labels.alpha = isPush ? 1 : 0
        fade(isPush ? T.labelsOut : T.labelsIn) { labels.alpha = self.isPush ? 0 : 1 }
        fade(isPush ? T.iconsIn : T.iconsOut) { self.setIcons(icons, visible: self.isPush) }
        animateBlur(labels, from: isPush ? 0 : T.blurRadius, to: isPush ? T.blurRadius : 0,
                    timing: isPush ? T.labelsOut : T.labelsIn)
        icons.forEach {
            animateBlur($0, from: isPush ? T.blurRadius : 0, to: isPush ? 0 : T.blurRadius,
                        timing: isPush ? T.iconsIn : T.iconsOut)
        }
        smallContent.alpha = isPush ? 1 : 0
        fade(isPush ? T.avatarSwap : T.avatarSwapBack) { smallContent.alpha = self.isPush ? 0 : 1 }

        let lift = source.pressLift
        if lift > 1.01 {
            let glow = min((lift - 1) / 0.3, 1)
            var glows: [UIView] = []
            if isPush {
                let avatarGlow = UIView(frame: flyer.bounds)
                avatarGlow.backgroundColor = .white
                avatarGlow.layer.cornerRadius = flyer.bounds.width / 2
                avatarGlow.alpha = T.pressGlow.avatar * glow
                flyer.addSubview(avatarGlow)
                glows.append(avatarGlow)
            }
            let pressedGlass = isPush ? accountGlass : tabsGlass
            let glassGlow = UIView(frame: pressedGlass.contentView.bounds)
            glassGlow.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            glassGlow.backgroundColor = .white
            glassGlow.alpha = T.pressGlow.glass * glow
            pressedGlass.contentView.insertSubview(glassGlow, at: 0)
            glows.append(glassGlow)
            fade((0, T.pressGlow.duration)) { glows.forEach { $0.alpha = 0 } }
        }

        animateSpring(Self.slide, { progress in
            toView.transform = toTransform.translatedBy(x: (self.isPush ? screenWidth : -screenWidth * T.parallax) * (1 - progress), y: 0)
            fromView.transform = fromTransform.translatedBy(x: (self.isPush ? -screenWidth * T.parallax : screenWidth) * progress, y: 0)
        }, completion: pieceDone)

        CATransaction.begin()
        CATransaction.setCompletionBlock(pieceDone)
        animateFlight(of: flyer,
                      from: isPush ? source.avatarFrame.center : largeFrame.center,
                      to: isPush ? largeFrame.center : source.avatarFrame.center,
                      fromScale: isPush ? smallScale * lift : 1, toScale: isPush ? 1 : smallScale,
                      settingsAlpha: avatarState.alpha, settingsBlur: avatarState.blurRadius)
        CATransaction.commit()
    }

    func animationEnded(_ transitionCompleted: Bool) {
        finish()
    }

    private func finish() {
        let cleanup = cleanup
        self.cleanup = nil
        cleanup?()
    }

    private func makeGlass() -> UIVisualEffectView {
        let glass = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
        glass.clipsToBounds = true
        glass.layer.cornerCurve = .continuous
        glass.isUserInteractionEnabled = false
        return glass
    }

    private func makeContent(_ content: UIView) -> WBlurredContentView {
        let view = WBlurredContentView()
        view.translatesAutoresizingMaskIntoConstraints = true
        view.bounds = CGRect(origin: .zero, size: content.bounds.size)
        content.removeFromSuperview()
        content.transform = .identity
        content.alpha = 1
        content.frame = view.bounds
        view.addSubview(content)
        return view
    }

    private func makeIcon(_ image: UIImage?) -> WBlurredContentView {
        let icon = UIImageView(image: image)
        icon.tintColor = .label
        icon.contentMode = .center
        icon.sizeToFit()
        icon.frame = icon.frame.insetBy(dx: -8, dy: -8)
        return makeContent(icon)
    }

    private static func setCapsule(_ view: UIView, _ frame: CGRect) {
        view.frame = frame
        view.layer.cornerRadius = frame.height / 2
    }

    private func animateBlur(_ view: WBlurredContentView, from: CGFloat, to: CGFloat,
                             timing: (delay: Double, duration: Double)) {
        view.blurRadius = to
        let animation = CABasicAnimation(keyPath: "filters.gaussianBlur.inputRadius")
        animation.fromValue = from
        animation.toValue = to
        animation.beginTime = view.layer.convertTime(CACurrentMediaTime(), from: nil) + timing.delay
        animation.duration = timing.duration
        animation.fillMode = .backwards
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        view.layer.add(animation, forKey: "settingsMorphBlur")
    }

    private func setIcons(_ icons: [UIView], visible: Bool) {
        for icon in icons {
            icon.alpha = visible ? 1 : 0
            let s = visible ? 1 : SettingsMorphTiming.iconsStartScale
            icon.transform = CGAffineTransform(scaleX: s, y: s)
        }
    }

    private func animateSpring(_ spring: MorphSpring, _ apply: @escaping (CGFloat) -> Void,
                               completion: @escaping () -> Void) {
        let duration = spring.settlingDuration
        let n = SettingsMorphTiming.keyframeCount
        let times = (0...n).map { Double($0) / Double(n) }
        apply(0)
        UIView.animateKeyframes(withDuration: duration, delay: 0, options: [.calculationModeLinear]) {
            for index in 1...n {
                let p = CGFloat(spring.value(at: times[index] * duration))
                UIView.addKeyframe(withRelativeStartTime: times[index - 1], relativeDuration: times[index] - times[index - 1]) {
                    apply(index == n ? 1 : p)
                }
            }
        } completion: { _ in completion() }
    }

    private func animateLiquid(_ left: UIView, _ right: UIView,
                               from: (left: CGRect, right: CGRect), to: (left: CGRect, right: CGRect),
                               spring: MorphSpring, lifts: (left: CGFloat, right: CGFloat),
                               isRTL: Bool, width: CGFloat,
                               layout: @escaping (CGRect, CGRect) -> Void,
                               completion: @escaping () -> Void) {
        func mirror(_ frame: CGRect) -> CGRect {
            isRTL ? CGRect(x: width - frame.maxX, y: frame.minY, width: frame.width, height: frame.height) : frame
        }
        let from = (left: mirror(from.left), right: mirror(from.right))
        let to = (left: mirror(to.left), right: mirror(to.right))
        let leftSwell = Self.swellCurve(of: spring, from: lifts.left)
        let rightSwell = Self.swellCurve(of: spring, from: lifts.right)
        let duration = max(leftSwell.duration, rightSwell.duration)
        let start = (Self.swollen(from.left, leftSwell.value(0)), Self.swollen(from.right, rightSwell.value(0)))
        // A lifted glass may start closer than the minimum gap (UIKit lets it touch its neighbour):
        // the gap opens up over the first moments instead of jumping open.
        let startGap = start.1.minX - start.0.maxX
        func requiredGap(_ t: Double) -> CGFloat {
            let minGap = SettingsMorphTiming.glassMinGap
            guard startGap < minGap else { return minGap }
            let ramp = CGFloat(min(t / 0.12, 1))
            return startGap + (minGap - startGap) * ramp * ramp * (3 - 2 * ramp)
        }
        let n = SettingsMorphTiming.keyframeCount
        let times = (0...n).map { Double($0) / Double(n) }
        func frames(at i: Int) -> (CGRect, CGRect) {
            let t = times[i] * duration
            let p = CGFloat(spring.value(at: min(t, spring.settlingDuration)))
            var l = Self.swollen(Self.capsule(from: from.left, to: to.left, p), leftSwell.value(t))
            var r = Self.swollen(Self.capsule(from: from.right, to: to.right, p), rightSwell.value(t))
            // Keep the gap open: the shrinking left capsule yields first, then the right one.
            var missing = requiredGap(t) - (r.minX - l.maxX)
            if missing > 0 {
                let fromLeft = min(missing, max(l.width - l.height, 0))
                l.size.width -= fromLeft
                missing -= fromLeft
                r.origin.x += missing
                r.size.width = max(r.width - missing, r.height)
            }
            return i == n ? (to.left, to.right) : (l, r)
        }
        Self.setCapsule(left, mirror(start.0))
        Self.setCapsule(right, mirror(start.1))
        layout(mirror(start.0), mirror(start.1))
        UIView.animateKeyframes(withDuration: duration, delay: 0, options: [.calculationModeLinear]) {
            for i in 1...n {
                let f = frames(at: i)
                UIView.addKeyframe(withRelativeStartTime: times[i - 1], relativeDuration: times[i] - times[i - 1]) {
                    Self.setCapsule(left, mirror(f.0))
                    Self.setCapsule(right, mirror(f.1))
                    layout(mirror(f.0), mirror(f.1))
                }
            }
        } completion: { _ in completion() }
    }

    private static func swollen(_ frame: CGRect, _ grow: CGFloat) -> CGRect {
        let d = frame.height * grow / 2
        return frame.insetBy(dx: -d, dy: -d)
    }

    private static func swellCurve(of spring: MorphSpring, from initial: CGFloat) -> (value: (Double) -> CGFloat, duration: Double) {
        let T = SettingsMorphTiming.self
        let dt = 1.0 / 600
        let steps = Int(2.0 / dt)
        let speed = (0...steps).map { i -> Double in
            let t = Double(i) * dt
            return abs(spring.value(at: t + dt) - spring.value(at: max(t - dt, 0))) / (2 * dt)
        }
        let topSpeed = max(speed.max() ?? 1, 0.001)
        let omega = 2 * .pi / T.swellResponse
        let drive = Double(T.glassSwell)
        var x = Double(initial), v = 0.0
        var samples = [x]
        var lastActive = 0
        for i in 1...steps {
            v += (omega * omega * (drive * speed[i] / topSpeed - x) - 2 * T.swellDamping * omega * v) * dt
            x += v * dt
            samples.append(x)
            if abs(x) > 0.002 { lastActive = i }
        }
        let duration = max(spring.settlingDuration, Double(lastActive + 1) * dt)
        // Fades to exactly zero at the end, so the hand-over to the real bar cannot pop.
        let value: (Double) -> CGFloat = { t in
            let i = min(max(Int(t / dt), 0), steps)
            let tail = min(max((duration - t) / 0.06, 0), 1)
            return CGFloat(samples[i] * tail)
        }
        return (value, duration)
    }

    private static func capsule(from start: CGRect, to end: CGRect, _ p: CGFloat) -> CGRect {
        func lerp(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * p }
        let height = lerp(start.height, end.height)
        var minX = lerp(start.minX, end.minX), maxX = lerp(start.maxX, end.maxX)
        if maxX - minX < height {
            if abs(start.minX - end.minX) < 0.5 { maxX = minX + height }
            else if abs(start.maxX - end.maxX) < 0.5 { minX = maxX - height }
            else { let mid = (minX + maxX) / 2; minX = mid - height / 2; maxX = mid + height / 2 }
        }
        return CGRect(x: minX, y: lerp(start.midY, end.midY) - height / 2, width: maxX - minX, height: height)
    }

    private func fade(_ timing: (delay: Double, duration: Double), _ animations: @escaping () -> Void) {
        UIView.animate(
            withDuration: timing.duration,
            delay: timing.delay,
            options: [.curveEaseOut, .beginFromCurrentState],
            animations: animations
        )
    }

    private func animateFlight(of view: WBlurredContentView, from start: CGPoint, to end: CGPoint,
                               fromScale: CGFloat, toScale: CGFloat, settingsAlpha: CGFloat, settingsBlur: CGFloat) {
        let T = SettingsMorphTiming.self
        let across = Self.slide
        let vertical = vertical
        let scale = scale
        let duration = [across, vertical, scale].map(\.settlingDuration).max() ?? across.settlingDuration

        let n = T.keyframeCount
        let times = (0...n).map { Double($0) / Double(n) }
        func at(_ s: MorphSpring, _ t: Double) -> CGFloat { CGFloat(s.value(at: t * duration)) }
        var positions: [Any] = times.map { t in
            NSValue(cgPoint: CGPoint(
                x: start.x + (end.x - start.x) * at(across, t),
                y: start.y + (end.y - start.y) * at(vertical, t)))
        }
        var scales: [Any] = times.map { t in
            NSNumber(value: Double(fromScale + (toScale - fromScale) * at(scale, t)))
        }
        var appearance: [CGFloat] = times.map { t in
            let progress = min(1, max(0, at(scale, t)))
            return isPush ? progress : 1 - progress
        }
        appearance[n] = isPush ? 1 : 0
        let opacity: [Any] = appearance.map { NSNumber(value: Double(1 + (settingsAlpha - 1) * $0)) }
        let blur: [Any] = appearance.map { NSNumber(value: Double(settingsBlur * $0)) }
        view.alpha = isPush ? settingsAlpha : 1
        view.blurRadius = isPush ? settingsBlur : 0
        // Exact end values, so nothing shifts when the real avatar takes over.
        positions[n] = NSValue(cgPoint: end)
        scales[n] = NSNumber(value: Double(toScale))
        view.center = end
        view.transform = CGAffineTransform(scaleX: toScale, y: toScale)
        let keyTimes = times.map { NSNumber(value: $0) }
        for (keyPath, values) in [("position", positions), ("transform.scale", scales), ("opacity", opacity), ("filters.gaussianBlur.inputRadius", blur)] {
            let animation = CAKeyframeAnimation(keyPath: keyPath)
            animation.values = values
            animation.keyTimes = keyTimes
            animation.calculationMode = .linear
            animation.duration = duration
            view.layer.add(animation, forKey: keyPath)
        }
    }
}

private struct MorphSpring {
    let response: Double
    let damping: Double
    /// Initial speed as a share of the natural frequency: 0 = starts at rest (slow ramp),
    /// 1 = starts at full speed (critically damped → pure exponential ease-out).
    var launch: Double = 0

    init(response: Double, damping: Double, launch: Double = 0) {
        self.response = response
        self.damping = damping
        self.launch = launch
    }

    init(_ parameters: (response: Double, damping: Double, launch: Double)) {
        self.init(response: parameters.response, damping: parameters.damping, launch: parameters.launch)
    }

    func value(at time: Double) -> Double {
        Double(GlassSpring(dampingRatio: damping, response: response).advance(
            value: 0, velocity: launch * 2 * .pi / response, target: 1, time: time
        ).value)
    }

    /// Time until the spring stays within 0.1% of its target (under half a point on a phone
    /// screen, so nothing visibly snaps when the animation hands over).
    var settlingDuration: Double {
        var t = response * 4
        while t > response * 0.5, abs(1 - value(at: t - 0.01)) < 0.001 {
            t -= 0.01
        }
        return t
    }
}

private enum InteractiveGlassLift {
    static func scale(heldFor held: TimeInterval) -> CGFloat {
        1 + 0.36 * CGFloat(1 - exp(-max(held, 0) / 0.05))
    }
}

final class SettingsMorphPressRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
    private var downTime: CFTimeInterval = 0
    private var downLocation: CGPoint = .zero
    private var upTime: CFTimeInterval = 0

    init() {
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
    }

    func recentLift(in area: CGRect) -> CGFloat {
        guard CACurrentMediaTime() - upTime < 0.4, upTime >= downTime, area.contains(downLocation) else { return 1 }
        return InteractiveGlassLift.scale(heldFor: upTime - downTime)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        downTime = CACurrentMediaTime()
        downLocation = touches.first?.location(in: view) ?? .zero
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        upTime = CACurrentMediaTime()
        state = .failed
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        upTime = CACurrentMediaTime()
        state = .failed
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}
