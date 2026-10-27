import Combine
import UIKit

/// Coordinates touch and device motion without taking over the card's buttons or scrolling.
@MainActor
public final class CardSurfaceInteraction: NSObject, UIGestureRecognizerDelegate {
    private weak var container: UIView?
    private let driver: CardSurfaceMotionDriver
    private let touch = CardTouchObserver()
    private let hold = UILongPressGestureRecognizer()
    private let playFeedback = UIImpactFeedbackGenerator(style: .light)
    private let scrollLock = CardScrollLock()
    private var preset: CardMotionPreset?
    private var requested = false
    private var animatesActivation = false
    private var observation: AnyCancellable?
    private var suspensionObservation: AnyCancellable?
    /// Points are in the stationary container; nil releases the particle field.
    public var onPlayTouch: ((CGPoint?) -> Void)?
    private var lastTouchPoint: CGPoint?

    public var input: CardSurfaceMotionDriver.Input {
        get { driver.input }
        set { driver.input = newValue }
    }

    public var shineStyle: CardSurfaceConfiguration.Shine {
        get { driver.shineStyle ?? CardSurfaceConfiguration.current.shine }
        set { driver.shineStyle = newValue }
    }

    public var linearTouchMode: CardSurfaceMotionDriver.LinearTouchMode {
        get { driver.linearTouchMode }
        set { driver.linearTouchMode = newValue }
    }

    public var linearTouchAngle: CGFloat {
        get { driver.linearTouchAngle }
        set { driver.linearTouchAngle = newValue }
    }

    public var linearPitchSensitivity: CGFloat {
        get { driver.linearPitchSensitivity }
        set { driver.linearPitchSensitivity = newValue }
    }

    public var linearRollSensitivity: CGFloat {
        get { driver.linearRollSensitivity }
        set { driver.linearRollSensitivity = newValue }
    }

    public var linearTriggerAngle: CGFloat {
        get { driver.linearTriggerAngle }
        set { driver.linearTriggerAngle = newValue }
    }

    public var linearReturnAngle: CGFloat {
        get { driver.linearReturnAngle }
        set { driver.linearReturnAngle = newValue }
    }

    public var sweepAxis: CardSurfaceMotionDriver.SweepAxis {
        get { driver.sweepAxis }
        set { driver.sweepAxis = newValue }
    }

    public var sweepSpeed: Double {
        get { driver.sweepSpeed }
        set { driver.sweepSpeed = newValue }
    }

    public func recenter() { driver.recenter() }

    @discardableResult public func previewPress() -> Bool { driver.previewPress() }

    public init(container: UIView, surface: UIView, onLight: @escaping (CardSurfaceLight) -> Void) {
        self.container = container
        driver = CardSurfaceMotionDriver(cardView: surface, onLight: onLight)
        super.init()
        driver.pressDepth = 0.525 // 4.2 degrees at the edge, less at a corner.
        driver.framesPerSecond = 60
        driver.shineStyle = CardSurfaceConfiguration.current.shine
        driver.linearTouchMode = CardSurfaceConfiguration.current.shine == .linear ? .directional : .sweep
        container.addGestureRecognizer(touch)
        hold.name = "cardPlayHold"
        hold.allowableMovement = 12
        hold.cancelsTouchesInView = true
        hold.delegate = self
        hold.addTarget(self, action: #selector(holdChanged))
        container.addGestureRecognizer(hold)
        touch.onPress = { [weak self] point, began in
            guard let self, let container = self.container else { return }
            if began, preset?.holdToPlay == true { playFeedback.prepare() }
            driver.press(at: point, began: began)
            lastTouchPoint = CGPoint(x: (point.x + 1) * container.bounds.width / 2,
                                     y: (point.y + 1) * container.bounds.height / 2)
            if scrollLock.isLocked { onPlayTouch?(lastTouchPoint) }
        }
        touch.onRelease = { [weak self] cancelled in
            self?.driver.releasePress(cancelled: cancelled)
            self?.finishPlaying()
        }
        observation = CardBackgroundAnimationEnvironment.shared.objectWillChange
            .receive(on: RunLoop.main).sink { [weak self] in self?.updateVisibility() }
        suspensionObservation = CardBackgroundAnimationEnvironment.shared.willSuspend.sink { [weak self] in
            self?.finishPlaying()
            self?.hold.isEnabled = false
            self?.driver.setSuspended(true)
            self?.touch.isEnabled = false
        }
        updateVisibility()
    }

    public func configure(surface: CardSurfaceConfiguration) {
        guard preset != surface.motion else { return }
        finishPlaying()
        preset = surface.motion
        if let preset { preset.configure(driver, surface: surface) }
        hold.minimumPressDuration = preset?.holdDelay ?? 0.15
        driver.recenter()
        updateVisibility()
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard requested, preset?.holdToPlay == true, let container else { return false }
        var ancestor = container.superview
        while let view = ancestor {
            if let scroll = view as? UIScrollView, scroll.isDragging || scroll.isDecelerating { return false }
            ancestor = view.superview
        }
        return true
    }

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Preserve existing buttons and the balance's long-press currency menu.
        var view = touch.view
        while let current = view, current !== container {
            if current is UIControl || current.gestureRecognizers?.contains(where: { $0 is UILongPressGestureRecognizer && $0.isEnabled }) == true { return false }
            view = current.superview
        }
        return true
    }

    @objc private func holdChanged(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            guard let container else { return }
            lastTouchPoint = gesture.location(in: container)
            scrollLock.lock(above: container)
            driver.setPlayMode(true)
            onPlayTouch?(lastTouchPoint)
            playFeedback.impactOccurred(intensity: 1)
        case .changed:
            guard scrollLock.isLocked, let container else { return }
            lastTouchPoint = gesture.location(in: container)
            onPlayTouch?(lastTouchPoint)
        case .ended, .cancelled, .failed: finishPlaying()
        default: break
        }
    }

    private func finishPlaying() {
        lastTouchPoint = nil
        onPlayTouch?(nil)
        guard scrollLock.isLocked else { return }
        scrollLock.unlock()
        driver.setPlayMode(false)
    }

    public func setActive(_ active: Bool, animated: Bool = false) {
        requested = active
        animatesActivation = animated
        updateVisibility()
    }

    public func updateVisibility() {
        let environment = CardBackgroundAnimationEnvironment.shared
        let allowed = CardBackgroundMotionPolicy(requested: requested && environment.cardEffectsEnabled,
            animationsEnabled: environment.animationsEnabled, lowPowerMode: environment.lowPowerMode,
            reduceMotion: environment.reduceMotion, applicationActive: true,
            visible: container?.window != nil).canAnimate
        // Suspension preserves the visible pose and fade. Reuse/visibility/settings
        // still deactivate fully, so another card cannot inherit the interaction.
        if !allowed || !environment.applicationActive { finishPlaying() }
        hold.isEnabled = allowed && environment.applicationActive && preset?.holdToPlay == true
        driver.setSuspended(!environment.applicationActive)
        touch.isEnabled = allowed && environment.applicationActive
        driver.setActive(allowed, animated: animatesActivation && environment.applicationActive
            && environment.animationsEnabled && environment.cardEffectsEnabled
            && !environment.lowPowerMode && !environment.reduceMotion && container?.window != nil)
    }
}

/// Remains possible until the finger lifts, never delays or cancels another recognizer.
/// Locations are read in the stationary parent, avoiding feedback from the 3D transform.
final class CardTouchObserver: UIGestureRecognizer {
    var onPress: ((CGPoint, Bool) -> Void)?
    var onRelease: ((Bool) -> Void)?
    private weak var trackedTouch: UITouch?

    init() {
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard trackedTouch == nil, let touch = touches.first else { return }
        trackedTouch = touch
        update(touch, began: true)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let trackedTouch, touches.contains(trackedTouch) else { return }
        update(trackedTouch, began: false)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let trackedTouch, touches.contains(trackedTouch) else { return }
        update(trackedTouch, began: false)
        onRelease?(false)
        state = .failed
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        onRelease?(true)
        state = .failed
    }

    override func reset() {
        super.reset()
        trackedTouch = nil
    }

    private func update(_ touch: UITouch, began: Bool) {
        guard let view, view.bounds.width > 0, view.bounds.height > 0 else { return }
        let location = touch.location(in: view)
        onPress?(CGPoint(x: 2 * (location.x - view.bounds.midX) / view.bounds.width,
                         y: 2 * (location.y - view.bounds.midY) / view.bounds.height), began)
    }
}
