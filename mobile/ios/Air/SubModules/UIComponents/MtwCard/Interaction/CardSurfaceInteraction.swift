import Combine
import UIKit

/// Coordinates touch and device motion without taking over the card's buttons or scrolling.
@MainActor
public final class CardSurfaceInteraction {
    private weak var container: UIView?
    private let driver: CardSurfaceMotionDriver
    private let touch = CardTouchObserver()
    private var requested = false
    private var observation: AnyCancellable?
    private var suspensionObservation: AnyCancellable?

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
        driver.pressDepth = 0.525 // 4.2 degrees at the edge, less at a corner.
        driver.framesPerSecond = 60
        driver.shineStyle = CardSurfaceConfiguration.current.shine
        driver.linearTouchMode = CardSurfaceConfiguration.current.shine == .linear ? .directional : .sweep
        container.addGestureRecognizer(touch)
        touch.onPress = { [weak self] point, began in self?.driver.press(at: point, began: began) }
        touch.onRelease = { [weak self] cancelled in self?.driver.releasePress(cancelled: cancelled) }
        observation = CardBackgroundAnimationEnvironment.shared.objectWillChange
            .receive(on: RunLoop.main).sink { [weak self] in self?.updateVisibility() }
        suspensionObservation = CardBackgroundAnimationEnvironment.shared.willSuspend.sink { [weak self] in
            self?.driver.setSuspended(true)
            self?.touch.isEnabled = false
        }
        updateVisibility()
    }

    public func setActive(_ active: Bool) {
        requested = active
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
        driver.setSuspended(!environment.applicationActive)
        touch.isEnabled = allowed && environment.applicationActive
        driver.setActive(allowed)
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
