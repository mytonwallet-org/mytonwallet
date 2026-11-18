import UIKit
import UIComponents
import WalletContext

/// Telegram's voice recording interface, driving dictation: the microphone grows into a pulsing circle that follows
/// the finger along the field, between the field's cross and Send, and the field tells what letting go does there. A
/// hands-free recording's circle is its stop, and its voice runs through the field as a thread of light.
enum AgentVoiceRecordingMetrics {
    /// A circle over the field's microphone, a little taller than the field, the waves reaching past it
    static let circleDiameter: CGFloat = 54
    /// Room for the waves at their loudest
    static let blobDiameter: CGFloat = 120
    /// How far the hint comes in from, from behind the recording circle, as Telegram's lock panel does
    static let hintEntranceTravel: CGFloat = 100
    /// The solid centre circle at rest, and its scale of the blob
    static let centreDiameter: CGFloat = circleDiameter
    static let centreRestingScale: CGFloat = centreDiameter / blobDiameter
    /// The failure circle, smaller than the recording's, which then shrinks to the field's microphone's size before it
    /// fades into it
    static let failureScale: CGFloat = 30 / centreDiameter
    /// A hands-free recording's stop, as tall as the field's buttons
    static let stopScale: CGFloat = AgentComposerMetrics.sendButtonSize.height / centreDiameter
    static let failureCollapsedScale: CGFloat = AgentComposerMetrics.fieldMicrophoneSize / (blobDiameter * centreRestingScale)
}

final class AgentDictationButton: UIButton {
    var onAccessibilityActivate: (() -> Bool)?

    override func accessibilityActivate() -> Bool {
        onAccessibilityActivate?() ?? super.accessibilityActivate()
    }
}

/// The field's content while recording: what letting go does once the finger holds the microphone, a hands-free
/// recording's voice, and the recognition's status, which nothing cancels
final class AgentDictationStripView: UIView {
    private static let recognizingFadeDuration: TimeInterval = 0.2

    private let hintLabel = UILabel()
    /// A hands-free recording's voice, in place of a hint: a thread of light out of the stop button
    private let ribbonView = AgentVoiceRibbonView()
    private var state = AgentDictationState()

    /// The recognition's status, for VoiceOver to go to
    var statusAccessibilityElement: UIView { hintLabel }

    /// Room the content leaves at the trailing end for the recording circle, which stands in the field
    var trailingClearance: CGFloat = 0 {
        didSet {
            if trailingClearance != oldValue { setNeedsLayout() }
        }
    }

    /// Where the stop button's centre stands across the strip's bounds
    var stopCenter: CGFloat = 0 {
        didSet {
            if stopCenter != oldValue { setNeedsLayout() }
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        hintLabel.font = .systemFont(ofSize: 15)
        hintLabel.textAlignment = .center
        hintLabel.lineBreakMode = .byTruncatingTail
        addSubview(hintLabel)
        addSubview(ribbonView)
        applyTheme()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func applyTheme() {
        hintLabel.textColor = .air.secondaryLabel
    }

    func update(_ state: AgentDictationState) {
        let previousPhase = self.state.phase
        let wasHintShown = self.state.phase == .holding && !hintLabel.isHidden
        self.state = state
        let canAnimate = window != nil && UIView.areAnimationsEnabled
        let isRecognizing = state.phase == .recognizing
        hintLabel.isHidden = state.phase == .holding ? !state.isHeld : !isRecognizing
        let isHintComingIn = state.phase == .holding && !hintLabel.isHidden && !wasHintShown && canAnimate && !isHidden
        // A held microphone tells what letting go does where the finger is
        switch (isRecognizing, state.holdZone) {
        case (true, _): hintLabel.text = lang("$agent_dictation_recognizing")
        case (false, .stop): hintLabel.text = lang("$agent_dictation_release_to_stop")
        case (false, .cancel): hintLabel.text = lang("$agent_dictation_release_to_cancel")
        case (false, .send): hintLabel.text = lang("$agent_dictation_release_to_send")
        }
        hintLabel.transform = .identity
        hintLabel.alpha = 1
        // "Recognizing…" comes in with the field's glow, at the pace of Android's and the web's
        if isRecognizing, previousPhase != .recognizing, canAnimate, !isHidden {
            hintLabel.alpha = 0
            UIView.animate(withDuration: Self.recognizingFadeDuration, delay: 0, options: [.beginFromCurrentState]) {
                self.hintLabel.alpha = 1
            }
        }
        updateRibbon(previousPhase: previousPhase)
        applyTheme()
        setNeedsLayout()
        if isHintComingIn {
            layoutIfNeeded()
            slideInHint()
        }
    }

    /// Once the touch is a hold, the hint comes in from behind the recording circle at the trailing end, on a spring and
    /// with a quick fade, as Telegram's lock panel comes in. With Reduce Motion it fades in.
    private func slideInHint() {
        guard !UIAccessibility.isReduceMotionEnabled else {
            hintLabel.layer.add(Self.makeFadeIn(duration: Self.fadeDuration), forKey: "fadeIn")
            return
        }
        let travel = AgentVoiceRecordingMetrics.hintEntranceTravel
        let distance = effectiveUserInterfaceLayoutDirection == .rightToLeft ? -travel : travel
        // Additive, so the hint's slide after the finger rides on it
        let spring = Self.makeHintEntranceSpring()
        spring.keyPath = "position.x"
        spring.fromValue = distance
        spring.toValue = 0
        spring.isAdditive = true
        hintLabel.layer.add(spring, forKey: "slideIn")
        hintLabel.layer.add(Self.makeFadeIn(duration: Self.hintEntranceFadeDuration), forKey: "fadeIn")
    }

    /// `UIView`'s spring with damping 0.55 over 0.5 s: its damping ratio, settling in about half a second
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

    /// Where the strip's content starts from its leading end
    static let contentStart: CGFloat = 0

    /// How long the field's content takes to come in and go as a recording does, on Telegram's curve
    static let slideDuration: CFTimeInterval = 0.4
    private static let fadeDuration: CFTimeInterval = 0.2
    /// The hint's fade as it comes in
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
        // The hint stands at the leading end, where the field has room for it
        hintLabel.textAlignment = isRightToLeft ? .right : .left
        // The strip spans the field between the recording's cross and the circle
        let availableWidth = bounds.width

        let contentStart: CGFloat = state.phase == .recognizing ? 0 : Self.contentStart
        // The frame is set without its drag transform, so layout passes preserve the slide
        let hintEnd = max(contentStart, availableWidth - trailingClearance)
        // The thread runs from the strip's start under the stop button, so it can slide on into Send
        let ribbonStart = Self.contentStart
        ribbonView.frame = directionalFrame(CGRect(
            x: ribbonStart,
            y: 0,
            width: max(0, availableWidth - ribbonStart),
            height: bounds.height
        ))
        ribbonView.stopCenter = (isRightToLeft ? bounds.width - stopCenter : stopCenter) - ribbonStart
        let hintWidth = max(0, hintEnd - contentStart)
        hintLabel.bounds = CGRect(x: 0, y: 0, width: hintWidth, height: bounds.height)
        hintLabel.center = CGPoint(x: horizontalPosition(contentStart + hintWidth / 2), y: bounds.midY)
    }

    /// The thread comes out of the stop button as a hands-free recording starts. As it ends, the thread gathers back
    /// into the button for a transcript to go into the field, slides into Send for one to be sent, or fades otherwise.
    private func updateRibbon(previousPhase: AgentDictationState.Phase) {
        ribbonView.setLevel(state.peakLevel)
        let wasHandsFree = previousPhase == .handsFree
        let isHandsFree = state.phase == .handsFree
        guard wasHandsFree != isHandsFree else { return }
        if isHandsFree {
            ribbonView.start()
        } else if state.phase == .recognizing {
            if state.isSending {
                ribbonView.send()
            } else {
                ribbonView.stop()
            }
        } else {
            ribbonView.cancel()
        }
    }
}

/// The circle that grows out of the field's microphone while recording, with Telegram's audio blobs: held, it follows
/// the finger along the field, and a hands-free recording's circle is its stop. Touches pass through to the field, all
/// but those on the stop.
/// When a recording produces no transcript, the circle turns red with a cross and shrinks back into the microphone.
final class AgentDictationTouchView: UIView {
    private let blobView = AgentVoiceBlobView()
    private let iconView = UIImageView()
    private var phase: AgentDictationState.Phase = .idle
    private var targetCancelX: CGFloat = 0
    private var currentCancelX: CGFloat = 0
    private var currentScale: CGFloat = 1
    private lazy var clock = GlassMotionClock(frameRateRange: nil) { [weak self] _ in self?.step() }
    private var isPresented = false
    private var isShowingFailure = false
    /// Identifies the latest presentation, so completions of an interrupted failure animation are ignored
    private var presentationGeneration = 0
    /// The recording's touch is a tap or a hold, and no longer a touch that may be either
    private var isTouchClassified = false
    /// The recording circle has grown in, which it does once the touch is a tap or a hold
    private var isCircleShown = false
    /// When the recording circle began to grow in, while it grows
    private var circleAppearanceStart: CFTimeInterval?

    /// How far the held circle travels along the field from the microphone: to the cross one way and to Send the other
    var horizontalTravel: ClosedRange<CGFloat> = -1000...1000

    /// A tap on the recording circle of a hands-free recording, its stop
    var onStop: (() -> Void)?
    private lazy var stopTap = UITapGestureRecognizer(target: self, action: #selector(handleStopTap))

    /// A hands-free recording's circle is its stop, the size of the field's buttons
    var isShowingStop: Bool {
        isPresented && phase == .handsFree
    }

    /// Where the recording circle stands, in this view's coordinates: over the microphone, or where the finger has
    /// taken it along the field
    var recordingCenter: CGPoint {
        CGPoint(x: bounds.midX + targetCancelX, y: bounds.midY)
    }

    /// Where a failure's red circle stands, in this view's coordinates, while it shows: over the microphone
    var failureCenter: CGPoint? {
        isShowingFailure ? CGPoint(x: bounds.midX, y: bounds.midY) : nil
    }

    /// How much of the recording circle shows
    var recordingCircleAlpha: CGFloat {
        isHidden ? 0 : blobView.alpha
    }

    /// The stop takes touches here, outside the field's bounds
    var isTakingTouches: Bool {
        !isHidden && isShowingStop
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = false
        blobView.isUserInteractionEnabled = false
        // Out of sight until a recording presents it, as the circle grows in once the touch is a tap or a hold
        blobView.alpha = 0
        addSubview(blobView)
        iconView.contentMode = .center
        updateIconColor()
        iconView.image = Self.getIcon(for: .idle)
        blobView.addSubview(iconView)
        stopTap.isEnabled = false
        addGestureRecognizer(stopTap)
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
        let center = recordingCenter
        return hypot(point.x - center.x, point.y - center.y) <= AgentVoiceRecordingMetrics.circleDiameter / 2
    }

    @objc private func handleStopTap() {
        guard isShowingStop else { return }
        onStop?()
    }

    // VoiceOver finds the stop where the recording circle stands
    override var isAccessibilityElement: Bool {
        get { isShowingStop }
        set {}
    }

    override var accessibilityLabel: String? {
        get { isShowingStop ? lang("$agent_dictation_finish") : nil }
        set {}
    }

    override var accessibilityTraits: UIAccessibilityTraits {
        get { isShowingStop ? .button : .none }
        set {}
    }

    override var accessibilityFrame: CGRect {
        get {
            guard isShowingStop else { return super.accessibilityFrame }
            let center = recordingCenter
            let side = AgentVoiceRecordingMetrics.circleDiameter
            let circle = CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
            return UIAccessibility.convertToScreenCoordinates(circle, in: self)
        }
        set {}
    }

    override func accessibilityActivate() -> Bool {
        guard isShowingStop else { return false }
        onStop?()
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
    }

    /// Positions the circle over the field's microphone, whose centre is `center` in the superview
    func setAnchor(_ center: CGPoint) {
        let size = AgentVoiceRecordingMetrics.circleDiameter
        bounds = CGRect(x: 0, y: 0, width: size, height: size)
        self.center = center
    }

    func update(_ state: AgentDictationState) {
        let previousPhase = phase
        phase = state.phase
        blobView.updateLevel(CGFloat(state.waveLevel))
        let isRecording = state.phase == .holding || state.phase == .handsFree
        // The circle follows the finger along the field, from the cross to Send and no further
        targetCancelX = state.phase == .holding
            ? min(horizontalTravel.upperBound, max(horizontalTravel.lowerBound, CGFloat(state.dragX)))
            : 0
        let canAnimate = window != nil && UIView.areAnimationsEnabled && !UIAccessibility.isReduceMotionEnabled
        isTouchClassified = state.phase != .holding || state.isHeld
        stopTap.isEnabled = state.phase == .handsFree
        // The stop keeps to the size of the field's buttons, without waves
        blobView.setWavesHidden(state.phase == .handsFree, animated: isPresented && canAnimate)
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
    }

    private func present() {
        presentationGeneration += 1
        isPresented = true
        isShowingFailure = false
        isHidden = false
        alpha = 1
        currentCancelX = 0
        currentScale = targetScale
        blobView.layer.removeAllAnimations()
        blobView.setFailed(false, animated: false)
        updateIconColor()
        setIcon(Self.getIcon(for: phase), animated: false)
        blobView.color = tintColor
        clock.start()
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
        // A hands-free recording's stop grows straight to its size
        currentScale = targetScale
        guard !UIAccessibility.isReduceMotionEnabled else {
            blobView.transform = CGAffineTransform(translationX: currentCancelX, y: 0)
                .scaledBy(x: currentScale, y: currentScale)
            UIView.animate(withDuration: 0.2, delay: 0, options: [.beginFromCurrentState]) {
                self.blobView.alpha = 1
            }
            return
        }
        // It grows where it is going rather than where the touch had nudged it, for a tap's stop not to step aside
        // after growing, and a held circle grows as it follows the finger
        if phase != .holding {
            currentCancelX = targetCancelX
        }
        circleAppearanceStart = CACurrentMediaTime()
        applyCirclePlace()
        blobView.alpha = 1
    }

    /// The circle where it stands, at its size and as far as it has grown in
    private func applyCirclePlace() {
        let scale = currentScale * getCircleAppearanceScale()
        blobView.transform = CGAffineTransform(translationX: currentCancelX, y: 0)
            .scaledBy(x: scale, y: scale)
    }

    /// How far the circle has grown in: from a fifth of its size on `UIView`'s spring with damping 0.55 over 0.5 s
    private func getCircleAppearanceScale() -> CGFloat {
        guard let start = circleAppearanceStart else { return 1 }
        let time = CGFloat(CACurrentMediaTime() - start)
        guard time < Self.circleAppearanceDuration else {
            circleAppearanceStart = nil
            return 1
        }
        let frequency = Self.circleAppearanceStiffness.squareRoot()
        let damping = Self.circleAppearanceDamping
        let dampedFrequency = frequency * (1 - damping * damping).squareRoot()
        let decay = exp(-damping * frequency * time)
        let oscillation = cos(dampedFrequency * time)
            + damping * frequency / dampedFrequency * sin(dampedFrequency * time)
        let progress = 1 - decay * oscillation
        return Self.circleAppearanceScale + (1 - Self.circleAppearanceScale) * progress
    }

    private static let circleAppearanceScale: CGFloat = 0.2
    /// `UIView`'s spring with damping 0.55 over 0.5 s, settled within a hundredth by then
    private static let circleAppearanceStiffness: CGFloat = 280
    private static let circleAppearanceDamping: CGFloat = 0.55
    private static let circleAppearanceDuration: CGFloat = 0.6

    private func dismiss() {
        isPresented = false
        circleAppearanceStart = nil
        clock.stop()
        blobView.stopAnimating()
        guard !UIAccessibility.isReduceMotionEnabled else {
            blobView.alpha = 0
            updateVisibility()
            return
        }
        // The circle shrinks away where it stands
        let place = CGAffineTransform(translationX: currentCancelX, y: 0)
        UIView.animate(withDuration: 0.18, delay: 0, options: [.beginFromCurrentState]) {
            self.blobView.transform = place.scaledBy(x: 0.2, y: 0.2)
            self.blobView.alpha = 0
        } completion: { [weak self] _ in
            guard let self, !self.isPresented, !self.isShowingFailure else { return }
            self.blobView.transform = .identity
            self.updateVisibility()
        }
    }

    /// The view stays while it shows the circle or a failure
    private func updateVisibility() {
        isHidden = !isPresented && !isShowingFailure
    }

    /// The failure indicator: the circle settles at rest (or pops back out of the microphone after recognition), turns
    /// red as its waves go, swaps its glyph for a cross, then shrinks onto the microphone and fades into it, within
    /// `AgentDictationController.failureDuration`
    private func showFailure() {
        presentationGeneration += 1
        let generation = presentationGeneration
        let isPresentedBefore = isPresented
        isPresented = false
        circleAppearanceStart = nil
        isShowingFailure = true
        // The red circle settles smaller than the recording's, over the microphone
        let failureScale = AgentVoiceRecordingMetrics.failureScale
        let place = CGAffineTransform(scaleX: failureScale, y: failureScale)
        clock.stop()
        blobView.stopAnimating()
        guard window != nil, UIView.areAnimationsEnabled else {
            finishFailure(generation)
            return
        }
        isHidden = false
        alpha = 1
        let isMotionReduced = UIAccessibility.isReduceMotionEnabled
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
            blobView.transform = CGAffineTransform(scaleX: collapsedScale, y: collapsedScale)
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

    /// Shrinks the red circle onto the microphone, which shows through as it fades
    private func collapseFailure(_ generation: Int, isMotionReduced: Bool) {
        guard generation == presentationGeneration, isShowingFailure else { return }
        if !isMotionReduced {
            let collapsedScale = AgentVoiceRecordingMetrics.failureCollapsedScale
            UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0, options: [.beginFromCurrentState]) {
                self.blobView.transform = CGAffineTransform(scaleX: collapsedScale, y: collapsedScale)
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
        updateVisibility()
        blobView.layer.removeAllAnimations()
        blobView.transform = .identity
        // Out of sight until the next recording presents it
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
        withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
    )

    /// Drawn at the circle's size, which the stop shrinks to the field's buttons'
    private static let stopIcon = UIImage(
        systemName: "stop.fill",
        withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
    )

    private static let failureIcon = UIImage(
        systemName: "xmark",
        withConfiguration: UIImage.SymbolConfiguration(pointSize: 26, weight: .bold)
    )

    /// The red circle's brief swell as it takes the failure
    private static let failurePopScale: CGFloat = 1.1

    /// The circle's size: a hands-free recording's stop keeps to the field's buttons
    private var targetScale: CGFloat {
        phase == .handsFree ? AgentVoiceRecordingMetrics.stopScale : 1
    }

    /// Telegram's smoothing: each frame closes 30% of the remaining distance to the finger
    private func step() {
        guard isPresented else { return }
        // With Reduce Motion the circle moves with the finger without easing after it
        let pull: CGFloat = UIAccessibility.isReduceMotionEnabled ? 1 : 0.3
        currentCancelX = currentCancelX * (1 - pull) + targetCancelX * pull
        currentScale = currentScale * (1 - pull) + targetScale * pull
        blobView.updatePresentationLevel()
        if blobView.layer.animationKeys()?.isEmpty ?? true {
            applyCirclePlace()
        }
    }
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
