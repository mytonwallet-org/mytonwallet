import UIKit

@MainActor
enum ContextMenuPressAnimationUpdate {
    case begin
    case update
    case ended(CGFloat)
}

@MainActor
final class ContextMenuPressAnimationGestureRecognizer: UIGestureRecognizer {
    var activationDuration: TimeInterval = 0.32
    var beginDelay: TimeInterval = 0.12
    var pressInDuration: TimeInterval = 0.2
    var allowableMovement: CGFloat = 10.0
    var activationProgress: ((CGFloat, ContextMenuPressAnimationUpdate) -> Void)?

    private var activationTimer: Timer?
    private var delayTimer: Timer?
    private var displayLink: CADisplayLink?
    private var displayLinkStartTime: CFTimeInterval = 0.0
    private var initialLocation: CGPoint?
    private var currentProgress: CGFloat = 0.0
    private var isPressing = false
    private var hasActivated = false

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)

        self.cancelsTouchesInView = true
    }

    override func reset() {
        super.reset()

        self.endPressAppearance()
        self.initialLocation = nil
        self.isPressing = false
        self.hasActivated = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)

        guard touches.count == 1, let touch = touches.first, let view else {
            self.state = .failed
            return
        }

        self.initialLocation = touch.location(in: view)
        self.startActivationTimer()
        self.startDelayTimer()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)

        guard let touch = touches.first, let view, let initialLocation else {
            return
        }

        let location = touch.location(in: view)
        if !self.hasActivated && hypot(location.x - initialLocation.x, location.y - initialLocation.y) > self.allowableMovement {
            self.endPressAppearance()
            self.state = .failed
        } else if self.hasActivated {
            self.state = .changed
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)

        self.endPressAppearance()
        self.state = self.hasActivated ? .ended : .failed
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)

        self.endPressAppearance()
        self.state = self.hasActivated ? .cancelled : .failed
    }

    func cancelPressAnimation() {
        self.endPressAppearance()
        switch self.state {
        case .began, .changed:
            self.state = .cancelled
        case .possible:
            self.state = .failed
        default:
            break
        }
    }

    func finishPressAnimation() {
        self.endPressAppearance()
    }

    private func startDelayTimer() {
        self.delayTimer?.invalidate()

        let delayTimer = Timer(timeInterval: self.beginDelay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.beginPressAnimation()
            }
        }
        self.delayTimer = delayTimer
        RunLoop.main.add(delayTimer, forMode: .common)
    }

    private func startActivationTimer() {
        self.activationTimer?.invalidate()

        guard self.activationDuration > 0 else {
            self.activate()
            return
        }

        let activationTimer = Timer(timeInterval: self.activationDuration, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.activate()
            }
        }
        self.activationTimer = activationTimer
        RunLoop.main.add(activationTimer, forMode: .common)
    }

    private func beginPressAnimation() {
        guard self.state == .possible || self.hasActivated else {
            return
        }

        self.isPressing = true
        self.activationProgress?(self.currentProgress, .begin)
        self.startDisplayLink()
    }

    private func startDisplayLink() {
        self.displayLink?.invalidate()
        self.displayLinkStartTime = CACurrentMediaTime()

        let displayLink = CADisplayLink(target: self, selector: #selector(self.handleDisplayLink(_:)))
        displayLink.add(to: .main, forMode: .common)
        self.displayLink = displayLink
    }

    @objc private func handleDisplayLink(_ displayLink: CADisplayLink) {
        guard self.isPressing else {
            displayLink.invalidate()
            return
        }

        let duration = max(self.pressInDuration, .ulpOfOne)
        let elapsed = CACurrentMediaTime() - self.displayLinkStartTime
        let progress = min(max(CGFloat(elapsed / duration), 0.0), 1.0)
        self.currentProgress = progress
        self.activationProgress?(progress, .update)

        if progress >= 1.0 {
            displayLink.invalidate()
            if self.displayLink === displayLink {
                self.displayLink = nil
            }
            if self.hasActivated {
                self.endPressAppearance()
            }
        }
    }

    private func activate() {
        guard self.state == .possible else {
            return
        }

        self.hasActivated = true
        self.state = .began

        if self.isPressing && self.currentProgress >= 1.0 {
            self.endPressAppearance()
        }
    }

    private func endPressAppearance() {
        self.activationTimer?.invalidate()
        self.activationTimer = nil

        self.delayTimer?.invalidate()
        self.delayTimer = nil

        self.displayLink?.invalidate()
        self.displayLink = nil

        if self.isPressing || !self.currentProgress.isZero {
            let previousProgress = self.currentProgress
            self.currentProgress = 0.0
            self.isPressing = false
            self.activationProgress?(0.0, .ended(previousProgress))
        }
    }
}

@MainActor
enum ContextMenuPressAnimationApplier {
    static func apply(
        _ animation: ContextMenuPressAnimation,
        to view: UIView,
        progress: CGFloat,
        update: ContextMenuPressAnimationUpdate
    ) {
        let layer = view.layer
        let contentRect = CGRect(origin: .zero, size: layer.bounds.size)
        let transform = self.transform(for: layer, contentRect: contentRect, progress: progress, animation: animation)

        switch update {
        case .begin, .update:
            self.removeReleaseAnimation(from: layer, mode: animation.transformMode)
            self.setTransform(transform, on: layer, mode: animation.transformMode)
        case .ended:
            let previousTransform = self.currentTransform(on: layer, mode: animation.transformMode)
            self.setTransform(transform, on: layer, mode: animation.transformMode)
            self.animateRelease(
                from: previousTransform,
                to: transform,
                on: layer,
                mode: animation.transformMode,
                duration: animation.releaseDuration
            )
        }
    }

    private static func transform(
        for layer: CALayer,
        contentRect: CGRect,
        progress: CGFloat,
        animation: ContextMenuPressAnimation
    ) -> CATransform3D {
        guard contentRect.width > 0.0 else {
            return CATransform3DIdentity
        }

        let minScale = max(animation.minimumScale, (contentRect.width - animation.scaleInset) / contentRect.width)
        let currentScale = 1.0 * (1.0 - progress) + minScale * progress

        let originalCenterOffsetX = layer.bounds.width / 2.0 - contentRect.midX
        let scaledCenterOffsetX = originalCenterOffsetX * currentScale
        let originalCenterOffsetY = layer.bounds.height / 2.0 - contentRect.midY
        let scaledCenterOffsetY = originalCenterOffsetY * currentScale

        let scaleMidX = scaledCenterOffsetX - originalCenterOffsetX
        let scaleMidY = scaledCenterOffsetY - originalCenterOffsetY

        return CATransform3DTranslate(
            CATransform3DScale(CATransform3DIdentity, currentScale, currentScale, 1.0),
            scaleMidX,
            scaleMidY,
            0.0
        )
    }

    private static func currentTransform(on layer: CALayer, mode: ContextMenuPressAnimation.TransformMode) -> CATransform3D {
        switch mode {
        case .sublayerTransform:
            layer.sublayerTransform
        case .transform:
            layer.transform
        }
    }

    private static func setTransform(
        _ transform: CATransform3D,
        on layer: CALayer,
        mode: ContextMenuPressAnimation.TransformMode
    ) {
        switch mode {
        case .sublayerTransform:
            layer.sublayerTransform = transform
        case .transform:
            layer.transform = transform
        }
    }

    private static func animateRelease(
        from previousTransform: CATransform3D,
        to transform: CATransform3D,
        on layer: CALayer,
        mode: ContextMenuPressAnimation.TransformMode,
        duration: TimeInterval
    ) {
        layer.addContextMenuBasicAnimation(
            keyPath: self.keyPath(for: mode),
            from: NSValue(caTransform3D: previousTransform),
            to: NSValue(caTransform3D: transform),
            duration: duration,
            timingFunction: .easeOut
        )
    }

    private static func removeReleaseAnimation(from layer: CALayer, mode: ContextMenuPressAnimation.TransformMode) {
        layer.removeAnimation(forKey: self.keyPath(for: mode) + ".contextMenuBasic")
    }

    private static func keyPath(for mode: ContextMenuPressAnimation.TransformMode) -> String {
        switch mode {
        case .sublayerTransform:
            "sublayerTransform"
        case .transform:
            "transform"
        }
    }
}
