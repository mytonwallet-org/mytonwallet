import UIKit
import UIComponents
import WalletContext
import WalletCore

enum AgentComposerMetrics {
    static let composerBackgroundColor = UIColor.clear
    static let inputCornerRadius: CGFloat = 24
    static let minInputHeight: CGFloat = 48
    /// The least the field may grow to; with room above, it grows further, as Telegram's does
    static let maxInputHeight: CGFloat = 132
    /// Telegram stops the field this far short of the top bar, keeping a strip of the chat in view
    static let inputTopClearance: CGFloat = 120
    static let navigationBarHeight: CGFloat = 44
    /// The glass circle beside the field while it is empty, and the gap between them: the microphone
    static let microphoneSize: CGFloat = 48
    static let microphoneSpacing: CGFloat = 12
    /// The spring the trailing circle comes out of the field and merges back into it on, which the floating microphone
    /// sinks into it on too
    static let actionSeparationDuration: TimeInterval = 0.5
    static let actionSeparationDamping: CGFloat = 0.72
    /// The design's send button inside the field once it has text: a 40 × 32 capsule at the field's trailing end,
    /// 8 pt from its edge and its bottom, with 12 pt before it for the text
    static let sendButtonSize = CGSize(width: 40, height: 32)
    static let sendButtonInset: CGFloat = 8
    static let sendButtonSpacing: CGFloat = 12
    static var sendButtonReserve: CGFloat { sendButtonInset + sendButtonSize.width + sendButtonSpacing }
    /// Glass pieces closer than this flow into each other; the resting gaps are wider
    static let glassMergeSpacing: CGFloat = 6
    /// Thread composer insets around the field. Its bottom follows the keyboard, or sits where the root toolbar does.
    /// The same side inset as the root toolbar, so the field keeps its edges between the Agent list and a chat.
    static let threadHorizontalInset: CGFloat = 28
    /// Above a docked keyboard the field widens to this side inset, as the Agent list's field does there
    static let keyboardHorizontalInset: CGFloat = 16
    static let threadVerticalInset: CGFloat = 12

    /// The field's distance from the screen's bottom edge with the keyboard hidden, matching the root toolbar: just
    /// inside the home indicator's safe area, or 16 pt above the edge without one
    static func getFieldBottomInset(safeAreaBottom: CGFloat) -> CGFloat {
        safeAreaBottom > 0 ? safeAreaBottom - 2 : 16
    }
    static let contentHorizontalInset: CGFloat = 16
    static let contentVerticalInset: CGFloat = 13.5

    static var placeholderAttributes: [NSAttributedString.Key: Any] {
        [
            .font: UIFont.systemFont(ofSize: 17),
            .foregroundColor: placeholderColor,
        ]
    }

    static let placeholderColor = UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.3) : UIColor(hex: "#BFBFBF")
    }

    /// The upward arrow of the send button, drawn from the design's 30 pt glyph
    static let sendArrowImage = AgentGlyph.makeImage(size: CGSize(width: 30, height: 30), lineWidth: 2.3, strokes: [
        [CGPoint(x: 15, y: 22.5), CGPoint(x: 15, y: 8.04)],
        [CGPoint(x: 20.89, y: 13.93), CGPoint(x: 15, y: 8.04), CGPoint(x: 9.11, y: 13.93)],
    ])

    /// Telegram's iOS 26 layout spring (`make26SpringAnimationImpl`): critically damped, settled in about 0.4 s
    @MainActor
    static func makeTelegramSpring() -> UISpringTimingParameters {
        UISpringTimingParameters(mass: 1, stiffness: telegramSpringStiffness, damping: telegramSpringDamping, initialVelocity: .zero)
    }

    /// The stiffness and damping of `makeTelegramSpring`, with a mass of 1
    static let telegramSpringStiffness: CGFloat = 555.027
    static let telegramSpringDamping: CGFloat = 47.118

    /// The cubic curve of Telegram's input panel, recording panel and history transitions
    static func makeTelegramCurve() -> CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: 0.38, 0.7, 0.125, 1)
    }

    /// `makeTelegramCurve` for a property animator
    @MainActor
    static func makeTelegramCubicTiming() -> UICubicTimingParameters {
        UICubicTimingParameters(controlPoint1: CGPoint(x: 0.38, y: 0.7), controlPoint2: CGPoint(x: 0.125, y: 1))
    }
}

final class AgentComposerTextView: UITextView {
    var onHardwareSend: (() -> Void)?
    var isInputBlocked = false
    /// Typing, deleting, pasting or cutting is about to change the text, which ends what blocks it, if it can
    var onWillEdit: (() -> Void)?

    override func insertText(_ text: String) {
        onWillEdit?()
        guard !isInputBlocked else { return }
        super.insertText(text)
    }

    override func deleteBackward() {
        onWillEdit?()
        guard !isInputBlocked else { return }
        super.deleteBackward()
    }

    override func paste(_ sender: Any?) {
        onWillEdit?()
        guard !isInputBlocked else { return }
        super.paste(sender)
    }

    override func cut(_ sender: Any?) {
        onWillEdit?()
        guard !isInputBlocked else { return }
        super.cut(sender)
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false
        for press in presses {
            guard let key = press.key else { continue }
            handled = handleHardwareKeyboardKey(key) || handled
        }
        if !handled {
            super.pressesBegan(presses, with: event)
        }
    }

    private func handleHardwareKeyboardKey(_ key: UIKey) -> Bool {
        switch key.keyCode {
        case .keyboardReturnOrEnter, .keypadEnter:
            var modifiers = key.modifierFlags
            modifiers.remove(.numericPad)
            if modifiers.isEmpty {
                onHardwareSend?()
                return true
            }
            // With Shift, Option, Command or Control it starts a new line, as on the web
            if modifiers.isSubset(of: [.shift, .alternate, .command, .control]) {
                insertText("\n")
                return true
            }
            return false
        default:
            return false
        }
    }
}

final class AgentComposerView: UIView {
    enum Style {
        /// A thread's composer: the field is inset from the screen edges
        case thread
        /// The field fills the view, for a host that lays it out itself
        case bare
    }

    /// What the composer offers outside a recording: the microphone circle beside the empty field, or the send button
    /// inside the field with text
    private enum ActionMode {
        case microphone, send
    }

    let style: Style
    /// Holds the field's and the trailing circle's glass so they merge when they meet. A host can supply its own
    /// container instead, so the composer's glass also merges with the host's.
    private let glassContainerView: UIVisualEffectView?
    private weak var externalGlassHost: UIView?
    private let inputBackgroundView = WGlassView(cornerRadius: AgentComposerMetrics.inputCornerRadius)
    /// The trailing circle: the microphone while the field is empty. With text it merges into the field. A circle at
    /// any size, as it grows by its size when it swells.
    private let actionGlassView = WGlassView(cornerRadius: nil)
    /// The trailing circle's glyph and button, which appear as the circle comes out of the field
    private let actionContentView = UIView()
    private let microphoneGlyphView = UIImageView()
    /// The cross the microphone turns into for a host's close button; see `actionGlyphSwap`
    private let closeGlyphView = UIImageView(image: UIImage.airBundle("UniversalSearchXmark").withRenderingMode(.alwaysTemplate))
    /// The send button's accent capsule inside the field, and its arrow
    private let sendHighlightView = UIView()
    private let sendGlyphView = UIImageView(image: AgentComposerMetrics.sendArrowImage)
    private var isSendDisplayed = false
    /// A line at the top of the field, for content that keeps clear of it
    let inputTopGuide = UILayoutGuide()
    private let textView = AgentComposerTextView()
    private let placeholderLabel = UILabel()
    private let sendButton = UIButton(type: .system)
    private let microphoneButton = AgentDictationButton(type: .system)
    private let dictationStripView = AgentDictationStripView()
    /// Telegram's listening light inside the field, while a recording is recognized and its text comes in
    private let dictationGlowView = AgentFieldGlowView(part: .lights)
    /// Over the field's edge, reaching beyond it for the rim's bloom
    private let dictationRimView = AgentFieldGlowView(part: .rim)
    private var textReveal: AgentDictationTextReveal?
    private let dictationTouchView = AgentDictationTouchView()
    /// A hands-free recording's cancelling cross above the field's leading end, opposite where the floating microphone
    /// rests, its glass in the field's glass container
    let cancelBubble = AgentDictationCancelBubble()
    private var isCancelBubbleShown = false
    /// The cross stands above the field, rather than in the field's leading end, out of which it splits off the field's
    /// glass and back into which it merges
    private var isCancelBubbleOut = true
    /// Identifies the latest showing or hiding of the cross, so an interrupted hiding doesn't hide it
    private var cancelBubbleGeneration = 0
    private let dismissPanGestureRecognizer = UIPanGestureRecognizer()
    private let microphoneGestureRecognizer = UILongPressGestureRecognizer()
    private var microphoneTouchOrigin = CGPoint.zero
    private var microphoneLastSample: (point: CGPoint, time: CFTimeInterval)?
    private var microphoneVelocity = CGPoint.zero
    private var dictationState = AgentDictationState()
    private var isSendEnabled = false
    private var isStopAvailable = false
    /// The trailing circle shows Stop in the microphone's place, while an answer that can be stopped is being written
    private var isStopDisplayed = false
    private var isDictationStartedWithVoiceOver = false
    private var settledInputHeight = AgentComposerMetrics.minInputHeight
    /// 1 while the trailing circle stands apart from the field, 0 while it is merged into the field's trailing end
    private var actionSeparation: CGFloat = 0
    private var displayedActionTint: UIColor?
    private var displayedActionGlyph: UIImage?
    /// The trailing circle's glyph that shrinks away as another takes its place
    private(set) var leavingActionGlyphView: UIImageView?
    private var glyphAnimators: [UIViewPropertyAnimator] = []

    var dictationController: AgentDictationController? {
        didSet {
            oldValue?.onStateChanged = nil
            oldValue?.onSendTranscript = nil
            dictationController?.onStateChanged = { [weak self] state in
                self?.updateDictationState(state)
            }
            dictationController?.onSendTranscript = { [weak self] text in
                self?.sendDictatedText(text)
            }
            updateDictationState(dictationController?.state ?? AgentDictationState())
            updateActionSeparation(animated: false)
        }
    }

    private lazy var placeholderLeadingConstraint = placeholderLabel.leadingAnchor.constraint(
        equalTo: inputBackgroundView.contentView.leadingAnchor,
        constant: AgentComposerMetrics.contentHorizontalInset
    )
    /// How far the field's text and placeholder stand in from the leading end, past a recording's cross and dot
    private(set) var recordingTextInset: CGFloat = 0
    /// The text's inset at the field's trailing end, wider while Send shows there
    private var textTrailingInset = AgentComposerMetrics.contentHorizontalInset

    private lazy var placeholderTrailingConstraint: NSLayoutConstraint = {
        // A host can narrow the field to a circle while it morphs; the placeholder then just clips
        let constraint = placeholderLabel.trailingAnchor.constraint(
            lessThanOrEqualTo: inputBackgroundView.contentView.trailingAnchor,
            constant: -AgentComposerMetrics.contentHorizontalInset
        )
        constraint.priority = .defaultHigh
        return constraint
    }()

    var onDraftTextChanged: (() -> Void)?
    var onSend: (() -> Void)?
    var onStop: (() -> Void)?
    /// Asked before a recording starts, as the recording goes to the Agent: false holds it back, and the host starts it
    /// later with `startDictationHandsFree()`
    var shouldStartDictation: (() -> Bool)?
    var onBeginEditing: (() -> Void)?
    var onEndEditing: (() -> Void)?
    var onLayoutHeightChanged: (() -> Void)?
    var onRecordingCircleVisibilityChanged: (() -> Void)?
    /// The dictation moved to another phase, such as from recording to recognizing, a touch on the microphone turned
    /// out a hold, or the dictation began or ended offering to dictate more
    var onDictationPhaseChanged: (() -> Void)?

    /// The floating microphone shows above the field, where it dictates more
    var isShowingFloatingMicrophone: Bool {
        dictationState.showsFloatingMicrophone
    }

    /// Whether the recording circle stands over the trailing circle: while recording, and while it shows a failure
    private(set) var isRecordingCircleVisible = false

    /// The field shows a question: one being recorded or recognized, a transcript coming in, or text. A touch on the
    /// microphone that isn't yet a tap or a hold shows nothing of its recording, so it adds no question until it is one.
    var showsQuestion: Bool {
        let isTouchUnclassified = dictationState.phase == .holding && !dictationState.isHeld && !dictationState.isFloating
        return isDictating && !isTouchUnclassified || dictationState.canDictateMore || textReveal != nil || hasText
    }

    var placeholder: String = lang("Ask anything") {
        didSet {
            placeholderLabel.attributedText = NSAttributedString(string: placeholder, attributes: AgentComposerMetrics.placeholderAttributes)
        }
    }

    var draftText: String? {
        textView.text
    }

    var isTextInputActive: Bool {
        textView.isFirstResponder
    }

    /// The top of the field, for content that keeps clear of it
    var inputTopAnchor: NSLayoutYAxisAnchor {
        inputTopGuide.topAnchor
    }

    /// The field's frame in this view's coordinates
    var inputBackgroundFrame: CGRect {
        fieldFrame
    }

    /// The field's current height, between the one-line minimum and the multi-line maximum
    var inputHeight: CGFloat {
        settledInputHeight
    }

    /// Opacity of the field's content, without its glass. A host fades it while the field morphs.
    var contentAlpha: CGFloat = 1 {
        didSet {
            for view in [textView, placeholderLabel, dictationStripView] as [UIView] {
                view.alpha = contentAlpha
            }
            applyGlassAppearance()
        }
    }

    /// Holds the trailing circle apart from the field, for a host that grows the composer out of a field and a circle
    /// beside it: 1 keeps the circle apart even while the field has text, 0 lets the field take it in then
    var actionCircleHold: CGFloat = 0 {
        didSet {
            if actionCircleHold != oldValue { layoutGlass() }
        }
    }

    /// Room the field leaves before the trailing circle besides its usual spacing, for a host whose own controls
    /// stand there while the composer grows over them
    var fieldTrailingReserve: CGFloat = 0 {
        didSet {
            if fieldTrailingReserve != oldValue { layoutGlass() }
        }
    }

    /// Scales the trailing circle's glyph around its center, for a host whose own glyph it takes over: the arriving
    /// glyph grows in as the leaving one shrinks away
    var actionContentScale: CGFloat = 1 {
        didSet {
            guard actionContentScale != oldValue else { return }
            actionContentView.transform = actionContentScale == 1
                ? .identity
                : CGAffineTransform(scaleX: actionContentScale, y: actionContentScale)
        }
    }

    /// Scales the field and the trailing circle around their centers, for a host's morph
    var glassScale: CGFloat = 1 {
        didSet {
            if glassScale != oldValue { layoutGlass() }
        }
    }

    /// Opacity of the composer's glass, for a host whose fades don't reach glass that lives in another container
    var glassAlpha: CGFloat = 1 {
        didSet { applyGlassAppearance() }
    }

    /// Hides the composer's glass, for a host whose visibility doesn't reach glass that lives in another container
    var isGlassHidden = false {
        didSet { applyGlassAppearance() }
    }

    /// The glass that lives in a host's container, and the recording's pause button over it, for the host's hit testing
    var hostedGlassViews: [UIView] {
        guard externalGlassHost != nil else { return [] }
        return [inputBackgroundView, actionGlassView] + (dictationTouchView.isTakingTouches ? [dictationTouchView] : [])
            + (isCancelBubbleShown ? [cancelBubble.view] : [])
    }

    /// While a host animates the field's width, its height keeps the last settled value
    var isHeightUpdateSuspended = false {
        didSet {
            if !isHeightUpdateSuspended { updateInputHeightIfNeeded() }
        }
    }

    /// A thread composer above a docked keyboard: its field widens. The host lays the composer out again in the
    /// keyboard's animation.
    var isAboveKeyboard = false {
        didSet {
            if isAboveKeyboard != oldValue { setNeedsLayout() }
        }
    }

    /// The side inset of a thread composer's field and trailing circle
    var horizontalInset: CGFloat {
        guard style == .thread else { return 0 }
        return isAboveKeyboard ? AgentComposerMetrics.keyboardHorizontalInset : AgentComposerMetrics.threadHorizontalInset
    }

    private var verticalInset: CGFloat {
        style == .thread ? AgentComposerMetrics.threadVerticalInset : 0
    }

    private var glassHost: UIView {
        externalGlassHost ?? glassContainerView?.contentView ?? self
    }

    /// The trailing circle stands apart from an empty field as its microphone, or Stop while an answer can be stopped.
    /// It stays merged into the field while the field has text, with Send in its place, as a question sent during an
    /// answer waits for it, through any dictation into the text, recording, recognizing or failing, so the text never
    /// reflows; and while the field shows the recognition, or the floating microphone records as the one microphone.
    private var shouldSeparateActionButton: Bool {
        !hasText && dictationState.phase != .recognizing && !dictationState.isRecordingFloating
    }

    /// A dictation into a field that already has text, as from the floating microphone, leaves the field as it is: its
    /// text stays in sight and as tall as it is, without the dot, the cross or the recognition's status, while the
    /// floating microphone shows the recording and the field glows as it is recognized. Into an empty field, the
    /// recording strip shows the dot, with the cross hands-free, and the recognition's status.
    private var isDictatingIntoText: Bool {
        isDictating && hasText
    }

    /// While recording hands-free, an empty field keeps its placeholder, or text of nothing but spaces, in sight past
    /// the dot. A recording held on the composer's own microphone shows "Slide to cancel" there instead.
    private static func isFieldTextShown(during state: AgentDictationState) -> Bool {
        state.phase == .handsFree
    }

    /// How far an empty field's placeholder stands in during `state`: hands-free, to the middle of the room past the
    /// dot, where "Slide to cancel" stands while the microphone is held
    private func getRecordingTextInset(for state: AgentDictationState) -> CGFloat {
        guard state.phase == .handsFree else { return 0 }
        return AgentDictationStripView.getCenteredPlaceholderInset(
            placeholderWidth: ceil(placeholderLabel.intrinsicContentSize.width),
            stripWidth: fieldFrame.width - 2 * AgentComposerMetrics.contentHorizontalInset
        )
    }

    /// Recording with the field's text in sight
    private var isFieldTextShownWhileDictating: Bool {
        isDictatingIntoText || isDictating && Self.isFieldTextShown(during: dictationState)
    }

    /// The field shows its placeholder while empty: also while recording hands-free, and while a touch on the
    /// microphone isn't yet a tap or a hold, but not once "Slide to cancel" or the recognition takes its place
    private func isPlaceholderShown(for state: AgentDictationState) -> Bool {
        guard textView.text?.isEmpty ?? true else { return false }
        switch state.phase {
        case .idle, .failed, .handsFree: return true
        case .holding: return state.isFloating || !state.isHeld
        case .recognizing: return false
        }
    }

    /// The field's text in sight, as a recording keeps it
    var isDraftTextShown: Bool {
        !textView.isHidden
    }

    /// The placeholder as it shows, in the composer, or nil while it is hidden
    var placeholderFrame: CGRect? {
        placeholderLabel.isHidden ? nil : placeholderLabel.convert(placeholderLabel.bounds, to: self)
    }

    /// The text's inset at the field's leading end
    var textLeadingInset: CGFloat {
        effectiveUserInterfaceLayoutDirection == .rightToLeft ? textView.textContainerInset.right : textView.textContainerInset.left
    }

    /// Recording or recognizing: the field shows the recording strip, over its text or in its place
    private var isDictating: Bool {
        switch dictationState.phase {
        case .holding, .handsFree, .recognizing: true
        case .idle, .failed: false
        }
    }

    private var hasText: Bool {
        !(textView.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var effectiveActionSeparation: CGFloat {
        let hold = min(1, max(0, actionCircleHold))
        return actionSeparation + (1 - actionSeparation) * hold
    }

    /// The field: the trailing circle's room shrinks as the circle merges into it
    private var fieldFrame: CGRect {
        let reserve = (AgentComposerMetrics.microphoneSize + AgentComposerMetrics.microphoneSpacing) * effectiveActionSeparation
            + max(0, fieldTrailingReserve)
        let height = settledInputHeight
        let width = max(min(height, bounds.width), bounds.width - 2 * horizontalInset - reserve)
        return getDirectionalFrame(CGRect(x: horizontalInset, y: bounds.maxY - verticalInset - height, width: width, height: height))
    }

    /// The trailing circle sits at the trailing end, level with the field's bottom line
    private var actionFrame: CGRect {
        let size = AgentComposerMetrics.microphoneSize
        return getDirectionalFrame(CGRect(
            x: bounds.width - horizontalInset - size,
            y: bounds.maxY - verticalInset - size,
            width: size,
            height: size
        ))
    }

    init(style: Style = .thread) {
        self.style = style
        if #available(iOS 26, iOSApplicationExtension 26, *), IOS_26_MODE_ENABLED {
            let effect = UIGlassContainerEffect()
            effect.spacing = AgentComposerMetrics.glassMergeSpacing
            glassContainerView = UIVisualEffectView(effect: effect)
        } else {
            glassContainerView = nil
        }
        super.init(frame: .zero)
        setupViews()
        applyTheme()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: settledInputHeight + 2 * verticalInset)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        glassContainerView?.frame = bounds
        layoutGlass()
        updateInputHeightIfNeeded()
        updateDictationTouchPosition()
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        applyTheme()
    }

    /// The recording's pause button stands above the composer, where it takes its touches too, and so does the cross
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        super.point(inside: point, with: event)
            || dictationTouchView.point(inside: convert(point, to: dictationTouchView), with: event)
            || isCancelBubbleShown && convert(cancelBubble.view.bounds, from: cancelBubble.view).insetBy(dx: -4, dy: -4).contains(point)
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        // The cross stands above the field, outside the bounds of the glass container it is in
        guard hit === self, externalGlassHost == nil, isCancelBubbleShown else { return hit }
        return cancelBubble.view.hitTest(cancelBubble.view.convert(point, from: self), with: event) ?? hit
    }

    func applyTheme() {
        backgroundColor = AgentComposerMetrics.composerBackgroundColor
        inputBackgroundView.applyEffect()
        actionGlassView.applyEffect()
        textView.textColor = UIColor.label
        textView.tintColor = .tintColor
        placeholderLabel.attributedText = NSAttributedString(string: placeholder, attributes: AgentComposerMetrics.placeholderAttributes)
        dictationStripView.applyTheme()
        dictationTouchView.tintColor = tintColor
        updateActionButtons()
    }

    func setSendEnabled(_ isEnabled: Bool) {
        isSendEnabled = isEnabled
        updateActionButtons()
    }

    /// Offers Stop in the microphone's place while the field is empty, for an answer being written that can be stopped
    func setStopAvailable(_ isAvailable: Bool) {
        guard isAvailable != isStopAvailable else { return }
        isStopAvailable = isAvailable
        updateActionButtons()
    }

    /// The field's text as it shows, for the sent question's bubble to grow out of
    func makeSentTextSource(in container: UIView) -> AgentSentMessageSource? {
        guard let rect = getShownTextRect() else { return nil }
        return AgentSentMessageSource.makeText(of: textView, rect: rect, in: container)
    }

    /// The field's text drawn from its layers, also text set a moment ago, as a transcript sent on release is, for the
    /// bubble of a chat on another screen to grow out of
    func makeSentTextPictureSource(in container: UIView) -> AgentSentMessageSource? {
        textView.layoutIfNeeded()
        textView.layoutManager.ensureLayout(for: textView.textContainer)
        guard let rect = getShownTextRect() else { return nil }
        return AgentSentMessageSource.makeTextPicture(of: textView, rect: rect, in: container)
    }

    /// Where the field's text is, in the text view, while the field shows it
    private func getShownTextRect() -> CGRect? {
        guard !textView.isHidden, hasText else { return nil }
        var used = textView.layoutManager.usedRect(for: textView.textContainer)
        used.origin.x += textView.textContainerInset.left
        used.origin.y += textView.textContainerInset.top
        let rect = used.intersection(textView.bounds)
        return rect.isNull ? nil : rect
    }

    /// Starts a recording that needs no finger on the microphone, as VoiceOver's does
    func startDictationHandsFree() {
        guard let dictationController, dictationState.phase == .idle || dictationState.phase == .failed else { return }
        dictationController.startHandsFree()
    }

    func clearDraft() {
        endTextReveal()
        textView.text = nil
        syncFloatingMicrophone()
        updatePlaceholderVisibility()
        updateInputHeightIfNeeded()
    }

    func setDraftText(_ text: String, focus: Bool) {
        endTextReveal()
        textView.text = text
        syncFloatingMicrophone()
        updatePlaceholderVisibility()
        updateInputHeightIfNeeded()
        onDraftTextChanged?()

        guard focus else { return }
        if !textView.isFirstResponder {
            textView.becomeFirstResponder()
        }
        textView.selectedRange = NSRange(location: text.utf16.count, length: 0)
    }

    /// Puts a transcript in the field after its text, a space apart, character by character, each out of a blur, as
    /// `AgentDictationTextReveal` shows them. With Reduce Motion the text fades in. The field takes no typing and
    /// offers no sending until all of it is in.
    func revealDictatedText(_ text: String) {
        endTextReveal()
        let prefix = Self.getDictationPrefix(before: textView.text ?? "")
        guard window != nil, UIView.areAnimationsEnabled else {
            setDraftText(prefix + text, focus: false)
            return
        }
        guard !UIAccessibility.isReduceMotionEnabled else {
            UIView.transition(
                with: textView,
                duration: Self.glyphFadeDuration,
                options: [.transitionCrossDissolve, .allowUserInteraction]
            ) {
                self.setDraftText(prefix + text, focus: false)
            }
            return
        }
        let reveal = AgentDictationTextReveal(
            text: text,
            after: prefix,
            in: textView,
            onTextGrown: { [weak self] in
                self?.updatePlaceholderVisibility()
                self?.updateInputHeightIfNeeded()
            },
            onFinished: { [weak self] in
                guard let self else { return }
                self.endTextReveal()
                self.updatePlaceholderVisibility()
                self.updateInputHeightIfNeeded()
                self.onDraftTextChanged?()
            }
        )
        textReveal = reveal
        textView.isInputBlocked = true
        updateDictationGlow()
        reveal.start()
    }

    /// The field's text that a transcript goes after: none for blank text, else the text ending in a space
    static func getDictationPrefix(before text: String) -> String {
        guard text.contains(where: { !$0.isWhitespace }) else { return "" }
        return text.last?.isWhitespace == true ? text : text + " "
    }

    /// The floating microphone shows while the field has text, typed, pasted or dictated: the trailing microphone
    /// rises out of its circle into it as the text comes, and it sinks back as the field is emptied, sent or cleared
    private func syncFloatingMicrophone() {
        guard textReveal == nil, let dictationController else { return }
        if hasText {
            dictationController.offerDictatingMore()
        } else {
            dictationController.endDictatingMore()
        }
    }

    /// A held recording's transcript goes as the question at once, as in the Claude app. One that can't be sent yet
    /// stays in the field, with the floating microphone to dictate more.
    private func sendDictatedText(_ text: String) {
        setDraftText(Self.getDictationPrefix(before: textView.text ?? "") + text, focus: false)
        guard isSendEnabled, let onSend else {
            dictationController?.offerDictatingMore()
            return
        }
        onSend()
    }

    private func endTextReveal() {
        guard let textReveal else { return }
        self.textReveal = nil
        textReveal.complete()
        textView.isInputBlocked = isDictating
        updateDictationGlow()
    }

    /// Ends a transcript's reveal at once, as anything that interrupts it does: the field takes focus, its caret or
    /// selection moves, it is typed in, pasted into, sent or cleared, a new dictation starts, the field leaves the
    /// screen or the app goes to the background. All of the transcript shows, sharp and in the text colour.
    @objc private func settleTextReveal() {
        guard textReveal != nil else { return }
        endTextReveal()
        updatePlaceholderVisibility()
        updateInputHeightIfNeeded()
        onDraftTextChanged?()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            settleTextReveal()
        }
    }

    /// The field glows once a recording is finished, while it is recognized and while its words come in, but not while
    /// the user records
    private func updateDictationGlow() {
        let isRecognizing = dictationState.phase == .recognizing
        let isGlowing = isRecognizing || textReveal != nil
        dictationGlowView.setGlowing(isGlowing, animated: window != nil)
        dictationRimView.setGlowing(isGlowing, animated: window != nil)
    }

    /// Moves the field's and the trailing circle's glass into `host`, the content view of a glass container that holds
    /// other glass, so they merge with it. The host must route touches to `hostedGlassViews`; nil brings the glass back.
    func setGlassHost(_ host: UIView?) {
        externalGlassHost = host
        let target = glassHost
        if host != nil {
            // Under the host's own glass: a host whose field the composer's field grows out of keeps the field's
            // content in sight while the two overlap
            if actionGlassView.superview !== target { target.insertSubview(actionGlassView, at: 0) }
            if inputBackgroundView.superview !== target { target.insertSubview(inputBackgroundView, at: 0) }
        } else {
            if inputBackgroundView.superview !== target { target.addSubview(inputBackgroundView) }
            if actionGlassView.superview !== target { target.addSubview(actionGlassView) }
        }
        if cancelBubble.view.superview !== target { target.insertSubview(cancelBubble.view, belowSubview: inputBackgroundView) }
        if host == nil, let glassContainerView {
            // The touch circle stays above the glass, and so does the field's rim
            insertSubview(glassContainerView, belowSubview: dictationTouchView)
            insertSubview(dictationRimView, aboveSubview: glassContainerView)
        }
        layoutGlass()
    }

    /// Places glass that lives in a host's container after the composer moved without resizing
    func layoutHostedGlass() {
        guard externalGlassHost != nil else { return }
        layoutGlass()
    }

    private func setupViews() {
        translatesAutoresizingMaskIntoConstraints = false

        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.backgroundColor = .clear
        textView.applyTextStyle(.body)
        textView.isScrollEnabled = false
        textView.alwaysBounceVertical = false
        textView.keyboardDismissMode = .interactive
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainerInset = UIEdgeInsets(
            top: AgentComposerMetrics.contentVerticalInset,
            left: AgentComposerMetrics.contentHorizontalInset,
            bottom: AgentComposerMetrics.contentVerticalInset,
            right: AgentComposerMetrics.contentHorizontalInset
        )
        textView.returnKeyType = .default
        textView.autocapitalizationType = .sentences
        textView.delegate = self
        textView.accessibilityIdentifier = "agent_input"
        textView.onHardwareSend = { [weak self] in
            guard let self, dictationState.phase == .idle else { return }
            settleTextReveal()
            onSend?()
        }
        // Whatever the user does with the field settles a transcript coming in, rather than leaving it half shown
        textView.onWillEdit = { [weak self] in
            self?.settleTextReveal()
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settleTextReveal),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )

        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.attributedText = NSAttributedString(string: placeholder, attributes: AgentComposerMetrics.placeholderAttributes)
        placeholderLabel.isUserInteractionEnabled = false

        actionContentView.translatesAutoresizingMaskIntoConstraints = false
        microphoneGlyphView.translatesAutoresizingMaskIntoConstraints = false
        microphoneGlyphView.contentMode = .center
        closeGlyphView.translatesAutoresizingMaskIntoConstraints = false
        closeGlyphView.contentMode = .center
        closeGlyphView.tintColor = .label
        closeGlyphView.isHidden = true
        sendHighlightView.translatesAutoresizingMaskIntoConstraints = false
        sendHighlightView.isUserInteractionEnabled = false
        sendHighlightView.layer.cornerRadius = AgentComposerMetrics.sendButtonSize.height / 2
        sendHighlightView.layer.cornerCurve = .continuous
        sendHighlightView.alpha = 0
        sendHighlightView.transform = CGAffineTransform(scaleX: Self.hiddenGlyphScale, y: Self.hiddenGlyphScale)
        sendGlyphView.translatesAutoresizingMaskIntoConstraints = false
        sendGlyphView.contentMode = .center

        sendButton.translatesAutoresizingMaskIntoConstraints = false
        sendButton.isHidden = true
        sendButton.accessibilityLabel = lang("Send")
        sendButton.accessibilityIdentifier = "agent_send"
        sendButton.addTarget(self, action: #selector(sendButtonPressed), for: .touchUpInside)
        sendButton.addTarget(self, action: #selector(sendButtonHighlighted), for: [.touchDown, .touchDragEnter])
        sendButton.addTarget(self, action: #selector(sendButtonUnhighlighted), for: [.touchUpInside, .touchUpOutside, .touchDragExit, .touchCancel])

        microphoneButton.translatesAutoresizingMaskIntoConstraints = false
        microphoneButton.accessibilityIdentifier = "agent_microphone"
        microphoneButton.onAccessibilityActivate = { [weak self] in
            guard let self else { return false }
            if self.isStopDisplayed {
                self.onStop?()
                return true
            }
            guard let dictationController = self.dictationController else { return false }
            switch self.dictationState.phase {
            case .handsFree:
                dictationController.finish()
            case .idle, .failed:
                guard self.shouldStartDictation?() != false else { return true }
                self.isDictationStartedWithVoiceOver = true
                dictationController.startHandsFree()
            case .holding, .recognizing:
                return false
            }
            return true
        }
        microphoneButton.addTarget(self, action: #selector(actionButtonPressed), for: .touchUpInside)
        microphoneGestureRecognizer.minimumPressDuration = 0
        microphoneGestureRecognizer.allowableMovement = .greatestFiniteMagnitude
        microphoneGestureRecognizer.addTarget(self, action: #selector(handleMicrophoneGesture(_:)))
        microphoneButton.addGestureRecognizer(microphoneGestureRecognizer)

        dictationStripView.translatesAutoresizingMaskIntoConstraints = false
        dictationStripView.isHidden = true
        dictationStripView.onCancel = { [weak self] in
            self?.dictationController?.cancel()
        }
        dictationTouchView.isHidden = true
        cancelBubble.button.addTarget(self, action: #selector(cancelBubblePressed), for: .touchUpInside)
        dictationTouchView.onResume = { [weak self] in
            self?.dictationController?.startHandsFree(isFloating: true)
        }
        dictationTouchView.onFloatingTouchBegan = { [weak self] in
            guard let self else { return }
            self.dictationController?.touchBegan(
                isRightToLeft: self.effectiveUserInterfaceLayoutDirection == .rightToLeft,
                isFloating: true
            )
        }
        dictationTouchView.onFloatingTouchEnded = { [weak self] in
            self?.dictationController?.touchEnded()
        }
        dictationTouchView.onFloatingStop = { [weak self] in
            self?.dictationController?.finish()
        }
        // The floating microphone sinking into the trailing circle becomes its microphone as it lands, so the circle
        // shows none of its own meanwhile
        dictationTouchView.onMicrophonePlaceChanged = { [weak self] in
            guard let self else { return }
            actionContentView.layer.removeAnimation(forKey: "opacity")
            UIView.performWithoutAnimation { self.applyGlassAppearance() }
        }

        dismissPanGestureRecognizer.addTarget(self, action: #selector(handleDismissPan(_:)))
        dismissPanGestureRecognizer.cancelsTouchesInView = false
        dismissPanGestureRecognizer.delegate = self
        inputBackgroundView.addGestureRecognizer(dismissPanGestureRecognizer)

        if let glassContainerView {
            addSubview(glassContainerView)
        }
        glassHost.addSubview(cancelBubble.view)
        glassHost.addSubview(inputBackgroundView)
        glassHost.addSubview(actionGlassView)
        dictationRimView.cornerRadius = AgentComposerMetrics.inputCornerRadius
        dictationRimView.field = inputBackgroundView
        addSubview(dictationRimView)
        dictationGlowView.frame = inputBackgroundView.contentView.bounds
        dictationGlowView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        dictationGlowView.cornerRadius = AgentComposerMetrics.inputCornerRadius
        inputBackgroundView.contentView.addSubview(dictationGlowView)
        inputBackgroundView.contentView.addSubview(textView)
        inputBackgroundView.contentView.addSubview(placeholderLabel)
        inputBackgroundView.contentView.addSubview(dictationStripView)
        actionGlassView.contentView.addSubview(actionContentView)
        actionContentView.addSubview(microphoneGlyphView)
        actionContentView.addSubview(closeGlyphView)
        actionContentView.addSubview(microphoneButton)
        inputBackgroundView.contentView.addSubview(sendHighlightView)
        sendHighlightView.addSubview(sendGlyphView)
        inputBackgroundView.contentView.addSubview(sendButton)
        addSubview(dictationTouchView)
        addLayoutGuide(inputTopGuide)

        let field = inputBackgroundView.contentView
        let action = actionGlassView.contentView
        NSLayoutConstraint.activate([
            inputTopGuide.topAnchor.constraint(equalTo: topAnchor, constant: verticalInset),
            inputTopGuide.heightAnchor.constraint(equalToConstant: 0),
            inputTopGuide.leadingAnchor.constraint(equalTo: leadingAnchor),
            inputTopGuide.trailingAnchor.constraint(equalTo: trailingAnchor),

            textView.leadingAnchor.constraint(equalTo: field.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: field.trailingAnchor),
            textView.topAnchor.constraint(equalTo: field.topAnchor),
            textView.bottomAnchor.constraint(equalTo: field.bottomAnchor),

            placeholderLeadingConstraint,
            placeholderTrailingConstraint,
            placeholderLabel.topAnchor.constraint(
                equalTo: field.topAnchor,
                constant: AgentComposerMetrics.contentVerticalInset
            ),

            actionContentView.leadingAnchor.constraint(equalTo: action.leadingAnchor),
            actionContentView.trailingAnchor.constraint(equalTo: action.trailingAnchor),
            actionContentView.topAnchor.constraint(equalTo: action.topAnchor),
            actionContentView.bottomAnchor.constraint(equalTo: action.bottomAnchor),

            microphoneGlyphView.centerXAnchor.constraint(equalTo: actionContentView.centerXAnchor),
            microphoneGlyphView.centerYAnchor.constraint(equalTo: actionContentView.centerYAnchor),
            closeGlyphView.centerXAnchor.constraint(equalTo: actionContentView.centerXAnchor),
            closeGlyphView.centerYAnchor.constraint(equalTo: actionContentView.centerYAnchor),

            // The send button keeps to the field's bottom line as the text grows above it, as in Telegram
            sendHighlightView.trailingAnchor.constraint(equalTo: field.trailingAnchor, constant: -AgentComposerMetrics.sendButtonInset),
            sendHighlightView.bottomAnchor.constraint(equalTo: field.bottomAnchor, constant: -AgentComposerMetrics.sendButtonInset),
            sendHighlightView.widthAnchor.constraint(equalToConstant: AgentComposerMetrics.sendButtonSize.width),
            sendHighlightView.heightAnchor.constraint(equalToConstant: AgentComposerMetrics.sendButtonSize.height),
            sendGlyphView.centerXAnchor.constraint(equalTo: sendHighlightView.centerXAnchor),
            sendGlyphView.centerYAnchor.constraint(equalTo: sendHighlightView.centerYAnchor),

            microphoneButton.leadingAnchor.constraint(equalTo: actionContentView.leadingAnchor),
            microphoneButton.trailingAnchor.constraint(equalTo: actionContentView.trailingAnchor),
            microphoneButton.topAnchor.constraint(equalTo: actionContentView.topAnchor),
            microphoneButton.bottomAnchor.constraint(equalTo: actionContentView.bottomAnchor),

            // A touch target a little larger than the capsule, to the field's edge
            sendButton.leadingAnchor.constraint(equalTo: sendHighlightView.leadingAnchor, constant: -6),
            sendButton.trailingAnchor.constraint(equalTo: field.trailingAnchor),
            sendButton.topAnchor.constraint(equalTo: sendHighlightView.topAnchor, constant: -6),
            sendButton.bottomAnchor.constraint(equalTo: field.bottomAnchor),

            dictationStripView.leadingAnchor.constraint(equalTo: field.leadingAnchor, constant: AgentComposerMetrics.contentHorizontalInset),
            dictationStripView.trailingAnchor.constraint(equalTo: field.trailingAnchor, constant: -AgentComposerMetrics.contentHorizontalInset),
            dictationStripView.topAnchor.constraint(equalTo: field.topAnchor),
            dictationStripView.bottomAnchor.constraint(equalTo: field.bottomAnchor),
        ])

        updatePlaceholderVisibility()
        updateInputHeightIfNeeded()
    }

    /// Places the field and the trailing circle in their glass host
    private func layoutGlass() {
        let host = glassHost
        // A host's ancestors may be moving away, such as a toolbar sliding off with a navigation transition; the
        // glass rides along with them instead of being pinned against their motion
        let origin = Self.getUntransformedOrigin(of: self)
        let hostOrigin = Self.getUntransformedOrigin(of: host)
        let dx = origin.x - hostOrigin.x
        let dy = origin.y - hostOrigin.y
        let fieldOffset = effectiveUserInterfaceLayoutDirection == .rightToLeft ? -fieldHandoffOffset : fieldHandoffOffset
        place(inputBackgroundView, frame: fieldFrame.offsetBy(dx: dx + fieldOffset, dy: dy))
        place(actionGlassView, frame: actionFrame.offsetBy(dx: dx, dy: dy), swell: actionSwapSwell, shouldResize: true)
        place(cancelBubble.view, frame: cancelBubbleFrame.offsetBy(dx: dx, dy: dy), shouldResize: true)
        let rimMargin = AgentFieldGlowView.rimMargin
        // Set at once, as the rim's drawing doesn't stretch with an animated frame; while it glows it follows the field
        // as the field shows, frame by frame
        UIView.performWithoutAnimation {
            dictationRimView.frame = convert(inputBackgroundView.bounds, from: inputBackgroundView)
                .insetBy(dx: -rimMargin, dy: -rimMargin)
        }
        applyGlassAppearance()
    }

    /// Moves the field toward the trailing edge, past the circle beside it, for a host's handoff
    var fieldHandoffOffset: CGFloat = 0 {
        didSet {
            if fieldHandoffOffset != oldValue { layoutGlass() }
        }
    }

    /// Turns the trailing circle's microphone into a close cross, for a host whose close button takes its place:
    /// 0 shows the microphone, 1 the cross. The circle swells through the swap as the bar's morphing glass does,
    /// settling with the spring's slight bounce, while the leaving glyph shrinks away as the arriving one grows in, as
    /// the header capsules swap their content.
    var actionGlyphSwap: CGFloat = 0 {
        didSet {
            guard actionGlyphSwap != oldValue else { return }
            let swap = min(1, max(0, actionGlyphSwap))
            let hidden = GlassMotion.matchScale
            microphoneGlyphView.alpha = 1 - swap
            microphoneGlyphView.transform = CGAffineTransform(scaleX: 1 + (hidden - 1) * swap, y: 1 + (hidden - 1) * swap)
            closeGlyphView.isHidden = swap <= 0
            closeGlyphView.alpha = swap
            let closeScale = hidden + (1 - hidden) * swap
            closeGlyphView.transform = CGAffineTransform(scaleX: closeScale, y: closeScale)
            layoutGlass()
        }
    }

    /// The circle's swell through the glyph swap, slightly under its size while the spring overshoots
    private var actionSwapSwell: CGFloat {
        actionGlyphSwap == 0 ? 1 : AgentListBottomBar.swell(at: min(1.15, max(-0.1, actionGlyphSwap)))
    }

    /// Where `view`'s coordinate space starts in its window's, as if no view were transformed
    private static func getUntransformedOrigin(of view: UIView) -> CGPoint {
        var origin = CGPoint.zero
        var current = view
        while let superview = current.superview {
            let anchor = current.layer.anchorPoint
            origin.x += current.center.x - current.bounds.width * anchor.x - current.bounds.minX
            origin.y += current.center.y - current.bounds.height * anchor.y - current.bounds.minY
            current = superview
        }
        return origin
    }

    /// `shouldResize` scales the view by its size rather than by a transform, which glass in a host's container doesn't
    /// take its shape from; its content keeps its size
    private func place(_ view: UIView, frame: CGRect, swell: CGFloat = 1, shouldResize: Bool = false) {
        view.transform = .identity
        let scale = glassScale * swell
        let size = shouldResize ? CGSize(width: frame.width * scale, height: frame.height * scale) : frame.size
        view.bounds = CGRect(origin: .zero, size: size)
        view.center = CGPoint(x: frame.midX, y: frame.midY)
        if !shouldResize, scale != 1 {
            view.transform = CGAffineTransform(scaleX: scale, y: scale)
        }
    }

    private func applyGlassAppearance() {
        let separation = effectiveActionSeparation
        // The glyph appears once the circle has mostly left the field
        let glyphAlpha = min(1, max(0, (separation - 0.35) / 0.65))
        // One microphone at a time: none in the circle while the floating one is up or sinking into it, though Stop shows
        let isMicrophoneAway = !isStopDisplayed && (dictationTouchView.isMicrophoneUp || dictationTouchView.isSinking)
        actionContentView.alpha = isMicrophoneAway ? 0 : contentAlpha * glyphAlpha
        inputBackgroundView.isHidden = isGlassHidden
        // Glass doesn't fade with its alpha, and neither does blur; they materialize instead
        let isMaterialized = glassAlpha > 0.01
        inputBackgroundView.setMaterialized(isMaterialized)
        let canMergeWithField = glassContainerView != nil || externalGlassHost != nil
        // While the finger holds the recording, the recording circle grows from where the microphone's circle was;
        // the circle's pressed glass would ring the small recording circle with its edge. Blur that can't merge
        // with the field's comes in once the circle has mostly left the field, rather than darkening it where the
        // two overlap.
        actionGlassView.setMaterialized(
            isMaterialized && !(dictationState.phase == .holding && dictationState.isHeld && !dictationState.isFloating)
                && (canMergeWithField || separation > 0.5)
        )
        if canMergeWithField {
            // Merged into the field, the circle is part of the field's glass
            actionGlassView.isHidden = isGlassHidden || separation < 0.01
            actionGlassView.isUserInteractionEnabled = true
        } else {
            // The circle's blur fades out as it goes into the field, where it leaves the touches to the field
            actionGlassView.isHidden = isGlassHidden
            actionGlassView.isUserInteractionEnabled = separation > 0.01
        }
    }

    private func getDirectionalFrame(_ frame: CGRect) -> CGRect {
        guard effectiveUserInterfaceLayoutDirection == .rightToLeft else { return frame }
        return CGRect(x: bounds.width - frame.maxX, y: frame.minY, width: frame.width, height: frame.height)
    }

    private func updateActionSeparation(animated: Bool) {
        let target: CGFloat = shouldSeparateActionButton ? 1 : 0
        guard target != actionSeparation else { return }
        actionSeparation = target
        guard animated, window != nil, UIView.areAnimationsEnabled, !UIAccessibility.isReduceMotionEnabled else {
            layoutGlass()
            updateInputHeightIfNeeded()
            return
        }
        UIView.animate(
            withDuration: AgentComposerMetrics.actionSeparationDuration,
            delay: 0,
            usingSpringWithDamping: AgentComposerMetrics.actionSeparationDamping,
            initialSpringVelocity: 0,
            options: [.beginFromCurrentState, .allowUserInteraction]
        ) {
            self.layoutGlass()
            self.inputBackgroundView.layoutIfNeeded()
        }
        updateInputHeightIfNeeded()
    }

    @objc private func sendButtonPressed() {
        settleTextReveal()
        onSend?()
    }

    /// Telegram dims the send button while it is pressed and brings it back over 0.2 s
    @objc private func sendButtonHighlighted() {
        sendHighlightView.layer.removeAnimation(forKey: "opacity")
        sendHighlightView.alpha = Self.highlightedSendAlpha
    }

    @objc private func sendButtonUnhighlighted() {
        // A sent message hides the button; it stays hidden
        guard isSendDisplayed, sendHighlightView.alpha < 1 else { return }
        UIView.animate(withDuration: Self.glyphFadeDuration, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.sendHighlightView.alpha = 1
        }
    }

    @objc private func actionButtonPressed() {
        if isStopDisplayed {
            onStop?()
            return
        }
        guard dictationState.phase == .handsFree else { return }
        dictationController?.finish()
    }

    @objc private func handleMicrophoneGesture(_ gestureRecognizer: UILongPressGestureRecognizer) {
        // Starting a recording can shrink and move the composer under the finger.
        let point = gestureRecognizer.location(in: window)
        let now = CACurrentMediaTime()
        switch gestureRecognizer.state {
        case .began:
            guard shouldStartDictation?() != false else {
                // The press ends here; the host starts the recording once it may
                gestureRecognizer.isEnabled = false
                gestureRecognizer.isEnabled = true
                return
            }
            microphoneTouchOrigin = point
            microphoneLastSample = (point, now)
            microphoneVelocity = .zero
            dictationController?.touchBegan(isRightToLeft: effectiveUserInterfaceLayoutDirection == .rightToLeft)
        case .changed:
            trackMicrophoneVelocity(point: point, time: now)
            dictationController?.touchMoved(
                x: Double(point.x - microphoneTouchOrigin.x),
                y: Double(point.y - microphoneTouchOrigin.y)
            )
        case .ended:
            trackMicrophoneVelocity(point: point, time: now)
            dictationController?.touchEnded(
                x: Double(point.x - microphoneTouchOrigin.x),
                y: Double(point.y - microphoneTouchOrigin.y),
                velocityX: Double(microphoneVelocity.x),
                velocityY: Double(microphoneVelocity.y)
            )
        case .cancelled, .failed:
            // Pausing and automatic recognition disable the active recognizer.
            if dictationState.phase == .holding || dictationState.phase == .idle {
                dictationController?.cancel()
            }
        default:
            break
        }
    }

    private func trackMicrophoneVelocity(point: CGPoint, time: CFTimeInterval) {
        defer { microphoneLastSample = (point, time) }
        guard let sample = microphoneLastSample, time - sample.time > 0.001 else { return }
        let interval = CGFloat(time - sample.time)
        let instant = CGPoint(x: (point.x - sample.point.x) / interval, y: (point.y - sample.point.y) / interval)
        microphoneVelocity = CGPoint(x: microphoneVelocity.x * 0.4 + instant.x * 0.6, y: microphoneVelocity.y * 0.4 + instant.y * 0.6)
    }

    private func updateDictationState(_ state: AgentDictationState) {
        let previousPhase = dictationState.phase
        let wasHoldShown = previousPhase == .holding && dictationState.isHeld
        let couldDictateMore = dictationState.canDictateMore
        // As in Telegram, the field's placeholder fades out as "Slide to cancel" comes in
        let placeholderSnapshot = !placeholderLabel.isHidden && !isPlaceholderShown(for: state) && state.phase != .idle
            && window != nil && UIView.areAnimationsEnabled && !UIAccessibility.isReduceMotionEnabled
            ? placeholderLabel.snapshotView(afterScreenUpdates: false)
            : nil
        dictationState = state
        if state.phase == .holding || state.phase == .handsFree {
            settleTextReveal()
        }
        // The microphone's circle gives way to the recording circle once the touch is a hold
        let isHoldShown = state.phase == .holding && state.isHeld
        if wasHoldShown != isHoldShown {
            if isHoldShown || window == nil || !UIView.areAnimationsEnabled {
                UIView.performWithoutAnimation { applyGlassAppearance() }
            } else {
                // Back under the recording circle as it goes, the microphone's circle materializes again
                UIView.animate(withDuration: 0.3, delay: 0, options: [.beginFromCurrentState, .curveEaseOut]) {
                    self.applyGlassAppearance()
                }
            }
        }
        let isDictating = self.isDictating
        textView.isInputBlocked = isDictating || textReveal != nil
        textView.isHidden = isDictating && !isFieldTextShownWhileDictating
        // Shown before its update, so its dot and hint come in, and hidden after it, so they leave as they showed
        let isStripShown = isDictating && !isDictatingIntoText
        if isStripShown { dictationStripView.isHidden = false }
        dictationStripView.update(state)
        if !isStripShown { dictationStripView.isHidden = true }
        // The field's content makes room for the cross and the dot as they come in, and takes it back as they go
        setRecordingTextInset(
            isDictatingIntoText ? 0 : getRecordingTextInset(for: state),
            animated: window != nil && UIView.areAnimationsEnabled && !UIAccessibility.isReduceMotionEnabled
        )
        // No caret blinks in the field while it records or recognizes; the field keeps the keyboard
        textView.tintColor = isDictating ? .clear : nil
        setCancelBubbleShown(state.phase == .handsFree)
        updateDictationTouchPosition()
        // With Stop in the trailing circle, the floating microphone comes and goes where it rests
        dictationTouchView.isTrailingMicrophoneShown = !isStopAvailable
        dictationTouchView.update(state, isRightToLeft: effectiveUserInterfaceLayoutDirection == .rightToLeft)
        let wasPlaceholderHidden = placeholderLabel.isHidden
        updatePlaceholderVisibility()
        if previousPhase == .holding, wasPlaceholderHidden, !placeholderLabel.isHidden {
            bringPlaceholderBack()
        }
        if let placeholderSnapshot, placeholderLabel.isHidden, let container = placeholderLabel.superview {
            placeholderSnapshot.frame = placeholderLabel.frame
            container.insertSubview(placeholderSnapshot, aboveSubview: placeholderLabel)
            // Telegram's input panel transition: 0.4 s on its list curve
            let fade = UIViewPropertyAnimator(duration: 0.4, timingParameters: AgentComposerMetrics.makeTelegramCubicTiming())
            fade.addAnimations { placeholderSnapshot.alpha = 0 }
            fade.addCompletion { _ in placeholderSnapshot.removeFromSuperview() }
            fade.startAnimation()
        }
        updateDictationTouchPosition()
        updateRecordingCircleVisibility()
        updateDictationGlow()
        if state.phase != previousPhase {
            if state.phase == .failed, state.failure == .microphoneDenied {
                AppActions.showToast(ToastConfig(
                    style: .overlay, icon: .symbolImage("mic.slash"),
                    message: lang("$agent_dictation_microphone_denied_device"), duration: 5, transition: .scale,
                    actionTitle: lang("Open Settings"),
                    action: {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        UIApplication.shared.open(url)
                    }
                ))
            }
            updateInputHeightIfNeeded()
            if state.phase == .handsFree && !state.isFloating && !isDictationStartedWithVoiceOver {
                UIAccessibility.post(notification: .layoutChanged, argument: microphoneButton)
            } else if state.phase == .handsFree && state.isFloating {
                UIAccessibility.post(notification: .layoutChanged, argument: dictationTouchView)
            } else if state.phase == .recognizing {
                UIAccessibility.post(
                    notification: .layoutChanged,
                    argument: isDictatingIntoText ? textView : dictationStripView.cancelAccessibilityElement
                )
            } else if previousPhase == .recognizing, state.phase == .idle {
                UIAccessibility.post(notification: .layoutChanged, argument: textView)
            } else if state.phase == .failed, let failure = state.failure, UIAccessibility.isVoiceOverRunning {
                UIAccessibility.post(notification: .announcement, argument: failure.accessibilityAnnouncement)
            }
        }
        if state.phase == .idle {
            isDictationStartedWithVoiceOver = false
        }
        // A touch turning out a hold changes what the field shows as much as a new phase does
        if state.phase != previousPhase || state.canDictateMore != couldDictateMore || isHoldShown != wasHoldShown {
            onDictationPhaseChanged?()
        }
    }

    /// As "Slide to cancel" goes, after a held recording or a tap, the placeholder comes back the way the hint took its
    /// place: in from the trailing side as it fades in, on the strip's timing. With Reduce Motion it fades in.
    private func bringPlaceholderBack() {
        guard window != nil, UIView.areAnimationsEnabled else { return }
        let isMotionReduced = UIAccessibility.isReduceMotionEnabled
        let isRightToLeft = effectiveUserInterfaceLayoutDirection == .rightToLeft
        let distance = (fieldFrame.width - 2 * AgentComposerMetrics.contentHorizontalInset) * 0.3
        placeholderLabel.alpha = 0
        placeholderLabel.transform = isMotionReduced ? .identity : CGAffineTransform(translationX: isRightToLeft ? -distance : distance, y: 0)
        let animator = UIViewPropertyAnimator(
            duration: AgentDictationStripView.slideDuration,
            timingParameters: AgentComposerMetrics.makeTelegramCubicTiming()
        )
        animator.addAnimations {
            self.placeholderLabel.alpha = 1
            self.placeholderLabel.transform = .identity
        }
        animator.startAnimation()
    }

    /// Where the cross stands: above the field's leading end, opposite where the floating microphone rests, or, before it
    /// splits off and once it has merged back, in the field's rounded leading end, inside the field's glass
    private var cancelBubbleFrame: CGRect {
        let side = AgentDictationCancelBubble.diameter
        let field = fieldFrame
        guard !isCancelBubbleOut else {
            let centerX = bounds.width - actionFrame.midX
            let maxY = field.minY - AgentVCLayout.scrollToBottomButtonSpacing
            return CGRect(x: centerX - side / 2, y: maxY - side, width: side, height: side)
        }
        let endRadius = AgentComposerMetrics.minInputHeight / 2
        let isRightToLeft = effectiveUserInterfaceLayoutDirection == .rightToLeft
        let centerX = isRightToLeft ? field.maxX - endRadius : field.minX + endRadius
        let centerY = field.maxY - endRadius
        return CGRect(x: centerX - side / 2, y: centerY - side / 2, width: side, height: side)
    }

    /// The cross comes as a hands-free recording starts and goes as it ends. Its Liquid Glass splits off the field's
    /// leading end through the glass container they share and rises above the field on the trailing circle's spring, as
    /// iOS 26 bars separate their buttons, the cross showing once it is mostly out; it merges back into the field the
    /// same way. Without Liquid Glass it grows in and shrinks away as the scroll-to-bottom button does. With Reduce
    /// Motion it fades in and out where it stands.
    func setCancelBubbleShown(_ isShown: Bool, isReduceMotionEnabled: Bool = UIAccessibility.isReduceMotionEnabled) {
        guard isShown != isCancelBubbleShown else { return }
        isCancelBubbleShown = isShown
        cancelBubbleGeneration += 1
        let generation = cancelBubbleGeneration
        let bubble = cancelBubble
        if isShown {
            bubble.view.isHidden = false
        }
        guard window != nil, UIView.areAnimationsEnabled else {
            UIView.performWithoutAnimation {
                isCancelBubbleOut = true
                layoutGlass()
                bubble.setShown(isShown)
            }
            bubble.view.isHidden = !isShown
            return
        }
        let options: UIView.AnimationOptions = [.beginFromCurrentState, .allowUserInteraction]
        guard !isReduceMotionEnabled, bubble.glassView != nil else {
            let isScaling = !isReduceMotionEnabled
            UIView.performWithoutAnimation {
                isCancelBubbleOut = true
                layoutGlass()
                if isShown { bubble.setShown(false, isScaling: isScaling) }
            }
            if isScaling {
                UIView.animate(
                    withDuration: AgentScrollToBottomButton.animationDuration, delay: 0, usingSpringWithDamping: 1,
                    initialSpringVelocity: 0, options: options
                ) {
                    bubble.setShown(isShown, isScaling: true)
                } completion: { [weak self] _ in self?.hideCancelBubble(after: generation) }
            } else {
                UIView.animate(withDuration: Self.cancelBubbleFadeDuration, delay: 0, options: options) {
                    bubble.setShown(isShown)
                } completion: { [weak self] _ in self?.hideCancelBubble(after: generation) }
            }
            return
        }
        if isShown {
            UIView.performWithoutAnimation {
                isCancelBubbleOut = false
                layoutGlass()
                bubble.setShown(true)
                bubble.button.alpha = 0
            }
        }
        isCancelBubbleOut = isShown
        UIView.animate(
            withDuration: AgentComposerMetrics.actionSeparationDuration, delay: 0,
            usingSpringWithDamping: AgentComposerMetrics.actionSeparationDamping, initialSpringVelocity: 0, options: options
        ) {
            self.layoutGlass()
        } completion: { [weak self] _ in self?.hideCancelBubble(after: generation) }
        // The cross shows once its glass has mostly left the field's, and is gone before the glass is back in
        UIView.animate(withDuration: isShown ? 0.2 : 0.12, delay: isShown ? 0.15 : 0, options: options) {
            bubble.button.alpha = isShown ? 1 : 0
        }
    }

    private static let cancelBubbleFadeDuration: TimeInterval = 0.25

    /// Out of sight once gone, unless it was shown again since
    private func hideCancelBubble(after generation: Int) {
        guard cancelBubbleGeneration == generation, !isCancelBubbleShown else { return }
        cancelBubble.view.isHidden = true
    }

    @objc private func cancelBubblePressed() {
        guard isCancelBubbleShown else { return }
        dictationController?.cancel()
    }

    private func updateRecordingCircleVisibility() {
        let phase = dictationState.phase
        // The circle shows once the touch is a tap or a hold
        let isVisible = phase == .holding && dictationState.isHeld || phase == .handsFree || phase == .failed
        guard isVisible != isRecordingCircleVisible else { return }
        isRecordingCircleVisible = isVisible
        onRecordingCircleVisibilityChanged?()
    }

    private func updateActionButtons() {
        let phase = dictationState.phase
        let hasDictation = dictationController != nil
        // A recording on the floating microphone has its stop there, while the trailing circle is merged into the field
        let isHandsFree = phase == .handsFree && !dictationState.isFloating
        let isRecording = (phase == .holding || phase == .handsFree) && !dictationState.isFloating
        // Stop with an empty field while an answer can be stopped, Send with text, as Android has them: a question sent
        // during the answer waits for it. Send keeps its place whatever a dictation into the text does.
        let mode: ActionMode = hasText ? .send : .microphone
        let isSeparate = shouldSeparateActionButton
        let wasStopDisplayed = isStopDisplayed
        isStopDisplayed = isStopAvailable && phase == .idle && mode == .microphone
        sendButton.isHidden = mode != .send
        sendButton.isEnabled = isSendEnabled
        // It sends nothing while a dictation into the text goes on, with no change to how it looks
        sendButton.isUserInteractionEnabled = !isDictating
        microphoneButton.isHidden = mode != .microphone || !isSeparate
        microphoneButton.isEnabled = hasDictation || isStopDisplayed
        microphoneButton.accessibilityLabel = lang(
            isStopDisplayed ? "$agent_stop_answer" : isHandsFree ? "$agent_dictation_finish" : "$agent_dictation_start"
        )
        microphoneButton.accessibilityIdentifier = isStopDisplayed ? "agent_stop" : "agent_microphone"

        microphoneGestureRecognizer.isEnabled = hasDictation && !isStopDisplayed
            && (phase == .idle || phase == .holding || phase == .failed)

        // An answer that ends under a draft merges the circle into the field for Send with Stop's glyph, so the
        // microphone never shows in between; the circle comes back out of the field as the microphone
        let isStopGlyph = phase == .idle
            && (isStopAvailable || mode == .send && displayedActionGlyph === Self.stopImage)
        let microphoneImage = isHandsFree ? Self.stopImage : isStopGlyph ? Self.stopImage : Self.microphoneImage
        if displayedActionGlyph !== microphoneImage {
            displayedActionGlyph = microphoneImage
            if isStopDisplayed != wasStopDisplayed, window != nil, UIView.areAnimationsEnabled {
                swapActionGlyph(to: microphoneImage)
            } else {
                microphoneGlyphView.image = microphoneImage
            }
        }
        // Telegram's idle microphone is a plain grey glyph; the recording circle covers it while recording
        microphoneGlyphView.tintColor = isRecording ? tintColor.foregroundForTintedBackground : Self.idleMicrophoneColor
        let canAnimate = window != nil && UIView.areAnimationsEnabled
        // The hands-free recording's stop sits on accent-tinted glass; otherwise the circle is clear glass
        let tint: UIColor? = isHandsFree ? tintColor : nil
        if tint != displayedActionTint {
            displayedActionTint = tint
            applyActionTint(tint, animated: canAnimate)
        }
        applySendAppearance(isVisible: mode == .send, animated: canAnimate)
        updateActionSeparation(animated: true)
    }

    /// The microphone and Stop turn into each other in the trailing circle as the symbols' replace transition shows
    /// them: the leaving glyph shrinks away as the arriving one grows in, or the two cross-fade with Reduce Motion.
    /// Both are the circle's own views, so the swap goes with the circle, also as the composer moves with the keyboard
    /// that a sent question closes in the same pass. The symbols' own transition would keep the leaving glyph as far
    /// from the circle as the composer moves in that pass.
    private func swapActionGlyph(to image: UIImage?) {
        leavingActionGlyphView?.removeFromSuperview()
        leavingActionGlyphView = nil
        microphoneGlyphView.layer.removeAnimation(forKey: Self.glyphArrivalScaleKey)
        guard let leavingImage = microphoneGlyphView.image, !actionContentView.bounds.isEmpty else {
            microphoneGlyphView.image = image
            return
        }
        let leavingView = UIImageView(image: leavingImage)
        leavingView.contentMode = .center
        leavingView.tintColor = microphoneGlyphView.tintColor
        leavingView.isUserInteractionEnabled = false
        // Centred in the circle as the circle's size changes, as the arriving glyph is
        leavingView.autoresizingMask = [
            .flexibleLeftMargin, .flexibleRightMargin, .flexibleTopMargin, .flexibleBottomMargin,
        ]
        UIView.performWithoutAnimation {
            leavingView.center = CGPoint(x: actionContentView.bounds.midX, y: actionContentView.bounds.midY)
            leavingView.transform = microphoneGlyphView.transform
            leavingView.alpha = microphoneGlyphView.alpha
            actionContentView.insertSubview(leavingView, aboveSubview: microphoneGlyphView)
        }
        leavingActionGlyphView = leavingView
        microphoneGlyphView.image = image

        // The arriving glyph's animations add to its own transform and opacity, which a host's swap to the close cross
        // sets
        let isMotionReduced = UIAccessibility.isReduceMotionEnabled
        let fadeIn = CABasicAnimation(keyPath: "opacity")
        fadeIn.isAdditive = true
        fadeIn.fromValue = -1
        fadeIn.toValue = 0
        fadeIn.duration = Self.glyphFadeDuration
        fadeIn.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        microphoneGlyphView.layer.add(fadeIn, forKey: Self.glyphArrivalFadeKey)
        if !isMotionReduced {
            let grow = CASpringAnimation(keyPath: "transform.scale")
            grow.isAdditive = true
            grow.mass = 1
            grow.stiffness = AgentComposerMetrics.telegramSpringStiffness
            grow.damping = AgentComposerMetrics.telegramSpringDamping
            grow.fromValue = GlassMotion.matchScale - 1
            grow.toValue = 0
            grow.duration = grow.settlingDuration
            microphoneGlyphView.layer.add(grow, forKey: Self.glyphArrivalScaleKey)
        }
        let leave = UIViewPropertyAnimator(duration: Self.glyphFadeDuration, curve: .easeIn) {
            leavingView.alpha = 0
            if !isMotionReduced {
                let scale = GlassMotion.matchScale
                leavingView.transform = leavingView.transform.scaledBy(x: scale, y: scale)
            }
        }
        leave.addCompletion { [weak self, weak leavingView] _ in
            leavingView?.removeFromSuperview()
            guard let self, leavingActionGlyphView === leavingView else { return }
            leavingActionGlyphView = nil
        }
        leave.startAnimation()
    }

    private func applyActionTint(_ tint: UIColor?, animated: Bool) {
        guard animated else {
            actionGlassView.setTint(tint)
            return
        }
        let animator = UIViewPropertyAnimator(
            duration: Self.actionTransitionDuration,
            timingParameters: AgentComposerMetrics.makeTelegramSpring()
        )
        animator.addAnimations {
            self.actionGlassView.setTint(tint)
        }
        animator.startAnimation()
    }

    /// The send button inside the field: an accent capsule with a white arrow, or a quiet one while sending isn't
    /// possible. It grows in at the field's end on Telegram's layout spring as the microphone circle merges into the
    /// field, and the text makes room for it.
    private func applySendAppearance(isVisible: Bool, animated: Bool) {
        sendHighlightView.backgroundColor = isSendEnabled ? tintColor : Self.disabledSendBackgroundColor
        sendGlyphView.tintColor = isSendEnabled ? tintColor.foregroundForTintedBackground : Self.disabledSendForegroundColor
        textTrailingInset = isVisible ? AgentComposerMetrics.sendButtonReserve : AgentComposerMetrics.contentHorizontalInset
        applyTextInsets()
        guard isVisible != isSendDisplayed else { return }
        isSendDisplayed = isVisible
        for animator in glyphAnimators where animator.state == .active {
            animator.stopAnimation(true)
        }
        glyphAnimators = []
        let hiddenTransform = UIAccessibility.isReduceMotionEnabled
            ? .identity
            : CGAffineTransform(scaleX: Self.hiddenGlyphScale, y: Self.hiddenGlyphScale)
        let apply = {
            self.sendHighlightView.transform = isVisible ? .identity : hiddenTransform
        }
        let fade = {
            self.sendHighlightView.alpha = isVisible ? 1 : 0
        }
        guard animated else {
            apply()
            fade()
            return
        }
        let spring = UIViewPropertyAnimator(
            duration: Self.actionTransitionDuration,
            timingParameters: AgentComposerMetrics.makeTelegramSpring()
        )
        spring.addAnimations(apply)
        let fader = UIViewPropertyAnimator(duration: Self.glyphFadeDuration, curve: .easeInOut)
        fader.addAnimations(fade)
        spring.startAnimation()
        fader.startAnimation()
        glyphAnimators = [spring, fader]
    }

    private static let actionTransitionDuration: TimeInterval = 0.4
    private static let glyphFadeDuration: TimeInterval = 0.2
    private static let glyphArrivalFadeKey = "agentGlyphArrivalFade"
    private static let glyphArrivalScaleKey = "agentGlyphArrivalScale"
    private static let hiddenGlyphScale: CGFloat = 0.01
    private static let highlightedSendAlpha: CGFloat = 0.4

    static let microphoneImage = UIImage(
        systemName: "mic",
        withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
    )

    /// A filled square, a little smaller than the microphone so the two weigh the same in the circle
    private static let stopImage = UIImage(
        systemName: "stop.fill",
        withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)
    )

    private static let disabledSendForegroundColor = UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.3) : UIColor(hex: "#BEBEC3")
    }

    private static let disabledSendBackgroundColor = UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.08) : UIColor(white: 0, alpha: 0.05)
    }

    /// The idle microphone reads as a control, like the toolbar's icons
    static let idleMicrophoneColor = UIColor.label

    /// The recording circle grows out of the trailing circle, so it is centred on it rather than on the finger. The
    /// floating microphone sinking back goes to the trailing circle as it stands once the field has settled.
    private func updateDictationTouchPosition() {
        guard dictationState.phase != .idle || dictationState.canDictateMore || dictationTouchView.isSinking else { return }
        let frame = actionFrame
        dictationTouchView.setAnchor(CGPoint(x: frame.midX, y: frame.midY), fieldTop: inputBackgroundFrame.minY)
    }

    @objc private func handleDismissPan(_ gestureRecognizer: UIPanGestureRecognizer) {
        guard textView.isFirstResponder else { return }

        let translation = gestureRecognizer.translation(in: inputBackgroundView)
        let velocity = gestureRecognizer.velocity(in: inputBackgroundView)
        let isVerticalDownwardPan = translation.y > 24 && abs(translation.y) > abs(translation.x)
        let isFastDownwardPan = velocity.y > 500 && abs(velocity.y) > abs(velocity.x)
        guard gestureRecognizer.state == .ended, isVerticalDownwardPan || isFastDownwardPan else { return }

        endEditing(true)
    }

    private func updatePlaceholderVisibility() {
        placeholderLabel.isHidden = !isPlaceholderShown(for: dictationState)
        updateActionButtons()
    }

    /// The text's insets: at the leading end past a recording's cross and dot, at the trailing end past Send
    private func applyTextInsets() {
        let leadingInset = AgentComposerMetrics.contentHorizontalInset + recordingTextInset
        var insets = textView.textContainerInset
        if effectiveUserInterfaceLayoutDirection == .rightToLeft {
            insets.left = textTrailingInset
            insets.right = leadingInset
        } else {
            insets.left = leadingInset
            insets.right = textTrailingInset
        }
        if textView.textContainerInset != insets {
            textView.textContainerInset = insets
            updateInputHeightIfNeeded()
        }
    }

    /// Moves the field's text and placeholder in from the leading end by `inset`, sliding with the recording's dot
    private func setRecordingTextInset(_ inset: CGFloat, animated: Bool) {
        guard inset != recordingTextInset else { return }
        let delta = inset - recordingTextInset
        let content = inputBackgroundView.contentView
        if animated {
            UIView.performWithoutAnimation { content.layoutIfNeeded() }
        }
        recordingTextInset = inset
        placeholderLeadingConstraint.constant = AgentComposerMetrics.contentHorizontalInset + inset
        applyTextInsets()
        guard animated, !(textView.isHidden && placeholderLabel.isHidden) else {
            textView.transform = .identity
            return
        }
        // The text wraps at its new width at once, and slides there from where it stood
        let shift = effectiveUserInterfaceLayoutDirection == .rightToLeft ? delta : -delta
        textView.transform = CGAffineTransform(translationX: shift, y: 0)
        let animator = UIViewPropertyAnimator(
            duration: AgentDictationStripView.slideDuration,
            timingParameters: AgentComposerMetrics.makeTelegramCubicTiming()
        )
        animator.addAnimations {
            self.textView.transform = .identity
            content.layoutIfNeeded()
        }
        animator.startAnimation()
    }

    /// As in Telegram, a long message grows the field until it comes within 120 pt of the top bar, then scrolls
    private var maximumInputHeight: CGFloat {
        guard let window else { return AgentComposerMetrics.maxInputHeight }
        let fieldBottom = convert(CGPoint(x: 0, y: bounds.maxY - verticalInset), to: window).y
        let barBottom = window.safeAreaInsets.top + AgentComposerMetrics.navigationBarHeight
        return max(AgentComposerMetrics.maxInputHeight, fieldBottom - barBottom - AgentComposerMetrics.inputTopClearance)
    }

    private func updateInputHeightIfNeeded() {
        let fieldWidth = fieldFrame.width
        guard fieldWidth > 0, !isHeightUpdateSuspended else { return }

        let fittingSize = textView.sizeThatFits(
            CGSize(
                width: fieldWidth,
                height: .greatestFiniteMagnitude
            )
        )
        let maximumHeight = maximumInputHeight
        // A recording keeps the field as tall as its text while the text shows
        let clampedHeight = isDictating && !isFieldTextShownWhileDictating ? AgentComposerMetrics.minInputHeight : min(
            max(AgentComposerMetrics.minInputHeight, ceil(fittingSize.height)),
            maximumHeight
        )

        guard abs(settledInputHeight - clampedHeight) > 0.5 else {
            textView.isScrollEnabled = clampedHeight >= maximumHeight
            return
        }

        settledInputHeight = clampedHeight
        textView.isScrollEnabled = clampedHeight >= maximumHeight
        invalidateIntrinsicContentSize()
        setNeedsLayout()
        superview?.setNeedsLayout()
        onLayoutHeightChanged?()
    }
}

extension AgentComposerView: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer === dismissPanGestureRecognizer else { return true }
        guard let touchedView = touch.view else { return true }
        return !touchedView.isDescendant(of: microphoneButton)
    }
}

extension AgentComposerView: UITextViewDelegate {
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        !isDictating && textReveal == nil
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
        settleTextReveal()
        onBeginEditing?()
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        guard textView.isFirstResponder, let textReveal, !textReveal.isEditingText else { return }
        settleTextReveal()
    }

    func textViewDidChange(_ textView: UITextView) {
        // The floating microphone first, so the trailing circle knows whether it is coming or going
        syncFloatingMicrophone()
        updatePlaceholderVisibility()
        updateInputHeightIfNeeded()
        onDraftTextChanged?()
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        onEndEditing?()
    }
}
