import UIKit
import UIComponents
import WalletContext

/// Telegram's voice recording interface, driving dictation: the microphone grows into a pulsing circle that follows
/// the finger, a lock panel above it, and the field turns into a recording panel with a blinking dot, a timer and
/// "Slide to cancel"
enum AgentVoiceRecordingMetrics {
    static let circleDiameter: CGFloat = 110
    /// Room for the waves at their loudest
    static let blobDiameter: CGFloat = 240
    static let lockPanelSize = CGSize(width: 40, height: 72)
    static let lockedPanelHeight: CGFloat = 40
    /// The lock panel's centre above the circle's centre
    static let lockPanelOffset: CGFloat = 122
    /// Upward travel at which the lock closes completely
    static let lockTravel: CGFloat = 105
    /// Leftward travel over which the circle shrinks, down to 40%
    static let cancelScaleTravel: CGFloat = 300
    static let recordingDotDiameter: CGFloat = 10
    static let recordingDotColor = UIColor(red: 1, green: 45 / 255, blue: 85 / 255, alpha: 1)
    static let hintWobble: CGFloat = 6
    /// Telegram's "Cancel" of a locked recording: 17 pt regular, replacing "Slide to cancel"
    static let cancelFontSize: CGFloat = 17
    /// The solid centre circle at rest, and its scale of the blob
    static let centreDiameter: CGFloat = 99
    static let centreRestingScale: CGFloat = centreDiameter / blobDiameter
    /// The failure circle shrinks to the trailing circle's size before it fades into the microphone
    static let failureCollapsedScale: CGFloat = AgentComposerMetrics.microphoneSize / (blobDiameter * centreRestingScale)

    static func formatTimer(_ elapsed: TimeInterval) -> String {
        let total = max(0, elapsed)
        let seconds = Int(total)
        let centiseconds = min(99, Int((total - floor(total)) * 100))
        return String(format: "%d:%02d,%02d", seconds / 60, seconds % 60, centiseconds)
    }
}

final class AgentDictationButton: UIButton {
    var onAccessibilityActivate: (() -> Bool)?

    override func accessibilityActivate() -> Bool {
        onAccessibilityActivate?() ?? super.accessibilityActivate()
    }
}

/// The field's content while recording
final class AgentDictationStripView: UIView {
    private let recordingDot = UIView()
    private let timerLabel = UILabel()
    private let hintLabel = UILabel()
    private let cancelButton = UIButton(type: .system)
    private var state = AgentDictationState()
    private var isAnimating = false

    var onCancel: (() -> Void)?

    var cancelAccessibilityElement: UIView { cancelButton }

    override init(frame: CGRect) {
        super.init(frame: frame)
        recordingDot.layer.cornerRadius = AgentVoiceRecordingMetrics.recordingDotDiameter / 2
        recordingDot.backgroundColor = AgentVoiceRecordingMetrics.recordingDotColor
        recordingDot.isAccessibilityElement = false
        timerLabel.font = .monospacedDigitSystemFont(ofSize: 15, weight: .regular)
        timerLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        hintLabel.font = .systemFont(ofSize: 15)
        hintLabel.textAlignment = .center
        hintLabel.lineBreakMode = .byTruncatingTail
        cancelButton.setTitle(lang("Cancel"), for: .normal)
        cancelButton.titleLabel?.font = .systemFont(ofSize: AgentVoiceRecordingMetrics.cancelFontSize)
        cancelButton.addTarget(self, action: #selector(cancelPressed), for: .touchUpInside)
        addSubview(recordingDot)
        addSubview(timerLabel)
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
        let isNearLimit = state.phase != .recognizing && state.elapsed >= 50
        timerLabel.textColor = isNearLimit ? .air.error : .label
        hintLabel.textColor = isNearLimit ? .air.error : .air.secondaryLabel
        cancelButton.tintColor = tintColor
    }

    func update(_ state: AgentDictationState) {
        let previousPhase = self.state.phase
        self.state = state
        // Locking turns "Slide to cancel" into "Cancel", as in Telegram
        let shouldRevealCancel = previousPhase == .holding && state.phase == .locked && window != nil && !isHidden
            && UIView.areAnimationsEnabled && !UIAccessibility.isReduceMotionEnabled
        let hintSnapshot = shouldRevealCancel ? hintLabel.snapshotView(afterScreenUpdates: false) : nil
        let isRecording = state.phase == .holding || state.phase == .locked
        let isComingIn = isRecording && (previousPhase == .idle || previousPhase == .failed) && window != nil && !isHidden
            && UIView.areAnimationsEnabled && !UIAccessibility.isReduceMotionEnabled
        let hintFrame = hintLabel.frame
        let isRightToLeft = effectiveUserInterfaceLayoutDirection == .rightToLeft
        let isRecognizing = state.phase == .recognizing
        let isLocked = state.phase == .locked
        let isNearLimit = state.elapsed >= 50
        timerLabel.text = AgentVoiceRecordingMetrics.formatTimer(state.elapsed)
        recordingDot.isHidden = isRecognizing
        timerLabel.isHidden = isRecognizing
        cancelButton.isHidden = !isRecognizing && !isLocked
        hintLabel.isHidden = isLocked && !isNearLimit
        if isRecognizing {
            hintLabel.text = lang("$agent_dictation_recognizing")
        } else if isNearLimit {
            hintLabel.text = L10n.agentDictationTimeLeft(seconds: max(0, Int(ceil(60 - state.elapsed))))
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
        if shouldRevealCancel {
            layoutIfNeeded()
            revealCancel(replacing: hintSnapshot, at: hintFrame)
        }
        if isComingIn {
            layoutIfNeeded()
            animateComingIn()
        }
    }

    /// Telegram's recording panel coming in: the hint slides in from past the trailing end on Telegram's 0.4 s curve,
    /// the timer fades in on its layout spring, and the dot grows in before it starts blinking
    private func animateComingIn() {
        let isRightToLeft = effectiveUserInterfaceLayoutDirection == .rightToLeft
        let textWidth = min(hintLabel.bounds.width, ceil(hintLabel.intrinsicContentSize.width))
        let startX = isRightToLeft ? -textWidth : bounds.width + textWidth
        let slide = CABasicAnimation(keyPath: "position.x")
        slide.fromValue = startX - hintLabel.layer.position.x
        slide.toValue = 0
        slide.isAdditive = true
        slide.duration = Self.slideInDuration
        slide.timingFunction = AgentComposerMetrics.makeTelegramCurve()
        hintLabel.layer.add(slide, forKey: "slideIn")

        let fade = CASpringAnimation(keyPath: "opacity")
        fade.mass = 1
        fade.stiffness = AgentComposerMetrics.telegramSpringStiffness
        fade.damping = AgentComposerMetrics.telegramSpringDamping
        fade.duration = Self.timerFadeDuration
        fade.fromValue = 0
        fade.toValue = 1
        fade.fillMode = .backwards
        timerLabel.layer.add(fade, forKey: "fadeIn")

        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 0.3
        grow.toValue = 1
        grow.duration = Self.dotAppearanceDuration
        grow.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        recordingDot.layer.add(grow, forKey: "growIn")
        let dotFade = CABasicAnimation(keyPath: "opacity")
        dotFade.fromValue = 0
        dotFade.toValue = 1
        dotFade.duration = Self.dotAppearanceDuration
        dotFade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        recordingDot.layer.add(dotFade, forKey: "fadeIn")
        // The dot starts blinking once it is in
        if let blink = recordingDot.layer.animation(forKey: "blink")?.copy() as? CAAnimation {
            blink.beginTime = recordingDot.layer.convertTime(CACurrentMediaTime(), from: nil) + Self.dotAppearanceDuration
            recordingDot.layer.add(blink, forKey: "blink")
        }
    }

    private static let slideInDuration: CFTimeInterval = 0.4
    private static let timerFadeDuration: CFTimeInterval = 0.5
    private static let dotAppearanceDuration: CFTimeInterval = 0.15

    /// Telegram's `updateIsDisplayingCancel`: the hint rises 22 pt and shrinks away while Cancel rises into its place
    private func revealCancel(replacing hintSnapshot: UIView?, at hintFrame: CGRect) {
        if let hintSnapshot {
            hintSnapshot.frame = hintFrame
            addSubview(hintSnapshot)
            UIView.animate(withDuration: 0.2) {
                hintSnapshot.center.y -= Self.cancelRevealOffset
            }
            UIView.animate(withDuration: 0.25) {
                hintSnapshot.transform = CGAffineTransform(scaleX: Self.cancelRevealScale, y: Self.cancelRevealScale)
                hintSnapshot.alpha = 0
            } completion: { _ in
                hintSnapshot.removeFromSuperview()
            }
        }
        cancelButton.transform = CGAffineTransform(translationX: 0, y: Self.cancelRevealOffset)
            .scaledBy(x: Self.cancelRevealScale, y: Self.cancelRevealScale)
        cancelButton.alpha = 0
        UIView.animate(withDuration: 0.25, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.cancelButton.transform = .identity
            self.cancelButton.alpha = 1
        }
    }

    private static let cancelRevealOffset: CGFloat = 22
    private static let cancelRevealScale: CGFloat = 0.25

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
        timerLabel.textAlignment = isRightToLeft ? .right : .left
        hintLabel.textAlignment = state.phase == .recognizing ? (isRightToLeft ? .right : .left) : .center
        // The finish control is the microphone's own circle beside the field, so the strip spans the field
        let availableWidth = bounds.width
        let dot = AgentVoiceRecordingMetrics.recordingDotDiameter
        recordingDot.frame = directionalFrame(CGRect(x: 0, y: bounds.midY - dot / 2, width: dot, height: dot))
        let timerWidth = ceil(timerLabel.sizeThatFits(bounds.size).width)
        timerLabel.frame = directionalFrame(CGRect(x: dot + 8, y: 0, width: timerWidth, height: bounds.height))

        let contentStart: CGFloat = state.phase == .recognizing ? 0 : dot + 8 + timerWidth + 8
        let contentWidth = max(0, availableWidth - contentStart)
        let cancelWidth = min(cancelButton.sizeThatFits(bounds.size).width + 12, contentWidth)
        // A locked recording shows Telegram's centred Cancel; with a countdown or while recognizing it moves to the end
        let shouldCenterCancel = state.phase == .locked && hintLabel.isHidden
        let cancelX = shouldCenterCancel ? contentStart + (contentWidth - cancelWidth) / 2 : availableWidth - cancelWidth
        // Placed by bounds and centre, which its reveal transform leaves alone
        let cancelFrame = directionalFrame(CGRect(x: cancelX, y: 0, width: cancelWidth, height: bounds.height))
        cancelButton.bounds = CGRect(origin: .zero, size: cancelFrame.size)
        cancelButton.center = CGPoint(x: cancelFrame.midX, y: cancelFrame.midY)

        // The frame is set without its drag transform so timer updates preserve the slide.
        let hintEnd = !cancelButton.isHidden && !shouldCenterCancel ? cancelX - 4 : availableWidth
        let hintWidth = max(0, hintEnd - contentStart)
        hintLabel.bounds = CGRect(x: 0, y: 0, width: hintWidth, height: bounds.height)
        hintLabel.center = CGPoint(x: horizontalPosition(contentStart + hintWidth / 2), y: bounds.midY)
    }

    private func updateAnimations() {
        let shouldAnimate = window != nil && !isHidden && (state.phase == .holding || state.phase == .locked)
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

/// The circle that grows out of the trailing circle while recording, with Telegram's audio blobs and its lock panel.
/// When a recording produces no transcript, the circle turns red with a cross and shrinks back into the microphone.
final class AgentDictationTouchView: UIView {
    private let blobView = AgentVoiceBlobView()
    private let iconView = UIImageView()
    private let lockPanel = AgentVoiceLockPanelView()
    private var phase: AgentDictationState.Phase = .idle
    private var targetTranslationY: CGFloat = 0
    private var targetCancelX: CGFloat = 0
    private var currentTranslationY: CGFloat = 0
    private var currentCancelX: CGFloat = 0
    private var currentScale: CGFloat = 1
    private lazy var clock = GlassMotionClock(frameRateRange: nil) { [weak self] _ in self?.step() }
    private var isPresented = false
    private var isShowingFailure = false
    /// Identifies the latest presentation, so completions of an interrupted failure animation are ignored
    private var presentationGeneration = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
        clipsToBounds = false
        addSubview(lockPanel)
        addSubview(blobView)
        iconView.contentMode = .center
        iconView.tintColor = .white
        iconView.image = Self.getIcon(for: .idle)
        blobView.addSubview(iconView)
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        blobView.color = tintColor
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let diameter = AgentVoiceRecordingMetrics.blobDiameter
        blobView.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        blobView.center = CGPoint(x: bounds.midX, y: bounds.midY)
        // Placed by bounds and centre, which its swap transform leaves alone
        iconView.bounds = blobView.bounds
        iconView.center = CGPoint(x: diameter / 2, y: diameter / 2)
        let panel = AgentVoiceRecordingMetrics.lockPanelSize
        lockPanel.bounds = CGRect(origin: .zero, size: panel)
        lockPanel.center = CGPoint(x: bounds.midX, y: bounds.midY - AgentVoiceRecordingMetrics.lockPanelOffset)
    }

    /// Positions the circle over the trailing circle, whose centre is `center` in the superview
    func setAnchor(_ center: CGPoint) {
        let size = AgentVoiceRecordingMetrics.circleDiameter
        bounds = CGRect(x: 0, y: 0, width: size, height: size)
        self.center = center
    }

    func update(_ state: AgentDictationState, isRightToLeft: Bool) {
        let previousPhase = phase
        phase = state.phase
        blobView.updateLevel(CGFloat(state.waveLevel))
        let isRecording = state.phase == .holding || state.phase == .locked
        if state.phase == .holding {
            targetTranslationY = min(0, CGFloat(state.dragY))
            targetCancelX = isRightToLeft ? max(0, CGFloat(state.dragX)) : min(0, CGFloat(state.dragX))
        } else {
            targetTranslationY = 0
            targetCancelX = 0
        }
        if previousPhase != state.phase {
            if state.phase == .failed {
                showFailure()
                return
            }
            if state.phase == .locked {
                lockPanel.setLocked(true, animated: true)
            }
            if isRecording {
                setIcon(Self.getIcon(for: state.phase), animated: isPresented && !UIAccessibility.isReduceMotionEnabled)
            }
        }
        if isRecording, !isPresented {
            present()
        } else if !isRecording, isPresented {
            dismiss()
        } else if state.phase == .idle, isShowingFailure {
            endFailure()
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
        setIcon(Self.getIcon(for: phase), animated: false)
        lockPanel.setLocked(phase == .locked, animated: false)
        blobView.color = tintColor
        blobView.startAnimating()
        clock.start()
        guard !UIAccessibility.isReduceMotionEnabled else {
            blobView.transform = .identity
            blobView.alpha = 1
            if phase != .locked {
                lockPanel.transform = .identity
                lockPanel.alpha = 1
            }
            return
        }
        // As in Telegram, the circle and its waves grow out of the microphone at once
        blobView.transform = CGAffineTransform(scaleX: 0.2, y: 0.2)
        blobView.alpha = 1
        lockPanel.transform = CGAffineTransform(translationX: 0, y: phase == .locked ? 36 : 100)
        lockPanel.alpha = 0
        UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.55, initialSpringVelocity: 0, options: [.beginFromCurrentState]) {
            self.blobView.transform = .identity
            self.lockPanel.transform = .identity
        }
        UIView.animate(withDuration: 0.1) {
            self.lockPanel.alpha = self.phase == .locked ? 0 : 1
        }
    }

    private func dismiss() {
        isPresented = false
        clock.stop()
        blobView.stopAnimating()
        guard !UIAccessibility.isReduceMotionEnabled else {
            isHidden = true
            return
        }
        UIView.animate(withDuration: 0.18, delay: 0, options: [.beginFromCurrentState]) {
            self.blobView.transform = CGAffineTransform(scaleX: 0.2, y: 0.2)
            self.blobView.alpha = 0
            self.lockPanel.transform = CGAffineTransform(translationX: 0, y: 100)
            self.lockPanel.alpha = 0
        } completion: { [weak self] _ in
            guard let self, !self.isPresented, !self.isShowingFailure else { return }
            self.isHidden = true
            self.blobView.transform = .identity
        }
    }

    /// The failure indicator: the circle settles at rest (or pops back out of the trailing circle after recognition),
    /// turns red as its waves go, swaps its glyph for a cross, then shrinks onto the trailing circle and fades into the
    /// microphone, within `AgentDictationController.failureDuration`
    private func showFailure() {
        presentationGeneration += 1
        let generation = presentationGeneration
        let isPresentedBefore = isPresented
        isPresented = false
        isShowingFailure = true
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
            self.lockPanel.transform = CGAffineTransform(translationX: 0, y: 100)
            self.lockPanel.alpha = 0
        }
        blobView.setFailed(true, animated: isPresentedBefore)
        setIcon(Self.failureIcon, animated: isPresentedBefore && !isMotionReduced)
        if isMotionReduced {
            blobView.transform = .identity
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
                self.blobView.transform = CGAffineTransform(scaleX: Self.failurePopScale, y: Self.failurePopScale)
            } completion: { [weak self] _ in
                guard let self, generation == self.presentationGeneration else { return }
                UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.55, initialSpringVelocity: 0, options: [.beginFromCurrentState]) {
                    self.blobView.transform = .identity
                } completion: { [weak self] _ in
                    self?.collapseFailure(generation, isMotionReduced: false)
                }
            }
        } else {
            let collapsedScale = AgentVoiceRecordingMetrics.failureCollapsedScale
            blobView.transform = CGAffineTransform(scaleX: collapsedScale, y: collapsedScale)
            blobView.alpha = 0
            UIView.animate(withDuration: 0.42, delay: 0, usingSpringWithDamping: 0.55, initialSpringVelocity: 0, options: [.beginFromCurrentState]) {
                self.blobView.transform = .identity
            } completion: { [weak self] _ in
                self?.collapseFailure(generation, isMotionReduced: false)
            }
            UIView.animate(withDuration: 0.1) {
                self.blobView.alpha = 1
            }
        }
    }

    /// Shrinks the red circle onto the trailing circle, where the microphone shows through as it fades
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
        isHidden = true
        blobView.layer.removeAllAnimations()
        blobView.transform = .identity
        blobView.alpha = 1
        blobView.setFailed(false, animated: false)
        setIcon(Self.getIcon(for: phase), animated: false)
    }

    /// Telegram's glyph swap on locking: the old glyph shrinks away as the new one grows from 30%
    private func setIcon(_ image: UIImage?, animated: Bool) {
        guard iconView.image !== image else { return }
        guard animated, window != nil, let snapshot = iconView.snapshotView(afterScreenUpdates: false) else {
            iconView.image = image
            return
        }
        snapshot.frame = iconView.frame
        blobView.insertSubview(snapshot, belowSubview: iconView)
        iconView.image = image
        iconView.transform = CGAffineTransform(scaleX: 0.3, y: 0.3)
        iconView.alpha = 0
        let swap = UIViewPropertyAnimator(duration: 0.3, timingParameters: AgentComposerMetrics.makeTelegramCubicTiming())
        swap.addAnimations {
            self.iconView.transform = .identity
            snapshot.transform = CGAffineTransform(scaleX: 0.001, y: 0.001)
        }
        swap.addCompletion { _ in
            snapshot.removeFromSuperview()
        }
        swap.startAnimation()
        UIView.animate(withDuration: 0.2) {
            snapshot.alpha = 0
            self.iconView.alpha = 1
        }
    }

    private static func getIcon(for phase: AgentDictationState.Phase) -> UIImage? {
        phase == .locked ? finishIcon : microphoneIcon
    }

    private static let microphoneIcon = UIImage(
        systemName: "mic.fill",
        withConfiguration: UIImage.SymbolConfiguration(pointSize: 30, weight: .semibold)
    )

    private static let finishIcon = UIImage(
        systemName: "checkmark",
        withConfiguration: UIImage.SymbolConfiguration(pointSize: 28, weight: .semibold)
    )

    private static let failureIcon = UIImage(
        systemName: "xmark",
        withConfiguration: UIImage.SymbolConfiguration(pointSize: 26, weight: .bold)
    )

    /// The red circle's brief swell as it takes the failure
    private static let failurePopScale: CGFloat = 1.1

    /// Telegram's smoothing: each frame closes 30% of the remaining distance to the finger
    private func step() {
        guard isPresented else { return }
        currentTranslationY = min(0, currentTranslationY * 0.7 + targetTranslationY * 0.3)
        let cancelTarget = targetCancelX
        currentCancelX = currentCancelX * 0.7 + cancelTarget * 0.3
        let cancelProgress = min(1, max(0, abs(currentCancelX) / AgentVoiceRecordingMetrics.cancelScaleTravel))
        currentScale = max(0.4, 1 - cancelProgress)
        blobView.updatePresentationLevel()
        if blobView.layer.animationKeys()?.isEmpty ?? true {
            blobView.transform = CGAffineTransform(translationX: currentCancelX, y: currentTranslationY)
                .scaledBy(x: currentScale, y: currentScale)
        }
        if lockPanel.layer.animationKeys()?.isEmpty ?? true, phase != .locked {
            lockPanel.transform = CGAffineTransform(translationX: 0, y: currentTranslationY)
        }
        lockPanel.lockness = phase == .locked ? 1 : min(1, abs(currentTranslationY) / AgentVoiceRecordingMetrics.lockTravel)
    }
}

/// Telegram's lock panel: a capsule with an open padlock and an arrow that closes as the finger slides up
final class AgentVoiceLockPanelView: UIView {
    private let backgroundView: UIView
    private let lockView = UIImageView()
    private let arrowView = UIImageView()
    private var isLocked = false

    var lockness: CGFloat = 0 {
        didSet { if lockness != oldValue { setNeedsLayout() } }
    }

    override init(frame: CGRect) {
        if #available(iOS 26, iOSApplicationExtension 26, *), IOS_26_MODE_ENABLED {
            let effectView = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
            effectView.cornerConfiguration = .capsule()
            backgroundView = effectView
        } else {
            let view = UIView()
            view.backgroundColor = .air.background
            view.layer.cornerRadius = AgentVoiceRecordingMetrics.lockPanelSize.width / 2
            view.layer.shadowColor = UIColor.black.cgColor
            view.layer.shadowOpacity = 0.12
            view.layer.shadowRadius = 6
            view.layer.shadowOffset = CGSize(width: 0, height: 1)
            backgroundView = view
        }
        super.init(frame: frame)
        isUserInteractionEnabled = false
        addSubview(backgroundView)
        lockView.contentMode = .center
        arrowView.contentMode = .center
        lockView.tintColor = .air.secondaryLabel
        arrowView.tintColor = .air.secondaryLabel
        arrowView.image = UIImage(systemName: "chevron.up", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold))
        addSubview(lockView)
        addSubview(arrowView)
        updateLockImage()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setLocked(_ isLocked: Bool, animated: Bool) {
        guard self.isLocked != isLocked else { return }
        self.isLocked = isLocked
        updateLockImage()
        guard isLocked else {
            alpha = 1
            transform = .identity
            return
        }
        // Once locked, the panel closes into the padlock and goes away, as in Telegram
        let animations = {
            self.lockness = 1
            self.layoutIfNeeded()
            self.transform = CGAffineTransform(scaleX: 0.01, y: 0.01)
            self.alpha = 0
        }
        if animated && !UIAccessibility.isReduceMotionEnabled {
            UIView.animate(withDuration: 0.25, delay: 0.1, options: [.beginFromCurrentState], animations: animations)
        } else {
            animations()
        }
    }

    private func updateLockImage() {
        lockView.image = UIImage(
            systemName: isLocked ? "lock.fill" : "lock.open.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        )
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = AgentVoiceRecordingMetrics.lockPanelSize
        let height = size.height - (size.height - AgentVoiceRecordingMetrics.lockedPanelHeight) * lockness
        backgroundView.frame = CGRect(x: 0, y: size.height - height, width: size.width, height: height)
        lockView.frame = CGRect(x: 0, y: size.height - height + 4, width: size.width, height: 32)
        arrowView.frame = CGRect(x: 0, y: 48 - 39 * lockness, width: size.width, height: 16)
        arrowView.alpha = 1 - lockness
    }
}
