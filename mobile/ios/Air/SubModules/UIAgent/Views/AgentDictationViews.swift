import UIKit
import UIComponents
import WalletContext

/// Telegram's voice recording interface, driving dictation: the microphone grows into a pulsing circle that follows
/// the finger, a hint above it shows that a swipe up keeps the question in the field, and the field turns into a
/// recording panel with a blinking dot and "Slide to cancel", or a cancelling cross for a hands-free recording. A
/// dictation that leaves its transcript in the field leaves a floating microphone of Liquid Glass that dictates more.
enum AgentVoiceRecordingMetrics {
    static let circleDiameter: CGFloat = 110
    /// Room for the waves at their loudest
    static let blobDiameter: CGFloat = 240
    /// The pause hint's centre above the circle's centre, where Telegram's lock sits
    static let pauseHintOffset: CGFloat = 122
    /// Leftward travel over which the circle shrinks, down to 40%
    static let cancelScaleTravel: CGFloat = 300
    static let recordingDotDiameter: CGFloat = 10
    static let recordingDotColor = UIColor(red: 1, green: 45 / 255, blue: 85 / 255, alpha: 1)
    static let hintWobble: CGFloat = 6
    /// How far the hints come in from and go back to, from behind the recording circle, as Telegram's lock panel does
    static let hintEntranceTravel: CGFloat = 100
    /// Telegram's "Cancel" while recognizing: 17 pt regular
    static let cancelFontSize: CGFloat = 17
    /// The solid centre circle at rest, and its scale of the blob
    static let centreDiameter: CGFloat = 99
    static let centreRestingScale: CGFloat = centreDiameter / blobDiameter
    /// The failure circle shrinks to the trailing circle's size before it fades into the microphone
    static let failureCollapsedScale: CGFloat = AgentComposerMetrics.microphoneSize / (blobDiameter * centreRestingScale)

    /// How far the finger has gone toward the pause point, from 0 where it started to 1 where the recording pauses
    @MainActor
    static func getPauseProgress(dragY: CGFloat) -> CGFloat {
        min(1, max(0, -dragY) / CGFloat(AgentDictationController.pauseDistance))
    }
}

final class AgentDictationButton: UIButton {
    var onAccessibilityActivate: (() -> Bool)?

    override func accessibilityActivate() -> Bool {
        onAccessibilityActivate?() ?? super.accessibilityActivate()
    }
}

/// The field's content while recording: Telegram's blinking dot, with "Slide to cancel" once the finger holds the
/// microphone, and the recognition's status with Cancel after it
final class AgentDictationStripView: UIView {
    private let recordingDot = UIView()
    private let hintLabel = UILabel()
    private let cancelButton = UIButton(type: .system)
    private var state = AgentDictationState()
    private var isAnimating = false
    /// The dot and the hint leaving as a recording ends, clipped to the strip
    private(set) weak var leavingPanel: UIView?

    var onCancel: (() -> Void)?

    var cancelAccessibilityElement: UIView { cancelButton }

    override init(frame: CGRect) {
        super.init(frame: frame)
        recordingDot.layer.cornerRadius = AgentVoiceRecordingMetrics.recordingDotDiameter / 2
        recordingDot.backgroundColor = AgentVoiceRecordingMetrics.recordingDotColor
        recordingDot.isAccessibilityElement = false
        hintLabel.font = .systemFont(ofSize: 15)
        hintLabel.textAlignment = .center
        hintLabel.lineBreakMode = .byTruncatingTail
        cancelButton.titleLabel?.font = .systemFont(ofSize: AgentVoiceRecordingMetrics.cancelFontSize)
        cancelButton.accessibilityLabel = lang("Cancel")
        cancelButton.addTarget(self, action: #selector(cancelPressed), for: .touchUpInside)
        addSubview(recordingDot)
        addSubview(hintLabel)
        addSubview(cancelButton)
        applyTheme()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateAnimations()
    }

    func applyTheme() {
        hintLabel.textColor = .air.secondaryLabel
        cancelButton.tintColor = tintColor
    }

    func update(_ state: AgentDictationState) {
        let wasRecording = self.state.phase == .holding || self.state.phase == .handsFree
        let wasDotShown = wasRecording && !recordingDot.isHidden
        let wasHintShown = self.state.phase == .holding && !hintLabel.isHidden
        let isRecording = state.phase == .holding || state.phase == .handsFree
        // A recording cancelled by sliding toward the leading end leaves on that way; any other leaves the way it came
        let wasSlidToCancel = self.state.phase == .holding
            && (effectiveUserInterfaceLayoutDirection == .rightToLeft ? self.state.dragX > 0 : self.state.dragX < 0)
            || self.state.phase == .handsFree
        let leaving = wasDotShown && !isRecording ? makeLeavingRecordingPanel() : nil
        self.state = state
        let canAnimate = window != nil && UIView.areAnimationsEnabled
        let isRightToLeft = effectiveUserInterfaceLayoutDirection == .rightToLeft
        let isRecognizing = state.phase == .recognizing
        // Nothing shows while the touch isn't yet a tap or a hold: the dot comes in with the hint once it is a hold, or
        // alone once it is a tap
        recordingDot.isHidden = !isRecording || state.phase == .holding && !state.isHeld
        let isDotComingIn = isRecording && !recordingDot.isHidden && !wasDotShown && canAnimate && !isHidden
        // A hands-free recording's cross floats above the field, as `AgentDictationCancelBubble`
        cancelButton.isHidden = !isRecognizing
        cancelButton.setTitle(lang("Cancel"), for: .normal)
        hintLabel.isHidden = state.phase == .holding ? !state.isHeld || state.isFloating : !isRecognizing
        let isHintComingIn = state.phase == .holding && !hintLabel.isHidden && !wasHintShown && canAnimate && !isHidden
        if isRecognizing {
            hintLabel.text = lang("$agent_dictation_recognizing")
        } else {
            // Isolate the arrow so RTL text does not mirror its physical direction.
            let arrow = isRightToLeft ? "\u{2066}›\u{2069} " : "‹ "
            hintLabel.text = arrow + lang("$agent_dictation_slide_to_cancel")
        }
        if state.phase == .holding {
            let cancelDrag = isRightToLeft ? max(0, state.dragX) : min(0, state.dragX)
            hintLabel.transform = CGAffineTransform(translationX: CGFloat(cancelDrag), y: 0)
            hintLabel.alpha = max(0, 1 - CGFloat(abs(cancelDrag) / 110))
        } else {
            hintLabel.transform = .identity
            hintLabel.alpha = 1
        }
        applyTheme()
        updateAnimations()
        setNeedsLayout()
        if isDotComingIn || isHintComingIn {
            layoutIfNeeded()
            slideIn(dot: isDotComingIn, hint: isHintComingIn)
        }
        if let leaving {
            slideOut(leaving, towardLeadingEnd: wasSlidToCancel)
        }
    }

    /// Once the touch is a hold, "Slide to cancel" and the recording dot come in together, from behind the recording
    /// circle at the trailing end, on the spring and with the quick fade the pause hint rises on, as Telegram's lock
    /// panel comes in. Once it is a tap, the hands-free recording's dot, with no hint, slides in from past the leading
    /// end, where it stands, on Telegram's 0.4 s curve, never crossing the field's placeholder. With Reduce Motion they
    /// fade in.
    private func slideIn(dot isDotComingIn: Bool, hint isHintComingIn: Bool) {
        let views = (isDotComingIn ? [recordingDot] : []) + (isHintComingIn ? [hintLabel] : [])
        guard !UIAccessibility.isReduceMotionEnabled else {
            for view in views {
                view.layer.add(Self.makeFadeIn(duration: Self.fadeDuration), forKey: "fadeIn")
            }
            return
        }
        guard isHintComingIn else {
            let slide = CABasicAnimation(keyPath: "position.x")
            slide.fromValue = getLeadingSlideDistance(of: recordingDot)
            slide.toValue = 0
            slide.isAdditive = true
            slide.duration = Self.slideDuration
            slide.timingFunction = AgentComposerMetrics.makeTelegramCurve()
            recordingDot.layer.add(slide, forKey: "slideIn")
            startBlinking(after: Self.slideDuration)
            return
        }
        let travel = AgentVoiceRecordingMetrics.hintEntranceTravel
        let distance = effectiveUserInterfaceLayoutDirection == .rightToLeft ? -travel : travel
        for view in views {
            // Additive, so the hint's slide after the finger rides on it
            let spring = Self.makeHintEntranceSpring()
            spring.keyPath = "position.x"
            spring.fromValue = distance
            spring.toValue = 0
            spring.isAdditive = true
            view.layer.add(spring, forKey: "slideIn")
            view.layer.add(Self.makeFadeIn(duration: Self.hintEntranceFadeDuration), forKey: "fadeIn")
        }
        if isDotComingIn {
            startBlinking(after: Self.hintEntranceFadeDuration)
        }
    }

    /// The pause hint's spring, `UIView`'s with damping 0.55 over 0.5 s: its damping ratio, settling in about half a
    /// second
    private static func makeHintEntranceSpring() -> CASpringAnimation {
        let stiffness: CGFloat = 280
        let spring = CASpringAnimation()
        spring.mass = 1
        spring.stiffness = stiffness
        spring.damping = 2 * 0.55 * stiffness.squareRoot()
        spring.duration = spring.settlingDuration
        return spring
    }

    private static func makeFadeIn(duration: CFTimeInterval) -> CABasicAnimation {
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = duration
        return fade
    }

    /// The dot starts blinking once it is in
    private func startBlinking(after delay: CFTimeInterval) {
        guard let blink = recordingDot.layer.animation(forKey: "blink")?.copy() as? CAAnimation else { return }
        blink.beginTime = recordingDot.layer.convertTime(CACurrentMediaTime(), from: nil) + delay
        recordingDot.layer.add(blink, forKey: "blink")
    }

    /// How far `view` travels from past the strip's leading end to its place
    private func getLeadingSlideDistance(of view: UIView) -> CGFloat {
        let isRightToLeft = effectiveUserInterfaceLayoutDirection == .rightToLeft
        let startX = isRightToLeft ? bounds.width + view.bounds.width : -view.bounds.width
        return startX - view.layer.position.x
    }

    /// Stand-ins for the dot and the hint as they show, in a view over the strip in the strip's superview, which keeps
    /// them in sight while they leave as the strip goes and clips them to the strip, inside the field
    private func makeLeavingRecordingPanel() -> UIView? {
        guard let container = superview, window != nil, !isHidden, UIView.areAnimationsEnabled else { return nil }
        leavingPanel?.removeFromSuperview()
        let panel = UIView(frame: frame)
        panel.clipsToBounds = true
        panel.isUserInteractionEnabled = false
        panel.isAccessibilityElement = false
        let dot = UIView()
        dot.backgroundColor = recordingDot.backgroundColor
        dot.layer.cornerRadius = recordingDot.layer.cornerRadius
        dot.frame = recordingDot.layer.presentation()?.frame ?? recordingDot.frame
        panel.addSubview(dot)
        if !hintLabel.isHidden, hintLabel.alpha > 0.01, let text = hintLabel.text {
            let hint = UILabel()
            hint.font = hintLabel.font
            hint.textColor = hintLabel.textColor
            hint.textAlignment = hintLabel.textAlignment
            hint.lineBreakMode = hintLabel.lineBreakMode
            hint.text = text
            hint.alpha = CGFloat(hintLabel.layer.presentation()?.opacity ?? Float(hintLabel.alpha))
            hint.frame = hintLabel.layer.presentation()?.frame ?? hintLabel.frame
            panel.addSubview(hint)
        }
        container.insertSubview(panel, aboveSubview: self)
        leavingPanel = panel
        return panel
    }

    /// The dot and the hint leave together, the same way, as far and as fast, fading as they go: past the trailing end,
    /// the way they came, or past the leading end after a slide to cancel. With Reduce Motion they only fade.
    private func slideOut(_ panel: UIView, towardLeadingEnd: Bool) {
        let isMotionReduced = UIAccessibility.isReduceMotionEnabled
        let isRightToLeft = effectiveUserInterfaceLayoutDirection == .rightToLeft
        let distance = panel.bounds.width * (towardLeadingEnd != isRightToLeft ? -1 : 1)
        let animator = UIViewPropertyAnimator(
            duration: isMotionReduced ? Self.fadeDuration : Self.slideDuration,
            timingParameters: AgentComposerMetrics.makeTelegramCubicTiming()
        )
        animator.addAnimations {
            for view in panel.subviews {
                view.alpha = 0
                if !isMotionReduced {
                    view.transform = CGAffineTransform(translationX: distance, y: 0)
                }
            }
        }
        animator.addCompletion { _ in
            panel.removeFromSuperview()
        }
        animator.startAnimation()
    }

    /// Where the strip's content starts from its leading end, after the dot: "Slide to cancel" is centred past it, and a
    /// hands-free recording's placeholder where the hint would be
    static let contentStart: CGFloat = AgentVoiceRecordingMetrics.recordingDotDiameter + 8

    /// How far a hands-free recording moves the empty field's placeholder, `placeholderWidth` wide, in from the leading
    /// end of a strip `stripWidth` wide: to the middle of the room past the dot, where "Slide to cancel" stands
    static func getCenteredPlaceholderInset(placeholderWidth: CGFloat, stripWidth: CGFloat) -> CGFloat {
        max(contentStart, contentStart + (stripWidth - contentStart - placeholderWidth) / 2)
    }

    /// How long the dot takes to come in and go, on Telegram's curve, which the field's content keeps time with
    static let slideDuration: CFTimeInterval = 0.4
    private static let fadeDuration: CFTimeInterval = 0.2
    /// The pause hint's fade as it comes in
    static let hintEntranceFadeDuration: CFTimeInterval = 0.1

    override func layoutSubviews() {
        super.layoutSubviews()
        let isRightToLeft = effectiveUserInterfaceLayoutDirection == .rightToLeft
        func horizontalPosition(_ logicalX: CGFloat) -> CGFloat {
            isRightToLeft ? bounds.width - logicalX : logicalX
        }
        func directionalFrame(_ frame: CGRect) -> CGRect {
            guard isRightToLeft else { return frame }
            return CGRect(x: horizontalPosition(frame.maxX), y: frame.minY, width: frame.width, height: frame.height)
        }
        hintLabel.textAlignment = state.phase == .recognizing ? (isRightToLeft ? .right : .left) : .center
        // The stop control is the microphone's own circle beside the field, so the strip spans the field. A hands-free
        // recording's cross stands at the leading end, away from it, before the dot.
        let availableWidth = bounds.width
        let dot = AgentVoiceRecordingMetrics.recordingDotDiameter
        recordingDot.frame = directionalFrame(CGRect(x: 0, y: bounds.midY - dot / 2, width: dot, height: dot))

        let contentStart: CGFloat = state.phase == .recognizing ? 0 : Self.contentStart
        let cancelWidth = min(cancelButton.sizeThatFits(bounds.size).width + 12, max(0, availableWidth - contentStart))
        let cancelX = availableWidth - cancelWidth
        cancelButton.frame = directionalFrame(CGRect(x: cancelX, y: 0, width: cancelWidth, height: bounds.height))

        // The frame is set without its drag transform, so layout passes preserve the slide
        let hintEnd = !cancelButton.isHidden ? cancelX - 4 : availableWidth
        let hintWidth = max(0, hintEnd - contentStart)
        hintLabel.bounds = CGRect(x: 0, y: 0, width: hintWidth, height: bounds.height)
        hintLabel.center = CGPoint(x: horizontalPosition(contentStart + hintWidth / 2), y: bounds.midY)
    }

    private func updateAnimations() {
        let shouldAnimate = window != nil && !isHidden && (state.phase == .holding || state.phase == .handsFree)
            && !UIAccessibility.isReduceMotionEnabled
        guard shouldAnimate != isAnimating else { return }
        isAnimating = shouldAnimate
        guard shouldAnimate else {
            recordingDot.layer.removeAnimation(forKey: "blink")
            hintLabel.layer.removeAnimation(forKey: "wobble")
            return
        }
        // Telegram's recording dot: on for half the cycle, then off, back and forth
        let blink = CAKeyframeAnimation(keyPath: "opacity")
        blink.values = [1, 1, 0, 0]
        blink.keyTimes = [0, 0.4546, 0.9091, 1]
        blink.duration = 0.5
        blink.autoreverses = true
        blink.repeatCount = .infinity
        recordingDot.layer.add(blink, forKey: "blink")

        // Additive, so the wobble rides on the slide that follows the finger
        let wobble = CAKeyframeAnimation(keyPath: "transform.translation.x")
        let direction: CGFloat = effectiveUserInterfaceLayoutDirection == .rightToLeft ? 1 : -1
        wobble.values = [0, direction * AgentVoiceRecordingMetrics.hintWobble, 0]
        wobble.keyTimes = [0, 0.5, 1]
        wobble.duration = 1.5
        wobble.repeatCount = .infinity
        wobble.timingFunctions = [CAMediaTimingFunction(name: .easeInEaseOut), CAMediaTimingFunction(name: .easeInEaseOut)]
        wobble.isAdditive = true
        hintLabel.layer.add(wobble, forKey: "wobble")
    }

    @objc private func cancelPressed() {
        onCancel?()
    }
}

/// The circle that grows out of the trailing circle while recording, with Telegram's audio blobs, and above it the hint
/// that a swipe up keeps the question in the field while the finger holds the microphone. A transcript bound for the
/// field leaves the floating microphone above it, which dictates more: it floats up out of the trailing circle after a
/// stop, or turns out of the hint after a swipe up, and sinks back into the trailing circle once the field is sent or
/// cleared. The floating microphone records into the field where it rests: held, while the finger holds it, and tapped,
/// hands-free, its recording circle the stop. Touches pass through to the trailing circle, all but those on the
/// floating microphone.
/// When a recording produces no transcript, the circle turns red with a cross and shrinks back into the microphone it
/// recorded on: the trailing circle, or the floating microphone, which stays where it rests.
final class AgentDictationTouchView: UIView {
    private let blobView = AgentVoiceBlobView()
    private let iconView = UIImageView()
    private let pauseHintView = AgentVoicePauseHintView()
    private let resumeButton = AgentVoiceResumeButton()
    private var phase: AgentDictationState.Phase = .idle
    private var targetTranslationY: CGFloat = 0
    private var targetCancelX: CGFloat = 0
    private var currentTranslationY: CGFloat = 0
    private var currentCancelX: CGFloat = 0
    private var currentScale: CGFloat = 1
    private lazy var clock = GlassMotionClock(frameRateRange: nil) { [weak self] _ in self?.step() }
    private var isPresented = false
    private var isShowingFailure = false
    private var isResumeShown = false
    /// The floating microphone coming in or going
    private var resumeAnimator: UIViewPropertyAnimator?
    /// Where the floating microphone rising out of the trailing circle is going
    private var resumeRiseTarget: CGRect?
    private var isHeld = false
    /// The recording is on the floating microphone, its circle where the microphone rests
    private var isFloatingRecording = false
    /// Where the red circle of a failure stands, from the trailing circle: on the floating microphone after its
    /// dictation fails
    private var failurePlace = CGAffineTransform.identity
    /// The field's top in this view's coordinates, which the floating microphone stays above
    private var fieldTop: CGFloat = .greatestFiniteMagnitude
    /// Identifies the latest presentation, so completions of an interrupted failure animation are ignored
    private var presentationGeneration = 0
    /// The recording's touch is a tap or a hold, and no longer a touch that may be either
    private var isTouchClassified = false
    /// The recording circle has grown in, which it does once the touch is a tap or a hold
    private var isCircleShown = false

    /// The trailing circle shows the microphone the floating one rises out of and sinks back into, rather than Stop,
    /// with which the floating microphone comes and goes where it rests
    var isTrailingMicrophoneShown = true
    /// The floating microphone is sinking into the trailing circle, whose microphone it becomes as it lands
    private(set) var isSinking = false {
        didSet { if isSinking != oldValue { onMicrophonePlaceChanged?() } }
    }
    /// The floating microphone is up, or on its way up, out of the trailing circle
    var isMicrophoneUp: Bool { isResumeShown }
    /// The floating microphone came up, or began or ended sinking back: the trailing circle shows its own microphone
    /// only once it is back
    var onMicrophonePlaceChanged: (() -> Void)?

    /// The floating microphone was activated with VoiceOver: it records hands-free, as a tap does
    var onResume: (() -> Void)?
    /// A finger came down on the floating microphone, and lifted
    var onFloatingTouchBegan: (() -> Void)?
    var onFloatingTouchEnded: (() -> Void)?
    /// A tap on the recording circle of a hands-free recording on the floating microphone, its stop
    var onFloatingStop: (() -> Void)?
    private lazy var floatingStopTap = UITapGestureRecognizer(target: self, action: #selector(handleFloatingStopTap))

    /// The floating microphone records hands-free where it stands, its circle the recording's stop
    var isShowingFloatingStop: Bool {
        isPresented && isFloatingRecording && phase == .handsFree
    }

    /// Where the recording circle of the floating microphone stands, in this view's coordinates: where the microphone
    /// rests
    var floatingRecordingCenter: CGPoint? {
        isFloatingRecording ? CGPoint(x: bounds.midX + targetCancelX, y: bounds.midY + targetTranslationY) : nil
    }

    /// Where a failure's red circle stands, in this view's coordinates, while it shows
    var failureCenter: CGPoint? {
        isShowingFailure ? CGPoint(x: bounds.midX + failurePlace.tx, y: bounds.midY + failurePlace.ty) : nil
    }

    /// How much of the recording circle shows
    var recordingCircleAlpha: CGFloat {
        isHidden ? 0 : blobView.alpha
    }

    /// The floating microphone takes touches here, over the chat and outside the composer's bounds
    var isTakingTouches: Bool {
        !isHidden && (isResumeShown || isShowingFloatingStop)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = false
        blobView.isUserInteractionEnabled = false
        // Out of sight until a recording presents it: the view also shows for the floating microphone, which the
        // field's first text brings, and a circle at full strength would look like a recording over the trailing circle
        blobView.alpha = 0
        pauseHintView.alpha = 0
        addSubview(pauseHintView)
        addSubview(blobView)
        iconView.contentMode = .center
        updateIconColor()
        iconView.image = Self.getIcon(for: .idle)
        blobView.addSubview(iconView)
        resumeButton.isHidden = true
        // VoiceOver activates it as a tap; a finger's touch goes to the press, which tells a tap from a hold
        resumeButton.addTarget(self, action: #selector(resumePressed), for: .touchUpInside)
        let press = UILongPressGestureRecognizer(target: self, action: #selector(handleFloatingPress(_:)))
        press.minimumPressDuration = 0
        press.allowableMovement = .greatestFiniteMagnitude
        resumeButton.addGestureRecognizer(press)
        addSubview(resumeButton)
        floatingStopTap.isEnabled = false
        addGestureRecognizer(floatingStopTap)
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        blobView.color = tintColor
        updateIconColor()
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard isTakingTouches else { return false }
        if isShowingFloatingStop, let center = floatingRecordingCenter {
            return hypot(point.x - center.x, point.y - center.y) <= AgentVoiceRecordingMetrics.circleDiameter / 2
        }
        return resumeButton.point(inside: convert(point, to: resumeButton), with: event)
    }

    @objc private func handleFloatingStopTap() {
        guard isShowingFloatingStop else { return }
        onFloatingStop?()
    }

    // VoiceOver finds the floating microphone's stop where its recording circle stands
    override var isAccessibilityElement: Bool {
        get { isShowingFloatingStop }
        set {}
    }

    override var accessibilityLabel: String? {
        get { isShowingFloatingStop ? lang("$agent_dictation_finish") : nil }
        set {}
    }

    override var accessibilityTraits: UIAccessibilityTraits {
        get { isShowingFloatingStop ? .button : .none }
        set {}
    }

    override var accessibilityFrame: CGRect {
        get {
            guard isShowingFloatingStop, let center = floatingRecordingCenter else { return super.accessibilityFrame }
            let side = AgentVoiceRecordingMetrics.circleDiameter
            let circle = CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
            return UIAccessibility.convertToScreenCoordinates(circle, in: self)
        }
        set {}
    }

    override func accessibilityActivate() -> Bool {
        guard isShowingFloatingStop else { return false }
        onFloatingStop?()
        return true
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let diameter = AgentVoiceRecordingMetrics.blobDiameter
        blobView.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        blobView.center = CGPoint(x: bounds.midX, y: bounds.midY)
        // Placed by bounds and centre, which their transforms leave alone
        iconView.bounds = blobView.bounds
        iconView.center = CGPoint(x: diameter / 2, y: diameter / 2)
        pauseHintView.bounds = CGRect(origin: .zero, size: AgentVoicePauseHintView.size)
        pauseHintView.center = CGPoint(x: bounds.midX, y: bounds.midY - AgentVoiceRecordingMetrics.pauseHintOffset)
        // The floating microphone follows the field's top as the field grows, at once with it, or in the animation the
        // field's change is in. Rising out of the trailing circle, it rises to where the field's top has gone in the
        // rest of its spring, as the field grows with text pasted into it, rather than to where the top was and then
        // there at once.
        guard isResumeShown, !isSinking else { return }
        let rest = getResumeRestFrame()
        if let resumeAnimator {
            guard let resumeRiseTarget, resumeRiseTarget != rest, resumeAnimator.state == .active else { return }
            self.resumeRiseTarget = rest
            resumeAnimator.addAnimations { [weak self] in
                guard let self else { return }
                place(resumeButton, in: rest)
            }
            return
        }
        resumeButton.bounds.size = rest.size
        let center = CGPoint(x: rest.midX, y: rest.midY)
        guard resumeButton.center != center else { return }
        resumeButton.center = center
    }

    /// Where the floating microphone rests, and stays: where the chat's scroll-to-bottom button does, over the trailing
    /// circle and as far above the field
    private func getResumeRestFrame() -> CGRect {
        let diameter = AgentVoiceResumeButton.diameter
        return CGRect(
            x: bounds.midX - diameter / 2,
            y: fieldTop - AgentVCLayout.scrollToBottomButtonSpacing - diameter,
            width: diameter,
            height: diameter
        )
    }

    /// Positions the circle over the trailing circle, whose centre is `center` in the superview, and keeps the
    /// floating microphone above the field's top, `fieldTop` in the superview
    func setAnchor(_ center: CGPoint, fieldTop: CGFloat) {
        let size = AgentVoiceRecordingMetrics.circleDiameter
        bounds = CGRect(x: 0, y: 0, width: size, height: size)
        self.center = center
        let top = fieldTop - center.y + size / 2
        if top != self.fieldTop {
            self.fieldTop = top
            // In the same pass as the field, and the same animation, if any, so the floating microphone keeps its
            // distance from the field's top as the field grows or shrinks
            setNeedsLayout()
            layoutIfNeeded()
        }
    }

    func update(_ state: AgentDictationState, isRightToLeft: Bool) {
        let previousPhase = phase
        phase = state.phase
        blobView.updateLevel(CGFloat(state.waveLevel))
        let isRecording = state.phase == .holding || state.phase == .handsFree
        let wasFloatingRecording = isFloatingRecording
        isFloatingRecording = state.isRecordingFloating
        if isFloatingRecording {
            // The circle stands where the floating microphone rests
            let rest = getResumeRestFrame()
            targetCancelX = rest.midX - bounds.midX
            targetTranslationY = rest.midY - bounds.midY
        } else if state.phase == .holding {
            targetTranslationY = min(0, CGFloat(state.dragY))
            targetCancelX = isRightToLeft ? max(0, CGFloat(state.dragX)) : min(0, CGFloat(state.dragX))
        } else {
            targetTranslationY = 0
            targetCancelX = 0
        }
        let canAnimate = window != nil && UIView.areAnimationsEnabled && !UIAccessibility.isReduceMotionEnabled
        isTouchClassified = state.phase != .holding || state.isHeld
        let wasHeld = isHeld
        isHeld = state.phase == .holding && state.isHeld && !state.isFloating
        // A swipe up's pause turns the hint into the floating microphone; a stop brings it up out of the trailing circle
        let pauseHintFrame = wasHeld && isPresented && previousPhase == .holding
            ? pauseHintView.layer.presentation()?.frame ?? pauseHintView.frame
            : nil
        // A touch on the floating microphone keeps it until the touch is a tap or a hold
        let isFloatingTouchPending = state.phase == .holding && !state.isHeld && state.isFloating
        setResumeShown(
            state.showsFloatingMicrophone || isFloatingTouchPending,
            from: pauseHintFrame,
            isInPlace: isFloatingRecording || wasFloatingRecording,
            animated: window != nil && UIView.areAnimationsEnabled
        )
        // The finger that held the floating microphone has let go without it coming back. After a tap it records
        // hands-free there, its recording circle the stop, which takes the touches the microphone took.
        if isFloatingRecording, state.phase == .handsFree, !resumeButton.isHidden {
            resumeAnimator?.stopAnimation(true)
            resumeAnimator = nil
            hideResumeButton()
        } else if !isFloatingRecording, !isResumeShown, resumeAnimator == nil, !resumeButton.isHidden {
            hideResumeButton()
        }
        // While the transcript is recognized, the floating microphone waits for it
        resumeButton.isEnabled = state.phase == .idle
        floatingStopTap.isEnabled = isFloatingRecording && state.phase == .handsFree
        if previousPhase != state.phase {
            if state.phase == .failed {
                showFailure()
                return
            }
            if isRecording {
                setIcon(Self.getIcon(for: state.phase), animated: isPresented && canAnimate)
            }
        }
        if isRecording, !isPresented {
            present()
        } else if !isRecording, isPresented {
            dismiss()
        } else if state.phase == .idle, isShowingFailure {
            endFailure()
        } else if isRecording, !isCircleShown, isTouchClassified {
            showCircle()
        }
        let canAnimateHint = window != nil && UIView.areAnimationsEnabled
        // The pause hint shows once the touch is a hold, and goes with the hold
        if isHeld, !wasHeld, isPresented {
            showPauseHint(animated: canAnimateHint)
        } else if !isHeld, wasHeld, isPresented {
            pauseHintView.layer.removeAllAnimations()
            pauseHintView.alpha = 0
        }
        // The arrow nudges up once the touch is a hold, after the hint has settled, and stops once the finger moves
        // up, and with the hold
        if isHeld, !wasHeld, isPresented {
            pauseHintView.setNudging(true)
        }
        if !isHeld || CGFloat(state.dragY) < -Self.nudgeEndTravel {
            pauseHintView.setNudging(false)
        }
    }

    /// The pause hint's arrow nudges up
    var isPauseHintNudging: Bool {
        pauseHintView.isNudging
    }

    /// The finger has gone this far up, where the hint's own rise takes over from its arrow's nudge
    private static let nudgeEndTravel: CGFloat = 4

    /// The hint rises in where Telegram's lock would, as Telegram's lock panel comes in: from behind the recording
    /// circle, on its spring, as the circle grows. With Reduce Motion it fades in in place.
    private func showPauseHint(animated: Bool) {
        pauseHintView.layer.removeAllAnimations()
        guard animated else {
            pauseHintView.transform = .identity
            pauseHintView.alpha = 1
            return
        }
        guard !UIAccessibility.isReduceMotionEnabled else {
            pauseHintView.transform = .identity
            pauseHintView.alpha = 0
            UIView.animate(withDuration: 0.2) {
                self.pauseHintView.alpha = 1
            }
            return
        }
        pauseHintView.transform = CGAffineTransform(translationX: 0, y: Self.pauseHintEntranceTravel)
        pauseHintView.alpha = 0
        UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.55, initialSpringVelocity: 0, options: [.beginFromCurrentState]) {
            self.pauseHintView.transform = CGAffineTransform(translationX: 0, y: self.currentTranslationY)
        }
        UIView.animate(withDuration: AgentDictationStripView.hintEntranceFadeDuration) {
            self.pauseHintView.alpha = 1
        }
    }

    /// How far below its place the hint comes in from, behind the recording circle
    private static let pauseHintEntranceTravel = AgentVoiceRecordingMetrics.hintEntranceTravel

    @objc private func resumePressed() {
        onResume?()
    }

    /// A finger on the floating microphone: the recording starts at once where the microphone rests. A hold records
    /// while held, and a tap records hands-free with the circle there as the stop.
    @objc private func handleFloatingPress(_ press: UILongPressGestureRecognizer) {
        switch press.state {
        case .began:
            guard resumeButton.isEnabled else { return }
            let rest = getResumeRestFrame()
            targetCancelX = rest.midX - bounds.midX
            targetTranslationY = rest.midY - bounds.midY
            currentCancelX = targetCancelX
            currentTranslationY = targetTranslationY
            onFloatingTouchBegan?()
        case .ended, .cancelled, .failed:
            onFloatingTouchEnded?()
        default:
            break
        }
    }

    private func present() {
        presentationGeneration += 1
        isPresented = true
        isShowingFailure = false
        isHidden = false
        alpha = 1
        currentTranslationY = 0
        currentCancelX = 0
        currentScale = 1
        blobView.layer.removeAllAnimations()
        blobView.setFailed(false, animated: false)
        updateIconColor()
        setIcon(Self.getIcon(for: phase), animated: false)
        blobView.color = tintColor
        clock.start()
        if isFloatingRecording {
            // On the floating microphone, where it rests
            currentTranslationY = targetTranslationY
            currentCancelX = targetCancelX
        }
        // The pause hint comes in once the touch on the trailing microphone is a hold
        pauseHintView.layer.removeAllAnimations()
        pauseHintView.transform = .identity
        pauseHintView.alpha = 0
        isCircleShown = false
        blobView.alpha = 0
        if isTouchClassified {
            showCircle()
        }
    }

    /// The circle and its waves grow out of the microphone at once, as in Telegram, once the touch is a tap or a hold,
    /// so they never come in for one and go for the other. With Reduce Motion they fade in in place.
    private func showCircle() {
        isCircleShown = true
        blobView.startAnimating()
        guard !UIAccessibility.isReduceMotionEnabled else {
            blobView.transform = CGAffineTransform(translationX: currentCancelX, y: currentTranslationY)
            UIView.animate(withDuration: 0.2, delay: 0, options: [.beginFromCurrentState]) {
                self.blobView.alpha = 1
            }
            return
        }
        let place = CGAffineTransform(translationX: currentCancelX, y: currentTranslationY)
        blobView.transform = place.scaledBy(x: 0.2, y: 0.2)
        blobView.alpha = 1
        UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.55, initialSpringVelocity: 0, options: [.beginFromCurrentState]) {
            self.blobView.transform = place
        }
    }

    private func dismiss() {
        isPresented = false
        clock.stop()
        blobView.stopAnimating()
        guard !UIAccessibility.isReduceMotionEnabled else {
            blobView.alpha = 0
            pauseHintView.alpha = 0
            updateVisibility()
            return
        }
        // The circle shrinks away where it stands
        let place = CGAffineTransform(translationX: currentCancelX, y: currentTranslationY)
        UIView.animate(withDuration: 0.18, delay: 0, options: [.beginFromCurrentState]) {
            self.blobView.transform = place.scaledBy(x: 0.2, y: 0.2)
            self.blobView.alpha = 0
            self.pauseHintView.alpha = 0
        } completion: { [weak self] _ in
            guard let self, !self.isPresented, !self.isShowingFailure else { return }
            self.blobView.transform = .identity
            self.updateVisibility()
        }
    }

    /// The view stays while it shows the circle, a failure or the floating microphone
    private func updateVisibility() {
        isHidden = !isPresented && !isShowingFailure && !isResumeShown
    }

    /// The floating microphone comes in as a bubble of glass that settles above the field on a spring with a little
    /// overshoot: out of the pause hint at `hintFrame`, after a swipe up, or up out of the trailing circle. It goes by
    /// sinking back into the trailing circle as its glass dissolves. With Reduce Motion it fades in and out in place.
    private func setResumeShown(_ isShown: Bool, from hintFrame: CGRect?, isInPlace: Bool = false, animated: Bool) {
        guard isShown != isResumeShown else { return }
        isResumeShown = isShown
        onMicrophonePlaceChanged?()
        resumeAnimator?.stopAnimation(true)
        resumeAnimator = nil
        resumeRiseTarget = nil
        isSinking = false
        resumeButton.transform = .identity
        let rest = getResumeRestFrame()
        let trailingCircle = CGRect(
            x: bounds.midX - AgentComposerMetrics.microphoneSize / 2,
            y: bounds.midY - AgentComposerMetrics.microphoneSize / 2,
            width: AgentComposerMetrics.microphoneSize,
            height: AgentComposerMetrics.microphoneSize
        )
        if isShown {
            updateVisibility()
            resumeButton.isHidden = false
        }
        guard animated else {
            place(resumeButton, in: rest)
            if !isShown, isFloatingRecording {
                // The finger still holds it: out of sight, it stays for the touch
                resumeButton.setMaterialized(false)
                return
            }
            resumeButton.isHidden = !isShown
            resumeButton.setMaterialized(true)
            updateVisibility()
            return
        }
        let animator: UIViewPropertyAnimator
        if isInPlace {
            // Under the finger, the microphone gives way to the recording circle and comes back where the finger left
            // it, its glass dissolving and forming in place
            place(resumeButton, in: rest)
            if isShown { resumeButton.setMaterialized(false) }
            animator = UIViewPropertyAnimator(duration: 0.2, curve: .easeInOut) {
                self.resumeButton.setMaterialized(isShown)
            }
        } else if UIAccessibility.isReduceMotionEnabled {
            place(resumeButton, in: rest)
            if isShown { resumeButton.setMaterialized(false) }
            animator = UIViewPropertyAnimator(duration: 0.25, curve: .easeInOut) {
                self.resumeButton.setMaterialized(isShown)
            }
        } else if !isTrailingMicrophoneShown {
            // With Stop in the trailing circle there is no microphone to rise out of or sink into: it grows in and
            // shrinks away where it rests
            place(resumeButton, in: rest)
            let small = CGAffineTransform(scaleX: Self.restingAppearanceScale, y: Self.restingAppearanceScale)
            if isShown {
                resumeButton.transform = small
                resumeButton.setMaterialized(false)
            }
            animator = UIViewPropertyAnimator(duration: 0.4, dampingRatio: 0.8) {
                self.resumeButton.transform = isShown ? .identity : small
                self.resumeButton.setMaterialized(isShown)
            }
        } else if isShown {
            // The hint's arrow and pause give way to the microphone; the trailing circle's microphone rises as it is
            place(resumeButton, in: hintFrame ?? trailingCircle)
            resumeButton.setMaterialized(false, keepsGlyph: hintFrame == nil)
            resumeRiseTarget = rest
            animator = UIViewPropertyAnimator(duration: 0.55, dampingRatio: 0.68) {
                self.place(self.resumeButton, in: rest)
                self.resumeButton.setMaterialized(true)
            }
        } else {
            // It sinks into the trailing circle as the circle comes out of the field, on the circle's spring, and its
            // microphone stays in sight until it lands, where it becomes the circle's
            isSinking = true
            animator = UIViewPropertyAnimator(
                duration: AgentComposerMetrics.actionSeparationDuration,
                dampingRatio: AgentComposerMetrics.actionSeparationDamping
            )
            animator.addAnimations {
                self.place(self.resumeButton, in: trailingCircle)
                self.resumeButton.setMaterialized(false, keepsGlyph: true)
            }
        }
        animator.addCompletion { [weak self, weak animator] _ in
            guard let self, let animator, resumeAnimator === animator else { return }
            resumeAnimator = nil
            resumeRiseTarget = nil
            resumeButton.transform = .identity
            isSinking = false
            if isResumeShown {
                setNeedsLayout()
            } else if !isFloatingRecording || phase == .handsFree {
                hideResumeButton()
            }
        }
        resumeAnimator = animator
        animator.startAnimation()
    }

    /// Out of sight once gone. While a finger holds it, it stays in the hierarchy, out of sight, so the touch goes on.
    private func hideResumeButton() {
        resumeButton.isHidden = true
        resumeButton.setMaterialized(true)
        updateVisibility()
    }

    private func place(_ view: UIView, in frame: CGRect) {
        view.bounds.size = frame.size
        view.center = CGPoint(x: frame.midX, y: frame.midY)
        view.layoutIfNeeded()
    }

    /// The failure indicator: the circle settles at rest (or pops back out of the trailing circle after recognition),
    /// turns red as its waves go, swaps its glyph for a cross, then shrinks onto the microphone it plays on and fades
    /// into it, within `AgentDictationController.failureDuration`
    private func showFailure() {
        presentationGeneration += 1
        let generation = presentationGeneration
        let isPresentedBefore = isPresented
        isPresented = false
        isShowingFailure = true
        // A failed dictation of the floating microphone plays on it, where it rests, which stays there; any other
        // on the trailing circle
        let rest = getResumeRestFrame()
        failurePlace = isResumeShown
            ? CGAffineTransform(translationX: rest.midX - bounds.midX, y: rest.midY - bounds.midY)
            : .identity
        let place = failurePlace
        // Over the floating microphone, which shows through as it fades
        bringSubviewToFront(blobView)
        clock.stop()
        blobView.stopAnimating()
        guard window != nil, UIView.areAnimationsEnabled else {
            finishFailure(generation)
            return
        }
        isHidden = false
        alpha = 1
        let isMotionReduced = UIAccessibility.isReduceMotionEnabled
        UIView.animate(withDuration: 0.18, delay: 0, options: [.beginFromCurrentState]) {
            self.pauseHintView.alpha = 0
        }
        blobView.setFailed(true, animated: isPresentedBefore)
        updateIconColor()
        setIcon(Self.failureIcon, animated: isPresentedBefore && !isMotionReduced)
        if isMotionReduced {
            blobView.transform = place
            if !isPresentedBefore { blobView.alpha = 0 }
            UIView.animate(withDuration: 0.15, delay: 0, options: [.beginFromCurrentState]) {
                self.blobView.alpha = 1
            } completion: { [weak self] _ in
                self?.collapseFailure(generation, isMotionReduced: true)
            }
            return
        }
        if isPresentedBefore {
            UIView.animate(withDuration: 0.12, delay: 0, options: [.beginFromCurrentState, .curveEaseOut]) {
                self.blobView.transform = place.scaledBy(x: Self.failurePopScale, y: Self.failurePopScale)
            } completion: { [weak self] _ in
                guard let self, generation == self.presentationGeneration else { return }
                UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.55, initialSpringVelocity: 0, options: [.beginFromCurrentState]) {
                    self.blobView.transform = place
                } completion: { [weak self] _ in
                    self?.collapseFailure(generation, isMotionReduced: false)
                }
            }
        } else {
            let collapsedScale = AgentVoiceRecordingMetrics.failureCollapsedScale
            blobView.transform = place.scaledBy(x: collapsedScale, y: collapsedScale)
            blobView.alpha = 0
            UIView.animate(withDuration: 0.42, delay: 0, usingSpringWithDamping: 0.55, initialSpringVelocity: 0, options: [.beginFromCurrentState]) {
                self.blobView.transform = place
            } completion: { [weak self] _ in
                self?.collapseFailure(generation, isMotionReduced: false)
            }
            UIView.animate(withDuration: 0.1) {
                self.blobView.alpha = 1
            }
        }
    }

    /// Shrinks the red circle onto the microphone it plays on, which shows through as it fades
    private func collapseFailure(_ generation: Int, isMotionReduced: Bool) {
        guard generation == presentationGeneration, isShowingFailure else { return }
        if !isMotionReduced {
            let collapsedScale = AgentVoiceRecordingMetrics.failureCollapsedScale
            let place = failurePlace
            UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0, options: [.beginFromCurrentState]) {
                self.blobView.transform = place.scaledBy(x: collapsedScale, y: collapsedScale)
            }
        }
        UIView.animate(withDuration: 0.16, delay: isMotionReduced ? 0.3 : 0.12, options: [.beginFromCurrentState, .curveEaseIn]) {
            self.blobView.alpha = 0
        } completion: { [weak self] _ in
            self?.finishFailure(generation)
        }
    }

    /// The failure ended before its animation did, so the circle fades out at once
    private func endFailure() {
        presentationGeneration += 1
        let generation = presentationGeneration
        guard window != nil, UIView.areAnimationsEnabled else {
            finishFailure(generation)
            return
        }
        UIView.animate(withDuration: 0.12, delay: 0, options: [.beginFromCurrentState]) {
            self.blobView.alpha = 0
        } completion: { [weak self] _ in
            self?.finishFailure(generation)
        }
    }

    private func finishFailure(_ generation: Int) {
        guard generation == presentationGeneration, isShowingFailure else { return }
        isShowingFailure = false
        failurePlace = .identity
        insertSubview(blobView, belowSubview: resumeButton)
        updateVisibility()
        blobView.layer.removeAllAnimations()
        blobView.transform = .identity
        // Out of sight until the next recording presents it: the view stays for the floating microphone, and a circle
        // left at full strength would look like a recording over the trailing circle
        blobView.alpha = 0
        blobView.setFailed(false, animated: false)
        updateIconColor()
        setIcon(Self.getIcon(for: phase), animated: false)
    }

    private func setIcon(_ image: UIImage?, animated: Bool) {
        swapRecordingGlyph(of: iconView, to: image, animated: animated)
    }

    private func updateIconColor() {
        iconView.tintColor = isShowingFailure ? .white : tintColor.foregroundForTintedBackground
    }

    private static func getIcon(for phase: AgentDictationState.Phase) -> UIImage? {
        phase == .handsFree ? stopIcon : microphoneIcon
    }

    private static let microphoneIcon = UIImage(
        systemName: "mic.fill",
        withConfiguration: UIImage.SymbolConfiguration(pointSize: 30, weight: .semibold)
    )

    private static let stopIcon = UIImage(
        systemName: "stop.fill",
        withConfiguration: UIImage.SymbolConfiguration(pointSize: 26, weight: .semibold)
    )

    private static let failureIcon = UIImage(
        systemName: "xmark",
        withConfiguration: UIImage.SymbolConfiguration(pointSize: 26, weight: .bold)
    )

    /// The red circle's brief swell as it takes the failure
    private static let failurePopScale: CGFloat = 1.1
    /// How small the floating microphone grows in from and shrinks away to where it rests
    private static let restingAppearanceScale: CGFloat = 0.5

    /// Telegram's smoothing: each frame closes 30% of the remaining distance to the finger
    private func step() {
        guard isPresented else { return }
        // With Reduce Motion the circle moves with the finger without easing after it
        let pull: CGFloat = UIAccessibility.isReduceMotionEnabled ? 1 : 0.3
        let translationY = currentTranslationY * (1 - pull) + targetTranslationY * pull
        // The circle on the floating microphone stands above the field, at its full size
        currentTranslationY = isFloatingRecording ? translationY : min(0, translationY)
        let cancelTarget = targetCancelX
        currentCancelX = currentCancelX * (1 - pull) + cancelTarget * pull
        let cancelProgress = min(1, max(0, abs(currentCancelX) / AgentVoiceRecordingMetrics.cancelScaleTravel))
        currentScale = isFloatingRecording ? 1 : max(0.4, 1 - cancelProgress)
        blobView.updatePresentationLevel()
        if blobView.layer.animationKeys()?.isEmpty ?? true {
            blobView.transform = CGAffineTransform(translationX: currentCancelX, y: currentTranslationY)
                .scaledBy(x: currentScale, y: currentScale)
        }
        // The pause hint rises with the finger and fades a little toward the pause point
        if isHeld, pauseHintView.layer.animationKeys()?.isEmpty ?? true {
            pauseHintView.transform = CGAffineTransform(translationX: 0, y: currentTranslationY)
            pauseHintView.alpha = 1 - 0.5 * AgentVoiceRecordingMetrics.getPauseProgress(dragY: targetTranslationY)
        }
    }
}

/// The hint that a swipe up pauses, where Telegram's lock sits while the finger holds the microphone: an arrow over
/// the pause glyph in a small capsule of the recording controls' glass
final class AgentVoicePauseHintView: UIView {
    static let size = CGSize(width: 36, height: 60)
    private let backgroundView: UIView
    private let arrowView = UIImageView(image: UIImage(
        systemName: "chevron.up",
        withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
    ))
    private let pauseView = UIImageView(image: UIImage(
        systemName: "pause.fill",
        withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
    ))

    override init(frame: CGRect) {
        backgroundView = makeRecordingControlBackground(cornerRadius: AgentVoicePauseHintView.size.width / 2)
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        backgroundView.isUserInteractionEnabled = false
        addSubview(backgroundView)
        for view in [arrowView, pauseView] {
            view.contentMode = .center
            view.tintColor = .air.secondaryLabel
            addSubview(view)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The arrow nudges up, showing that the microphone goes up to pause
    private(set) var isNudging = false

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateArrowMotion()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        backgroundView.frame = bounds
        arrowView.frame = CGRect(x: 0, y: 8, width: bounds.width, height: 18)
        pauseView.frame = CGRect(x: 0, y: bounds.height - 30, width: bounds.width, height: 22)
    }

    /// Starts the arrow's nudge a moment after the hold begins, or stops it, as the finger moves up and the hint's own
    /// rise takes over, or the recording ends
    func setNudging(_ isNudging: Bool) {
        guard isNudging != self.isNudging else { return }
        self.isNudging = isNudging
        updateArrowMotion()
    }

    /// As Telegram's arrow over its waiting lock does, the arrow rises a few points as it fades a little, and eases back,
    /// about once a second. With Reduce Motion it stays still.
    private func updateArrowMotion() {
        guard isNudging, window != nil, !UIAccessibility.isReduceMotionEnabled else {
            arrowView.layer.removeAnimation(forKey: Self.nudgeKey)
            return
        }
        guard arrowView.layer.animation(forKey: Self.nudgeKey) == nil else { return }
        let rise = CAKeyframeAnimation(keyPath: "transform.translation.y")
        rise.values = [0, -Self.nudgeDistance, 0]
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [1, 0.55, 1]
        let nudge = CAAnimationGroup()
        nudge.animations = [rise, fade]
        for animation in [rise, fade] {
            animation.keyTimes = [0, 0.45, 1]
            animation.timingFunctions = [
                CAMediaTimingFunction(name: .easeOut),
                CAMediaTimingFunction(name: .easeInEaseOut),
            ]
        }
        nudge.duration = Self.nudgePeriod
        nudge.repeatCount = .infinity
        nudge.beginTime = arrowView.layer.convertTime(CACurrentMediaTime(), from: nil) + Self.nudgeDelay
        nudge.fillMode = .backwards
        arrowView.layer.add(nudge, forKey: Self.nudgeKey)
    }

    static let nudgeKey = "nudge"
    /// How far the arrow rises, its cycle, and how long after the hold begins it starts
    static let nudgeDistance: CGFloat = 6
    static let nudgePeriod: CFTimeInterval = 1.1
    static let nudgeDelay: CFTimeInterval = 0.3
}

/// The floating microphone over a dictated question: it dictates more, after the field's text. It is the chat's
/// scroll-to-bottom button's size and glass, with the composer's microphone. The glass holds the microphone and takes
/// the touches, so it stretches toward the finger and moves the microphone with it.
final class AgentVoiceResumeButton: UIButton {
    static let diameter: CGFloat = AgentScrollToBottomButton.size
    /// The least side of the area that takes the button's touches
    private static let minimumTouchSide: CGFloat = 44
    private let glassView = AgentScrollToBottomButton.makeGlassView()
    private let backgroundView: UIView
    private let glyphView = UIImageView(image: AgentComposerView.microphoneImage)

    init() {
        if let glassView {
            backgroundView = glassView
        } else {
            let plainView = UIView()
            AgentScrollToBottomButton.stylePlainBackground(plainView)
            plainView.isUserInteractionEnabled = false
            backgroundView = plainView
        }
        super.init(frame: .zero)
        addSubview(backgroundView)
        glyphView.contentMode = .center
        glyphView.tintColor = AgentComposerView.idleMicrophoneColor
        glyphView.isUserInteractionEnabled = false
        (glassView?.contentView ?? self).addSubview(glyphView)
        accessibilityLabel = lang("$agent_voice_resume")
        accessibilityIdentifier = "agent_voice_resume"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet { updateGlyph() }
    }

    /// The glass takes the touches, so VoiceOver's activation reaches the button's actions directly
    override func accessibilityActivate() -> Bool {
        guard isEnabled else { return false }
        sendActions(for: .touchUpInside)
        return true
    }

    /// The glyph is out of sight while the glass is dissolved, unless `keepsGlyph`
    private var isGlyphShown = true

    /// Forms or dissolves the glass, which ignores alpha, with the glyph; inside an animation block it animates
    func setMaterialized(_ isMaterialized: Bool, keepsGlyph: Bool = false) {
        isGlyphShown = isMaterialized || keepsGlyph
        if let glassView {
            glassView.setMaterialized(isMaterialized)
            // The glyph is in the glass, whose content goes with it
            glassView.contentView.alpha = isGlyphShown ? 1 : 0
        } else {
            backgroundView.alpha = isMaterialized ? 1 : 0
        }
        updateGlyph()
    }

    private func updateGlyph() {
        glyphView.alpha = isGlyphShown ? (isHighlighted ? 0.4 : 1) : 0
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        backgroundView.frame = bounds
        if glassView == nil {
            backgroundView.layer.cornerRadius = bounds.height / 2
        }
        glyphView.frame = glyphView.superview?.bounds ?? bounds
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if glassView == nil, traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            AgentScrollToBottomButton.stylePlainBackground(backgroundView)
        }
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let inset = min(0, (bounds.width - Self.minimumTouchSide) / 2)
        return bounds.insetBy(dx: inset, dy: min(0, (bounds.height - Self.minimumTouchSide) / 2)).contains(point)
    }
}

/// A hands-free recording's cancelling cross above the field's leading end: a round glass button as the Agent header's
/// are, of their size and with their glyph weight, on clear interactive Liquid Glass that holds the button, so the
/// glass stretches toward the finger and moves the cross with it. The glass is `view` itself, for the composer to put
/// it in the field's glass container, where it splits off the field's glass and merges back into it. Without Liquid
/// Glass it is a plain circle as the chat's floating buttons are.
@MainActor
final class AgentDictationCancelBubble {
    static let diameter = WGlassButtonMetrics.size
    static let crossImage = UIImage(systemName: "xmark", withConfiguration: WGlassButtonMetrics.symbolConfiguration)

    /// The glass, or without Liquid Glass the place of the plain circle, which the composer places
    let view: UIView
    let glassView: WGlassView?
    let button = AgentChatNavigation.makeGlyphButton(image: AgentDictationCancelBubble.crossImage, primaryAction: nil)
    /// The plain circle, which scales as it comes and goes
    private let circleView: UIView?

    init() {
        let side = Self.diameter
        let glass = AgentScrollToBottomButton.makeGlassView()
        let host: UIView
        if let glass {
            view = glass
            circleView = nil
            host = glass.contentView
        } else {
            let place = UIView(frame: CGRect(x: 0, y: 0, width: side, height: side))
            let circle = UIView(frame: place.bounds)
            circle.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            circle.layer.cornerRadius = side / 2
            AgentScrollToBottomButton.stylePlainBackground(circle)
            place.addSubview(circle)
            view = place
            circleView = circle
            host = circle
        }
        glassView = glass
        if glass != nil {
            // The glass moves the cross with it as it stretches, so the button doesn't dim
            button.automaticallyUpdatesConfiguration = false
        }
        view.bounds.size = CGSize(width: side, height: side)
        button.frame = host.bounds
        button.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        button.accessibilityLabel = lang("Cancel")
        host.addSubview(button)
        view.isHidden = true
    }

    /// Shows or hides the cross on its glass, which forms and dissolves, as glass ignores alpha. Without Liquid Glass the
    /// plain circle fades, shrinking away with `isScaling` as the scroll-to-bottom button does. Inside an animation block
    /// it animates.
    func setShown(_ isShown: Bool, isScaling: Bool = false) {
        if let glassView {
            glassView.setMaterialized(isShown)
        } else if let circleView {
            circleView.alpha = isShown ? 1 : 0
            let scale = isShown || !isScaling ? 1 : AgentScrollToBottomButton.hiddenScale
            circleView.transform = CGAffineTransform(scaleX: scale, y: scale)
        }
        button.alpha = isShown ? 1 : 0
    }
}

/// The glass of the recording's controls above the circle: Liquid Glass, or the background colour with a soft shadow
@MainActor
private func makeRecordingControlBackground(cornerRadius: CGFloat) -> UIView {
    if #available(iOS 26, iOSApplicationExtension 26, *), IOS_26_MODE_ENABLED {
        let effectView = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
        effectView.cornerConfiguration = .capsule()
        return effectView
    }
    let view = UIView()
    view.backgroundColor = .air.background
    view.layer.cornerRadius = cornerRadius
    view.layer.shadowColor = UIColor.black.cgColor
    view.layer.shadowOpacity = 0.12
    view.layer.shadowRadius = 6
    view.layer.shadowOffset = CGSize(width: 0, height: 1)
    return view
}

/// Telegram's glyph swap in the recording controls: the old glyph shrinks away as the new one grows from 30%
@MainActor
private func swapRecordingGlyph(of imageView: UIImageView, to image: UIImage?, animated: Bool) {
    guard imageView.image !== image else { return }
    guard animated, imageView.window != nil, let container = imageView.superview,
          let snapshot = imageView.snapshotView(afterScreenUpdates: false) else {
        imageView.image = image
        return
    }
    snapshot.frame = imageView.frame
    container.insertSubview(snapshot, belowSubview: imageView)
    imageView.image = image
    imageView.transform = CGAffineTransform(scaleX: 0.3, y: 0.3)
    imageView.alpha = 0
    let swap = UIViewPropertyAnimator(duration: 0.3, timingParameters: AgentComposerMetrics.makeTelegramCubicTiming())
    swap.addAnimations {
        imageView.transform = .identity
        snapshot.transform = CGAffineTransform(scaleX: 0.001, y: 0.001)
    }
    swap.addCompletion { _ in
        snapshot.removeFromSuperview()
    }
    swap.startAnimation()
    UIView.animate(withDuration: 0.2) {
        snapshot.alpha = 0
        imageView.alpha = 1
    }
}
