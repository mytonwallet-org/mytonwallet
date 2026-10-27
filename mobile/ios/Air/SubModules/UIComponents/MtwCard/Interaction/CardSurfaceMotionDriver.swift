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
    private var returningToRest = false
    private var renderedTransform = CATransform3DIdentity
    private var displayLink: CADisplayLink?
    private var deviceTilt = CardDeviceTilt()
    private var gramReflection = CardGramReflectionMotion()
    var gramReflectionMode: CardGramReflectionMode = .current {
        didSet { if oldValue != gramReflectionMode { renderFrame(force: true) } }
    }
    var gramV2MaxRotation: Double = 35 {
        didSet { if oldValue != gramV2MaxRotation { renderFrame(force: true) } }
    }
    var gramV2Sensitivity: Double = 1 {
        didSet { if oldValue != gramV2Sensitivity { renderFrame(force: true) } }
    }
    private var linearShine = CardLinearShineMotion()
    private var touchSpot = CardTouchSpotMotion()
    private var crystalPlay = CardCrystalPlayMotion()
    private var crystalGyro = CardCrystalGyroMotion()
    private var borderDeviceTilt = CardDeviceTilt()
    private var borderGyro = CardCrystalGyroMotion()
    private var borderMotion = CardBorderLightMotion()
    var borderShineEnabled = false {
        didSet {
            guard oldValue != borderShineEnabled else { return }
            stop()
            borderMotion.reset()
            renderFrame(force: true)
            startIfNeeded()
        }
    }
    private var pressPoint = CGPoint.zero
    private var isPressDown = false
    private var crystalOwnsRelease = false
    var continuousCrystalShineEnabled = false {
        didSet {
            guard oldValue != continuousCrystalShineEnabled else { return }
            crystalPlay.reset()
            crystalOwnsRelease = false
            deviceTilt.reset()
            gramReflection.reset()
            crystalGyro.reset()
            linearShine.reset()
            target = .zero; current = .zero
            renderFrame(force: true)
            startIfNeeded()
        }
    }
    private func resetCrystalPlay() {
        crystalPlay.reset()
        crystalOwnsRelease = false
        isPressDown = false
        borderMotion.release()
    }
    func setPlayMode(_ playing: Bool) {
        if playing {
            guard isActive, !isSuspended, isPressDown, touchResponseEnabled,
                  shineEnabled, shineStyle == .linear, continuousCrystalShineEnabled,
                  !crystalPlay.isHeld else { return }
            crystalOwnsRelease = true
            crystalPlay.begin(at: pressPoint, from: .init(
                position: rendered.linearPosition ?? linearShine.position,
                angle: rendered.linearAngle ?? linearTouchAngle, opacity: rendered.activity))
            // Transfer ownership, including queued gyro/return passes, to this one light.
            linearShine.reset()
            lightActivity.reset()
        } else {
            crystalPlay.release(to: continuousGyroPose)
        }
        renderFrame(force: true)
        startIfNeeded()
    }
    var touchSpotGradualAppearance = false {
        didSet {
            guard oldValue != touchSpotGradualAppearance else { return }
            touchSpot.gradualAppearance = touchSpotGradualAppearance
            resetTouchSpot()
        }
    }
    var touchSpotAppearanceDelay: TimeInterval = 0.35 {
        didSet { touchSpot.appearanceDelay = touchSpotAppearanceDelay }
    }
    var touchSpotAppearanceDuration: TimeInterval = 0.8 {
        didSet { touchSpot.appearanceDuration = touchSpotAppearanceDuration }
    }
    private func resetTouchSpot() {
        touchSpot.reset()
    }

    private var target = CGPoint.zero
    private var current = CGPoint.zero
    private var rendered = CardSurfaceLight()
    private var activationLight: CardSurfaceLight?
    private var activationElapsed: TimeInterval = 0
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
            resetCrystalPlay()
            resetTouchSpot()
            renderFrame(force: true)
            startIfNeeded()
        }
    }
    public var touchSpotEnabled = false {
        didSet {
            guard touchSpotEnabled != oldValue else { return }
            resetTouchSpot()
            renderFrame(force: true)
        }
    }
    public var touchResponseEnabled = true {
        didSet {
            guard touchResponseEnabled != oldValue else { return }
            pressMotion.reset()
            resetCrystalPlay()
            linearShine.endDirectionalPress(cancelled: true)
            resetTouchSpot()
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
    /// Demo tuning; the upstream response stays the default.
    public var releaseFrequency: Double = 14 {
        didSet { pressMotion.releaseFrequency = max(1, releaseFrequency) }
    }
    public var sensitivity: CGFloat = 1.5
    public var linearTouchMode: LinearTouchMode = .sweep {
        didSet {
            guard linearTouchMode != oldValue else { return }
            linearShine.reset()
            resetCrystalPlay()
            resetTouchSpot()
            renderFrame(force: true)
        }
    }
    public var improvedLinearBehavior = false {
        didSet {
            guard improvedLinearBehavior != oldValue else { return }
            linearShine.reset()
            resetCrystalPlay()
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
            resetCrystalPlay()
            resetTouchSpot()
            renderFrame(force: true)
        }
    }
    struct DeviceSample {
        var attitude: CMQuaternion
        var rotationRate: CMRotationRate
        var orientation: UIInterfaceOrientation
    }
    /// Shared comparison input and sensor replay use the same quaternion, filtering and rendering path as the phone.
    var deviceSampleProvider: (() -> DeviceSample?)?
    var externallyDriven = false { didSet { guard oldValue != externallyDriven else { return }; if externallyDriven { stop() } else { startIfNeeded() } } }
    public var isMotionAvailable: Bool {
        if deviceSampleProvider != nil { return true }
        return motion.isDeviceMotionAvailable
    }
    private var wantsContinuousGyro: Bool {
        continuousCrystalShineEnabled && shineEnabled && shineStyle == .linear && input == .device && isMotionAvailable
    }
    private var continuousGyroPose: CardCrystalPlayMotion.Pose? {
        wantsContinuousGyro && isActive && !isSuspended ? crystalGyro.pose : nil
    }

    public init(cardView: UIView, onLight: @escaping (CardSurfaceLight) -> Void) {
        self.onLight = onLight
        self.cardView = cardView
    }

    // Older iOS concurrency runtimes can crash in isolated deinit (Swift #85663).
    // Cleanup only invalidates resources; it does not touch actor-isolated UI.
    deinit {
        displayLink?.invalidate()
        motion.stopDeviceMotionUpdates()
    }

    public func setActive(_ active: Bool, animated: Bool = false) {
        guard active != isActive else {
            if !active, !animated, returningToRest {
                returningToRest = false
                stop()
                pressMotion.reset()
                renderTransform(force: true)
            }
            return
        }
        isActive = active
        if active {
            if returningToRest { stop() }
            returningToRest = false
            activationLight = animated ? rendered : nil
            activationElapsed = 0
            startIfNeeded()
        } else {
            activationLight = nil
            stop()
            target = .zero
            current = .zero
            borderMotion.reset()
            lightActivity.reset()
            linearShine.reset()
            resetCrystalPlay()
            resetTouchSpot()
            // A swipe takes ownership of the gesture, but not of its visible pose.
            // Settle only the transform; lights and Metal stay paused during scrolling.
            returningToRest = animated && !isSuspended && !CATransform3DEqualToTransform(renderedTransform, CATransform3DIdentity)
            if returningToRest { pressMotion.release() }
            else { pressMotion.reset() }
            previewReleaseAfter = nil
            minimumPressTimeRemaining = 0
            renderFrame(force: true)
            startIfNeeded()
        }
    }

    public func recenter() {
        if returningToRest { stop() }
        returningToRest = false
        activationLight = nil
        borderDeviceTilt.reset()
        borderGyro.reset()
        deviceTilt.reset()
        gramReflection.reset()
        crystalGyro.reset()
        target = .zero
        current = .zero
        borderMotion.reset()
        rendered = CardSurfaceLight()
        lightActivity.reset()
        linearShine.reset()
        resetCrystalPlay()
        resetTouchSpot()
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
            if returningToRest {
                returningToRest = false
                pressMotion.reset()
            }
            resetCrystalPlay()
            previewReleaseAfter = nil
            minimumPressTimeRemaining = 0
            pressMotion.release()
            linearShine.endDirectionalPress(cancelled: true)
            touchSpot.release()
            renderFrame(force: true)
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
        if newPress { crystalPlay.reset(); crystalOwnsRelease = false }
        pressPoint = point; isPressDown = true
        if borderShineEnabled { borderMotion.press(at: point) }
        crystalPlay.move(to: point)
        pressMotion.press(at: point)
        if touchSpotEnabled { touchSpot.press(at: point, began: newPress) }
        if shineEnabled, shineStyle == .linear, crystalPlay.pose == nil, !wantsContinuousGyro {
            if linearTouchMode == .circular {
                if newPress { linearShine.reset() }
                touchSpot.press(at: point)
            } else if linearTouchMode == .directional {
                if newPress {
                    let size = cardView?.bounds.size ?? CGSize(width: 358, height: 208)
                    linearShine.beginDirectionalPress(at: point, angle: linearTouchAngle,
                        improved: improvedLinearBehavior, aspectRatio: size.width / max(1, size.height))
                }
                else { linearShine.moveDirectionalPress(to: point) }
            } else if newPress {
                linearShine.press()
            }
        }
        if newPress { renderFrame(force: true) }
        startIfNeeded()
    }

    public func releasePress(cancelled: Bool = false) {
        isPressDown = false
        borderMotion.release()
        let wasPlaying = crystalPlay.pose != nil
        crystalPlay.release(to: continuousGyroPose)
        // A short tap must never keep the delayed glow alive.
        touchSpot.release()
        linearShine.endDirectionalPress(cancelled: cancelled || wasPlaying)
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
        (shineEnabled || borderShineEnabled) && (input == .sweep || (input == .device && isMotionAvailable))
    }

    private var isLightSettled: Bool {
        abs(current.x - target.x) < 0.0005 && abs(current.y - target.y) < 0.0005
    }

    private var frameRateRange: CAFrameRateRange {
        CAFrameRateRange(minimum: Float(framesPerSecond), maximum: Float(framesPerSecond), preferred: Float(framesPerSecond))
    }

    private func startIfNeeded() {
        guard !externallyDriven, isActive || returningToRest, !isSuspended, displayLink == nil,
              returningToRest || activationLight != nil || needsContinuousInput || (borderShineEnabled && !borderMotion.isSettled) || crystalPlay.isAnimating || previewReleaseAfter != nil || !pressMotion.isSettled
                || (touchSpotEnabled && !touchSpot.isSettled)
                || (shineEnabled && (!isLightSettled || !lightActivity.isSettled || linearShine.isAnimating || !touchSpot.isSettled)) else { return }
        if isActive, input == .device, shineEnabled || borderShineEnabled, isMotionAvailable {
            deviceTilt.reset()
            gramReflection.reset()
            crystalGyro.reset()
            motion.deviceMotionUpdateInterval = 1 / Double(framesPerSecond)
            // Poll the latest fused accelerometer/gyro sample. No callback backlog on the main queue.
            if deviceSampleProvider == nil { motion.startDeviceMotionUpdates(using: .xArbitraryZVertical) }
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
        gramReflection.reset()
        crystalGyro.reset()
        borderDeviceTilt.reset()
        borderGyro.reset()
        previousTime = 0
    }

    fileprivate func tick(_ link: CADisplayLink) {
        let dt = previousTime == 0 ? 1 / Double(framesPerSecond) : min(link.timestamp - previousTime, 0.1)
        previousTime = link.timestamp
        advanceFrame(by: dt)
    }

    func advanceFrame(by dt: TimeInterval) {
        guard !isSuspended, dt > 0 else { return }
        if returningToRest {
            pressMotion.advance(by: dt)
            renderTransform()
            if pressMotion.isSettled {
                returningToRest = false
                stop()
            }
            return
        }
        guard isActive else { return }
        if activationLight != nil {
            activationElapsed += dt
            if activationElapsed >= CardSurfaceLight.resumeDuration { activationLight = nil }
        }
        minimumPressTimeRemaining = max(0, minimumPressTimeRemaining - dt)
        if let remaining = previewReleaseAfter {
            if remaining <= dt {
                previewReleaseAfter = nil
                pressMotion.release()
                isPressDown = false
                borderMotion.release()
                linearShine.endDirectionalPress()
                touchSpot.release()
            } else {
                previewReleaseAfter = remaining - dt
            }
        }
        let crystalOwnsFrame = crystalPlay.pose != nil
        touchSpot.advance(by: dt)
        var angularSpeed = 0.0
        var pitch = deviceTilt.pitch
        var roll = deviceTilt.roll
        if shineEnabled || borderShineEnabled {
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
                if shineStyle == .radial { gramReflection.synthetic(tilt: next) }
            }
            if wantsContinuousGyro, crystalGyro.hasSample {
                current = crystalGyro.tilt
            } else {
                let amount = CGFloat(1 - exp(-dt / responseTime))
                current.x += (target.x - current.x) * amount
                current.y += (target.y - current.y) * amount
                if isLightSettled { current = target }
            }
            if crystalOwnsFrame || wantsContinuousGyro {
                linearShine.rebase(to: pitch, roll: roll)
            } else if shineStyle == .linear, linearTouchMode == .circular, touchSpot.isFollowing || !touchSpot.isSettled {
                linearShine.rebase(to: pitch, roll: roll)
            } else if shineStyle == .linear {
                linearShine.advance(pitch: pitch, roll: roll,
                                    pitchSensitivity: linearPitchSensitivity, rollSensitivity: linearRollSensitivity,
                                    triggerAngle: linearTriggerAngle, returnAngle: linearReturnAngle,
                                    angularSpeed: input == .device
                                        ? hypot(deviceTilt.pitchAngularSpeed * Double(linearPitchSensitivity),
                                                deviceTilt.rollAngularSpeed * Double(linearRollSensitivity)) : nil,
                                    suppressTilt: linearTouchMode == .directional && pressMotion.isEngaged,
                                    improved: improvedLinearBehavior,
                                    by: dt)
            }
        }
        if borderShineEnabled {
            borderMotion.advance(gyro: input == .device ? borderGyro.tilt : (input == .sweep ? target : .zero), by: dt)
        }
        crystalPlay.advance(by: dt, returningTo: continuousGyroPose)
        pressMotion.advance(by: dt)
        if shineStyle == .radial { gramReflection.advance(by: dt) }
        if crystalOwnsFrame || wantsContinuousGyro { lightActivity.reset() }
        else { lightActivity.advance(angularSpeed: angularSpeed, touch: shineEnabled && !crystalOwnsRelease ? pressMotion.value.z : 0, by: dt) }
        renderFrame()
        if !externallyDriven, activationLight == nil, !needsContinuousInput, !crystalPlay.isAnimating, previewReleaseAfter == nil, pressMotion.isSettled,
           (!shineEnabled || (isLightSettled && lightActivity.isSettled && !linearShine.isAnimating)),
           touchSpot.isSettled, (!borderShineEnabled || borderMotion.isSettled) {
            renderFrame(force: true)
            stop()
        }
    }

    private func renderTransform(force: Bool = false) {
        let transform = pressMotion.transform(cardWidth: cardView?.bounds.width ?? 370)
        if force || !CATransform3DEqualToTransform(transform, renderedTransform) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            cardView?.layer.transform = transform
            CATransaction.commit()
            renderedTransform = transform
        }
    }

    private func renderFrame(force: Bool = false) {
        renderTransform(force: force)
        let pressTilt = pressMotion.lightTilt
        let tilt = CGPoint(x: clamp(current.x + pressTilt.x), y: clamp(current.y + pressTilt.y))
        let crystal = continuousCrystalShineEnabled && shineEnabled ? crystalPlay.pose ?? continuousGyroPose : nil
        let linearPosition = crystal?.position ?? (shineStyle == .linear ? linearShine.position : nil)
        let linearAngle = crystal?.angle ?? linearShine.linearAngle
        let activity = crystal?.opacity ?? (shineStyle == .linear && linearShine.isAnimating ? 1 : lightActivity.value)
        var light = CardSurfaceLight(tilt: tilt, activity: activity, press: pressMotion.value.z,
                                     linearPosition: linearPosition, linearAngle: linearAngle,
                                     touchSpot: (touchSpotEnabled || linearTouchMode == .circular) && (touchSpot.isFollowing || !touchSpot.isSettled)
                                        ? touchSpot.light : nil,
                                     borderTilt: borderShineEnabled ? borderMotion.value : nil)
        if shineStyle == .radial, shineEnabled, isActive, !isSuspended {
            let size = cardView?.bounds.size ?? CGSize(width: 400, height: 232)
            light.gramReflection = gramReflection.pose(mode: gramReflectionMode, press: pressMotion.value,
                                                       aspect: Double(size.height / max(size.width, 1)),
                                                       v2Limit: gramV2MaxRotation, v2Sensitivity: gramV2Sensitivity)
        }
        if let activationLight {
            light = light.interpolated(from: activationLight,
                progress: CardSurfaceLight.resumeProgress(elapsed: activationElapsed))
        }
        if force || !light.visuallyMatches(rendered) {
            onLight(light)
            rendered = light
        }
    }

    private func updateDeviceTarget(by dt: TimeInterval) -> Double {
        let sample: DeviceSample?
        if let provider = deviceSampleProvider { sample = provider() }
        else { sample = readDeviceSample() }
        guard let sample else { return 0 }
        if shineStyle == .radial {
            gramReflection.sample(attitude: sample.attitude, rotationRate: sample.rotationRate,
                                  orientation: sample.orientation, by: dt)
        }
        if borderShineEnabled {
            _ = borderDeviceTilt.update(attitude: sample.attitude, rotationRate: sample.rotationRate,
                orientation: sample.orientation, touchActive: false, lightIsSettled: false,
                sensitivity: sensitivity, by: dt)
            borderGyro.advance(pitch: borderDeviceTilt.pitch, roll: borderDeviceTilt.roll, sensitivity: sensitivity, by: dt)
        }
        let response = deviceTilt.update(attitude: sample.attitude, rotationRate: sample.rotationRate,
            orientation: sample.orientation,
            touchActive: pressMotion.isEngaged || previewReleaseAfter != nil,
            // A continuous reflection has no idle expiry: keep its reference
            // while the user holds a new phone angle, just like a real material.
            lightIsSettled: !wantsContinuousGyro && lightActivity.isSettled,
            sensitivity: sensitivity, by: dt)
        if wantsContinuousGyro {
            crystalGyro.advance(pitch: deviceTilt.pitch, roll: deviceTilt.roll, sensitivity: sensitivity, by: dt)
            target = crystalGyro.tilt
        } else {
            target = response.tilt
        }
        return response.angularSpeed
    }

    private func readDeviceSample() -> DeviceSample? {
        guard let sample = motion.deviceMotion else { return nil }
        return DeviceSample(attitude: sample.attitude.quaternion, rotationRate: sample.rotationRate,
            orientation: cardView?.window?.windowScene?.interfaceOrientation ?? .portrait)
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
