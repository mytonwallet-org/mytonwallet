import CoreMotion
import UIKit

@MainActor
public final class CardSurfaceMotionDriver {
    public enum Input: Int {
        case device, drag, sweep
    }
    public enum SweepAxis { case pitch, roll }
    public enum LinearTouchMode { case sweep, directional, circular }

    private let motion = CMMotionManager()
    private let onLight: (CardSurfaceLight) -> Void
    private weak var cardView: UIView?
    private var pressMotion = CardPressMotion()
    private var previewReleaseAfter: TimeInterval?
    private var minimumPressTimeRemaining: TimeInterval = 0
    private var renderedTransform = CATransform3DIdentity
    private var displayLink: CADisplayLink?
    private var deviceTilt = CardDeviceTilt()
    private var linearShine = CardLinearShineMotion()
    private var touchSpot = CardTouchSpotMotion()
    private var target = CGPoint.zero
    private var current = CGPoint.zero
    private var rendered = CardSurfaceLight()
    private var lightActivity = CardLightActivity()
    private var previousTime: CFTimeInterval = 0
    private var sweepTime: CFTimeInterval = 0
    private var isActive = false
    private var isSuspended = false

    public var input: Input = .device {
        didSet {
            guard input != oldValue else { return }
            stop()
            recenter()
            startIfNeeded()
        }
    }
    public var framesPerSecond = 60 {
        didSet {
            guard framesPerSecond != oldValue else { return }
            motion.deviceMotionUpdateInterval = 1 / Double(framesPerSecond)
            displayLink?.preferredFrameRateRange = frameRateRange
        }
    }
    public var shineEnabled = true {
        didSet {
            guard shineEnabled != oldValue else { return }
            stop()
            lightActivity.reset()
            linearShine.reset()
            touchSpot.reset()
            renderFrame(force: true)
            startIfNeeded()
        }
    }
    public var touchResponseEnabled = true {
        didSet {
            guard touchResponseEnabled != oldValue else { return }
            pressMotion.reset()
            linearShine.endDirectionalPress(cancelled: true)
            touchSpot.reset()
            previewReleaseAfter = nil
            minimumPressTimeRemaining = 0
            renderFrame(force: true)
            startIfNeeded()
        }
    }
    public var pressDepth: Double = 0.7 {
        didSet {
            pressMotion.depth = pressDepth
            renderFrame(force: true)
        }
    }
    public var sensitivity: CGFloat = 1.5
    public var linearTouchMode: LinearTouchMode = .sweep {
        didSet {
            guard linearTouchMode != oldValue else { return }
            linearShine.reset()
            touchSpot.reset()
            renderFrame(force: true)
        }
    }
    public var linearTouchAngle: CGFloat = 61
    public var linearPitchSensitivity: CGFloat = 0.89 {
        didSet { if linearPitchSensitivity != oldValue { linearShine.recenterInput() } }
    }
    public var linearRollSensitivity: CGFloat = 0.68 {
        didSet { if linearRollSensitivity != oldValue { linearShine.recenterInput() } }
    }
    public var linearTriggerAngle: CGFloat = 25 {
        didSet { if linearTriggerAngle != oldValue { linearShine.recenterInput() } }
    }
    public var linearReturnAngle: CGFloat = 25 {
        didSet { if linearReturnAngle != oldValue { linearShine.recenterInput() } }
    }
    public var sweepAxis: SweepAxis = .pitch {
        didSet { if sweepAxis != oldValue { recenter() } }
    }
    public var sweepSpeed: Double = 1 {
        didSet { if sweepSpeed != oldValue { recenter() } }
    }
    public var responseTime: TimeInterval = 0.22
    public var shineStyle: CardSurfaceConfiguration.Shine? {
        didSet {
            guard shineStyle != oldValue else { return }
            linearShine.reset()
            touchSpot.reset()
            renderFrame(force: true)
        }
    }
    public var isMotionAvailable: Bool { motion.isDeviceMotionAvailable }

    public init(cardView: UIView, onLight: @escaping (CardSurfaceLight) -> Void) {
        self.onLight = onLight
        self.cardView = cardView
    }

    isolated deinit {
        displayLink?.invalidate()
        motion.stopDeviceMotionUpdates()
    }

    public func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        if active {
            startIfNeeded()
        } else {
            stop()
            target = .zero
            current = .zero
            lightActivity.reset()
            linearShine.reset()
            touchSpot.reset()
            pressMotion.reset()
            previewReleaseAfter = nil
            minimumPressTimeRemaining = 0
            renderFrame(force: true)
        }
    }

    public func recenter() {
        deviceTilt.reset()
        target = .zero
        current = .zero
        rendered = CardSurfaceLight()
        lightActivity.reset()
        linearShine.reset()
        touchSpot.reset()
        sweepTime = 0
        pressMotion.reset()
        previewReleaseAfter = nil
        minimumPressTimeRemaining = 0
        renderFrame(force: true)
        startIfNeeded()
    }

    func setSuspended(_ suspended: Bool) {
        guard suspended != isSuspended else { return }
        isSuspended = suspended
        if suspended {
            stop()
            previewReleaseAfter = nil
            minimumPressTimeRemaining = 0
            pressMotion.release()
            linearShine.endDirectionalPress(cancelled: true)
            touchSpot.release()
        } else {
            startIfNeeded()
        }
    }

    public func press(at point: CGPoint, began: Bool = false) {
        guard isActive, !isSuspended, touchResponseEnabled else { return }
        previewReleaseAfter = nil
        // Keep very short taps visible, even if down and up arrive in one frame.
        if began { minimumPressTimeRemaining = 0.07 }
        let newPress = began || !pressMotion.isEngaged
        pressMotion.press(at: point)
        if shineEnabled, shineStyle == .linear {
            if linearTouchMode == .circular {
                if newPress { linearShine.reset() }
                touchSpot.press(at: point)
            } else if linearTouchMode == .directional {
                if newPress { linearShine.beginDirectionalPress(at: point, angle: linearTouchAngle) }
                else { linearShine.moveDirectionalPress(to: point) }
            } else if newPress {
                linearShine.press()
            }
        }
        if newPress { renderFrame(force: true) }
        startIfNeeded()
    }

    public func releasePress(cancelled: Bool = false) {
        linearShine.endDirectionalPress(cancelled: cancelled)
        if minimumPressTimeRemaining > 0 {
            previewReleaseAfter = minimumPressTimeRemaining
        } else {
            previewReleaseAfter = nil
            pressMotion.release()
            touchSpot.release()
        }
        startIfNeeded()
    }

    public func previewPress() -> Bool {
        guard isActive, !isSuspended, touchResponseEnabled else { return false }
        press(at: CGPoint(x: 0.65, y: 0.65), began: true)
        previewReleaseAfter = 0.16
        return true
    }

    private var needsContinuousInput: Bool {
        shineEnabled && (input == .sweep || (input == .device && isMotionAvailable))
    }

    private var isLightSettled: Bool {
        abs(current.x - target.x) < 0.0005 && abs(current.y - target.y) < 0.0005
    }

    private var frameRateRange: CAFrameRateRange {
        CAFrameRateRange(minimum: Float(framesPerSecond), maximum: Float(framesPerSecond), preferred: Float(framesPerSecond))
    }

    private func startIfNeeded() {
        guard isActive, !isSuspended, displayLink == nil,
              needsContinuousInput || previewReleaseAfter != nil || !pressMotion.isSettled
                || (shineEnabled && (!isLightSettled || !lightActivity.isSettled || linearShine.isAnimating || !touchSpot.isSettled)) else { return }
        if input == .device, shineEnabled, isMotionAvailable {
            deviceTilt.reset()
            motion.deviceMotionUpdateInterval = 1 / Double(framesPerSecond)
            // Poll the latest fused accelerometer/gyro sample. No callback backlog on the main queue.
            motion.startDeviceMotionUpdates(using: .xArbitraryZVertical)
        }
        previousTime = 0
        let link = CADisplayLink(target: DisplayLinkTarget(driver: self), selector: #selector(DisplayLinkTarget.tick(_:)))
        link.preferredFrameRateRange = frameRateRange
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stop() {
        displayLink?.invalidate()
        displayLink = nil
        motion.stopDeviceMotionUpdates()
        deviceTilt.reset()
        previousTime = 0
    }

    fileprivate func tick(_ link: CADisplayLink) {
        let dt = previousTime == 0 ? 1 / Double(framesPerSecond) : min(link.timestamp - previousTime, 0.1)
        previousTime = link.timestamp
        minimumPressTimeRemaining = max(0, minimumPressTimeRemaining - dt)
        if let remaining = previewReleaseAfter {
            if remaining <= dt {
                previewReleaseAfter = nil
                pressMotion.release()
                linearShine.endDirectionalPress()
                touchSpot.release()
            } else {
                previewReleaseAfter = remaining - dt
            }
        }
        touchSpot.advance(by: dt)
        var angularSpeed = 0.0
        var pitch = deviceTilt.pitch
        var roll = deviceTilt.roll
        if shineEnabled {
            switch input {
            case .device:
                angularSpeed = updateDeviceTarget(by: dt)
                pitch = deviceTilt.pitch
                roll = deviceTilt.roll
                if deviceTilt.didRecenter {
                    linearShine.rebase(to: pitch, roll: roll)
                }
            case .drag:
                break
            case .sweep:
                if !pressMotion.isEngaged { sweepTime += dt }
                let phase = sweepTime * .pi / 3 * sweepSpeed
                let sweepAngle = sin(phase * 0.5) * 30 * .pi / 180
                pitch = sweepAxis == .pitch ? sweepAngle : 0
                roll = sweepAxis == .roll ? sweepAngle : 0
                let next = CGPoint(x: sin(phase) * 0.9, y: sin(phase * 0.5) * 0.55)
                angularSpeed = hypot(next.x - target.x, next.y - target.y) / dt / sensitivity
                target = next
            }
            let amount = CGFloat(1 - exp(-dt / responseTime))
            current.x += (target.x - current.x) * amount
            current.y += (target.y - current.y) * amount
            if isLightSettled { current = target }
            if shineStyle == .linear, linearTouchMode == .circular, touchSpot.isFollowing || !touchSpot.isSettled {
                linearShine.rebase(to: pitch, roll: roll)
            } else if shineStyle == .linear {
                linearShine.advance(pitch: pitch, roll: roll,
                                    pitchSensitivity: linearPitchSensitivity, rollSensitivity: linearRollSensitivity,
                                    triggerAngle: linearTriggerAngle, returnAngle: linearReturnAngle,
                                    angularSpeed: input == .device
                                        ? hypot(deviceTilt.pitchAngularSpeed * Double(linearPitchSensitivity),
                                                deviceTilt.rollAngularSpeed * Double(linearRollSensitivity)) : nil,
                                    suppressTilt: linearTouchMode == .directional && pressMotion.isEngaged,
                                    by: dt)
            }
        }
        pressMotion.advance(by: dt)
        lightActivity.advance(angularSpeed: angularSpeed, touch: shineEnabled ? pressMotion.value.z : 0, by: dt)
        renderFrame()
        if !needsContinuousInput, previewReleaseAfter == nil, pressMotion.isSettled,
           !shineEnabled || (isLightSettled && lightActivity.isSettled && !linearShine.isAnimating && touchSpot.isSettled) {
            renderFrame(force: true)
            stop()
        }
    }

    private func renderFrame(force: Bool = false) {
        let transform = pressMotion.transform(cardWidth: cardView?.bounds.width ?? 370)
        if force || !CATransform3DEqualToTransform(transform, renderedTransform) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            cardView?.layer.transform = transform
            CATransaction.commit()
            renderedTransform = transform
        }
        let pressTilt = pressMotion.lightTilt
        let tilt = CGPoint(x: clamp(current.x + pressTilt.x), y: clamp(current.y + pressTilt.y))
        let linearPosition = shineStyle == .linear ? linearShine.position : nil
        let activity = shineStyle == .linear && linearShine.isAnimating ? 1 : lightActivity.value
        let light = CardSurfaceLight(tilt: tilt, activity: activity, press: pressMotion.value.z,
                                     linearPosition: linearPosition, linearAngle: linearShine.linearAngle,
                                     touchSpot: linearTouchMode == .circular && (touchSpot.isFollowing || !touchSpot.isSettled)
                                        ? touchSpot.light : nil)
        if force || abs(tilt.x - rendered.tilt.x) > 0.00015 || abs(tilt.y - rendered.tilt.y) > 0.00015
            || abs(light.activity - rendered.activity) > 0.0005 || abs(light.press - rendered.press) > 0.0005
            || light.linearPosition != rendered.linearPosition || light.linearAngle != rendered.linearAngle || light.touchSpot != rendered.touchSpot {
            onLight(light)
            rendered = light
        }
    }

    private func updateDeviceTarget(by dt: TimeInterval) -> Double {
        guard let sample = motion.deviceMotion else { return 0 }
        let response = deviceTilt.update(attitude: sample.attitude.quaternion, rotationRate: sample.rotationRate,
            orientation: cardView?.window?.windowScene?.interfaceOrientation ?? .portrait,
            touchActive: pressMotion.isEngaged || previewReleaseAfter != nil,
            lightIsSettled: lightActivity.isSettled, sensitivity: sensitivity, by: dt)
        target = response.tilt
        return response.angularSpeed
    }

    private func clamp(_ value: CGFloat) -> CGFloat {
        min(1, max(-1, value))
    }
}

@MainActor
private final class DisplayLinkTarget: NSObject {
    weak var driver: CardSurfaceMotionDriver?

    init(driver: CardSurfaceMotionDriver) {
        self.driver = driver
    }

    @objc func tick(_ link: CADisplayLink) {
        driver?.tick(link)
    }
}
