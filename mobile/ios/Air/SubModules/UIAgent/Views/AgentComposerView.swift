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
    /// The glass circle beside the field, support's on the chat list, and the gap between them
    static let actionCircleSize: CGFloat = 48
    static let actionCircleSpacing: CGFloat = 12
    /// The spring the trailing circle comes out of the field and merges back into it on
    static let actionSeparationDuration: TimeInterval = 0.5
    static let actionSeparationDamping: CGFloat = 0.72
    /// The design's send button inside the field once it has text: a 40 × 32 capsule at the field's trailing end,
    /// 8 pt from its edge and its bottom, with 12 pt before it for the text
    static let sendButtonSize = CGSize(width: 40, height: 32)
    static let sendButtonInset: CGFloat = 8
    static let sendButtonSpacing: CGFloat = 12
    /// The microphone inside the field, as in Claude's app: as tall as the send button and as far from the field's end
    /// and bottom, it steps aside for the send button or Stop, keeping this gap before it
    static let fieldMicrophoneSize: CGFloat = 32
    static let fieldMicrophoneSpacing: CGFloat = 8
    static var fieldMicrophoneShift: CGFloat { sendButtonSize.width + fieldMicrophoneSpacing }
    /// The room the text leaves at the field's end for the microphone
    static var fieldMicrophoneReserve: CGFloat { sendButtonInset + fieldMicrophoneSize + sendButtonSpacing }
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

    /// The placeholder reads as the root search field's "Search or Ask" does, in its font, colour and spacing
    @MainActor
    static var placeholderAttributes: [NSAttributedString.Key: Any] {
        [
            .font: WTypography.uiFont(.body),
            .foregroundColor: UIColor.tertiaryLabel,
            .kern: 0.05,
        ]
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

    let style: Style
    /// Holds the field's and the trailing circle's glass so they merge when they meet. A host can supply its own
    /// container instead, so the composer's glass also merges with the host's.
    private let glassContainerView: UIVisualEffectView?
    private weak var externalGlassHost: UIView?
    private let inputBackgroundView = WGlassView(cornerRadius: AgentComposerMetrics.inputCornerRadius)
    /// The trailing circle: support's headset beside the chat list's empty field. Otherwise it is merged into the field.
    /// A circle at any size, as it grows by its size when it swells.
    private let actionGlassView = WGlassView(cornerRadius: nil)
    /// The trailing circle's glyph and button, which appear as the circle comes out of the field
    private let actionContentView = UIView()
    private let supportGlyphView = UIImageView(image: AgentComposerView.supportImage)
    private let supportButton = UIButton(type: .system)
    /// The cross the headset turns into for a host's close button; see `actionGlyphSwap`
    private let closeGlyphView = UIImageView(image: UIImage.airBundle("UniversalSearchXmark").withRenderingMode(.alwaysTemplate))
    /// The send button's accent capsule inside the field, and its arrow, or Stop's square while an answer can be stopped
    private let sendHighlightView = UIView()
    private let sendGlyphView = UIImageView(image: AgentComposerMetrics.sendArrowImage)
    private var isSendDisplayed = false
    /// The microphone inside the field, its glyph and button
    private let microphoneView = UIView()
    private let microphoneGlyphView = UIImageView(image: AgentComposerView.microphoneImage)
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
    private var textReveal: TextViewCharacterReveal?
    private let dictationTouchView = AgentDictationTouchView()
    private let dismissPanGestureRecognizer = UIPanGestureRecognizer()
    private let microphoneGestureRecognizer = UILongPressGestureRecognizer()
    private var microphoneTouchOrigin = CGPoint.zero
    private var dictationState = AgentDictationState()
    private var isSendEnabled = false
    /// A chat's field keeps Send in place, quiet while there is nothing to send, so the microphone beside it stays put
    var isSendAlwaysShown = false {
        didSet {
            guard isSendAlwaysShown != oldValue else { return }
            updateActionButtons()
        }
    }
    /// The recording's cross at the field's leading end, across the field from Send: tapped, or reached by the held
    /// microphone, it cancels the recording
    private let recordingCancelView = UIView()
    private let recordingCancelGlyphView = UIImageView(image: AgentComposerView.recordingCancelImage)
    private let recordingCancelButton = UIButton(type: .custom)
    private var isRecordingCancelDisplayed = false
    private lazy var stripLeadingConstraint = dictationStripView.leadingAnchor.constraint(
        equalTo: inputBackgroundView.contentView.leadingAnchor,
        constant: AgentComposerMetrics.contentHorizontalInset
    )
    private var isStopAvailable = false
    /// The send button shows Stop, while the field is empty and an answer that can be stopped is being written
    private var isStopDisplayed = false

    /// Stop stands in Send's place
    var isStopShown: Bool { isStopDisplayed }
    private var isDictationStartedWithVoiceOver = false
    private var settledInputHeight = AgentComposerMetrics.minInputHeight
    /// 1 while the trailing circle stands apart from the field, 0 while it is merged into the field's trailing end
    private var actionSeparation: CGFloat = 0
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
    /// The text's inset at the field's trailing end, wider while Send shows there
    private var textTrailingInset = AgentComposerMetrics.contentHorizontalInset

    /// The microphone stands at the field's end, or before the send button
    private lazy var microphoneTrailingConstraint = microphoneView.trailingAnchor.constraint(
        equalTo: inputBackgroundView.contentView.trailingAnchor,
        constant: -AgentComposerMetrics.sendButtonInset
    )

    /// The text stops above the recording's row while the field records into it, so a long text scrolls clear of the
    /// row rather than under it
    private lazy var textBottomConstraint = textView.bottomAnchor.constraint(
        equalTo: inputBackgroundView.contentView.bottomAnchor
    )

    /// How far above the field's bottom the text stops: the recording's row while recording into the text
    private var textRecordingRowHeight: CGFloat {
        isDictatingIntoText ? AgentComposerMetrics.minInputHeight - AgentComposerMetrics.contentVerticalInset : 0
    }

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
    /// Called by the headset in the trailing circle
    var onSupport: (() -> Void)?
    /// The trailing circle offers support beside the empty field, as the chat list's does once it has chats
    var isSupportOffered = false {
        didSet {
            if isSupportOffered != oldValue { updateActionButtons() }
        }
    }
    /// The offered headset is grey and does nothing while support can't be called, as on Android and the web
    var isSupportEnabled = true {
        didSet {
            if isSupportEnabled != oldValue { updateActionButtons() }
        }
    }
    /// Asked before a recording starts, as the recording goes to the Agent: false holds it back, and the host starts it
    /// later with `startDictationHandsFree()`
    var shouldStartDictation: (() -> Bool)?
    var onBeginEditing: (() -> Void)?
    var onEndEditing: (() -> Void)?
    var onLayoutHeightChanged: (() -> Void)?
    var onRecordingCircleVisibilityChanged: (() -> Void)?
    /// The dictation moved to another phase, such as from recording to recognizing, or a touch on the microphone
    /// turned out a hold
    var onDictationPhaseChanged: (() -> Void)?

    /// Whether the recording circle stands over the field's microphone: while recording, and while it shows a failure
    private(set) var isRecordingCircleVisible = false

    /// The field shows a question: one being recorded or recognized, a transcript coming in, or text. A touch on the
    /// microphone that isn't yet a tap or a hold shows nothing of its recording, so it adds no question until it is one.
    var showsQuestion: Bool {
        let isTouchUnclassified = dictationState.phase == .holding && !dictationState.isHeld
        return isDictating && !isTouchUnclassified || textReveal != nil || hasText
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
            for view in [textView, placeholderLabel, dictationStripView, microphoneView] as [UIView] {
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

    /// Merges the trailing circle into the field, for a host that widens the field to a chat's, whose composer has no
    /// circle: 1 merges it whatever holds it apart
    var actionCircleRelease: CGFloat = 0 {
        didSet {
            if actionCircleRelease != oldValue { layoutGlass() }
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

    /// The glass that lives in a host's container, and a hands-free recording's stop over it, for the host's hit
    /// testing
    var hostedGlassViews: [UIView] {
        guard externalGlassHost != nil else { return [] }
        return [inputBackgroundView, actionGlassView] + (dictationTouchView.isTakingTouches ? [dictationTouchView] : [])
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

    /// The trailing circle stands apart from the empty field while support is offered. It merges into the field for a
    /// draft and while a recording shows, its circle over the field's microphone, but not for a touch on the
    /// microphone that isn't yet a tap or a hold.
    private var shouldSeparateActionButton: Bool {
        let isTouchUnclassified = dictationState.phase == .holding && !dictationState.isHeld
        return isSupportOffered && !hasText && (!isDictating || isTouchUnclassified)
    }

    /// A dictation into a field that already has text keeps the text in sight, a line up, and the recording's row
    /// under it: the cross, the hint or the voice, the microphone and Send
    private var isDictatingIntoText: Bool {
        isDictating && hasText
    }

    /// The recording's cross and Send show in the field while recording, once the touch is a tap or a hold
    private var isRecordingControlsShown: Bool {
        dictationState.phase == .holding && dictationState.isHeld || dictationState.phase == .handsFree
    }

    /// While recording hands-free, the field keeps its text in sight, also text of nothing but spaces. A held recording
    /// shows its hint there instead.
    private static func isFieldTextShown(during state: AgentDictationState) -> Bool {
        state.phase == .handsFree
    }

    /// Recording with the field's text in sight
    private var isFieldTextShownWhileDictating: Bool {
        isDictatingIntoText || isDictating && Self.isFieldTextShown(during: dictationState)
    }

    /// The field shows its placeholder while empty: also while a touch on the microphone isn't yet a tap or a hold, but
    /// not once the hint, a hands-free recording's voice or the recognition takes its place
    private func isPlaceholderShown(for state: AgentDictationState) -> Bool {
        guard textView.text?.isEmpty ?? true else { return false }
        switch state.phase {
        case .idle, .failed: return true
        case .handsFree: return false
        case .holding: return !state.isHeld
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
        // A host holds the circle apart, also while it turns the circle into its close cross, and merges it into the
        // field as it widens the field to a chat's
        let hold = min(1, max(0, max(actionCircleHold, actionGlyphSwap)))
        let release = min(1, max(0, actionCircleRelease))
        return (actionSeparation + (1 - actionSeparation) * hold) * (1 - release)
    }

    /// The field: the trailing circle's room shrinks as the circle merges into it
    private var fieldFrame: CGRect {
        let reserve = (AgentComposerMetrics.actionCircleSize + AgentComposerMetrics.actionCircleSpacing) * effectiveActionSeparation
            + max(0, fieldTrailingReserve)
        let height = settledInputHeight
        let width = max(min(height, bounds.width), bounds.width - 2 * horizontalInset - reserve)
        return getDirectionalFrame(CGRect(x: horizontalInset, y: bounds.maxY - verticalInset - height, width: width, height: height))
    }

    /// How far toward the trailing edge the trailing circle has flown as it goes, past the edge once gone, as the search
    /// circle flies past the leading edge: it never flows into the field
    private var actionFlightOffset: CGFloat {
        let distance = (horizontalInset + AgentComposerMetrics.actionCircleSize + Self.actionFlightMargin)
            * (1 - effectiveActionSeparation)
        return effectiveUserInterfaceLayoutDirection == .rightToLeft ? -distance : distance
    }

    private static let actionFlightMargin: CGFloat = 24

    /// The trailing circle is on its own flight, shown until it has flown
    private var isActionFlightAnimating = false

    /// Where the finger pressed the microphone, in the window, for the recording circle to stay there
    private var recordingAnchor: CGPoint?
    /// The window's width the anchor was taken in: a resized window lays the field out anew
    private var recordingAnchorWindowWidth: CGFloat?

    /// The trailing circle sits at the trailing end, level with the field's bottom line
    private var actionFrame: CGRect {
        let size = AgentComposerMetrics.actionCircleSize
        return getDirectionalFrame(CGRect(
            x: bounds.width - horizontalInset - size,
            y: bounds.maxY - verticalInset - size,
            width: size,
            height: size
        ))
    }

    /// The centre of the field's microphone, at the field's end or before the send button
    private var microphoneCenter: CGPoint {
        let field = fieldFrame
        let inset = AgentComposerMetrics.sendButtonInset + AgentComposerMetrics.fieldMicrophoneSize / 2
        let end = inset + (isSendDisplayed ? AgentComposerMetrics.fieldMicrophoneShift : 0)
        let x = effectiveUserInterfaceLayoutDirection == .rightToLeft ? field.minX + end : field.maxX - end
        return CGPoint(x: x, y: field.maxY - inset)
    }

    /// Between the strip's content and the recording circle
    private static let stripCircleSpacing: CGFloat = 8

    /// The recording strip keeps clear of the microphone, which the recording circle covers
    private static let stripTrailingInset = AgentComposerMetrics.sendButtonInset + AgentComposerMetrics.fieldMicrophoneSize
        + AgentComposerMetrics.fieldMicrophoneSpacing

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

    /// A hands-free recording's stop reaches past the composer, where it takes its touches too
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        super.point(inside: point, with: event)
            || dictationTouchView.point(inside: convert(point, to: dictationTouchView), with: event)
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
        updatePlaceholderVisibility()
        updateInputHeightIfNeeded()
    }

    func setDraftText(_ text: String, focus: Bool) {
        endTextReveal()
        textView.text = text
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
    /// `TextViewCharacterReveal` shows them. With Reduce Motion the text fades in. The field takes no typing and
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
        let reveal = TextViewCharacterReveal(
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

    /// A held recording's transcript goes as the question at once, as in the Claude app. One that can't be sent yet
    /// stays in the field, whose microphone dictates more.
    private func sendDictatedText(_ text: String) {
        setDraftText(Self.getDictationPrefix(before: textView.text ?? "") + text, focus: false)
        guard isSendEnabled, let onSend else { return }
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

    /// The field glows once a recording is finished, while it is recognized and while its words come in
    private func updateDictationGlow() {
        let isGlowing = dictationState.phase == .recognizing || textReveal != nil
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
        supportGlyphView.translatesAutoresizingMaskIntoConstraints = false
        supportGlyphView.contentMode = .center
        supportGlyphView.tintColor = Self.idleMicrophoneColor
        supportButton.translatesAutoresizingMaskIntoConstraints = false
        supportButton.accessibilityLabel = lang("$agent_support_contact")
        supportButton.accessibilityIdentifier = "agent_support"
        supportButton.addTarget(self, action: #selector(supportButtonPressed), for: .touchUpInside)
        microphoneView.translatesAutoresizingMaskIntoConstraints = false
        microphoneGlyphView.translatesAutoresizingMaskIntoConstraints = false
        microphoneGlyphView.contentMode = .center
        microphoneGlyphView.tintColor = Self.fieldMicrophoneColor
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

        recordingCancelView.translatesAutoresizingMaskIntoConstraints = false
        recordingCancelView.isUserInteractionEnabled = false
        recordingCancelView.layer.cornerRadius = AgentComposerMetrics.sendButtonSize.height / 2
        recordingCancelView.layer.cornerCurve = .continuous
        recordingCancelView.alpha = 0
        recordingCancelView.transform = CGAffineTransform(scaleX: Self.hiddenGlyphScale, y: Self.hiddenGlyphScale)
        recordingCancelGlyphView.translatesAutoresizingMaskIntoConstraints = false
        recordingCancelGlyphView.contentMode = .center
        recordingCancelButton.translatesAutoresizingMaskIntoConstraints = false
        recordingCancelButton.isHidden = true
        recordingCancelButton.accessibilityLabel = lang("Cancel")
        recordingCancelButton.accessibilityIdentifier = "agent_dictation_cancel"
        recordingCancelButton.addTarget(self, action: #selector(recordingCancelPressed), for: .touchUpInside)

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
            guard let self, let dictationController = self.dictationController else { return false }
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
        microphoneButton.addTarget(self, action: #selector(microphoneButtonPressed), for: .touchUpInside)
        microphoneGestureRecognizer.minimumPressDuration = 0
        microphoneGestureRecognizer.allowableMovement = .greatestFiniteMagnitude
        microphoneGestureRecognizer.addTarget(self, action: #selector(handleMicrophoneGesture(_:)))
        microphoneButton.addGestureRecognizer(microphoneGestureRecognizer)

        dictationStripView.translatesAutoresizingMaskIntoConstraints = false
        dictationStripView.isHidden = true
        dictationTouchView.isHidden = true
        dictationTouchView.onStop = { [weak self] in
            self?.dictationController?.finish()
        }

        dismissPanGestureRecognizer.addTarget(self, action: #selector(handleDismissPan(_:)))
        dismissPanGestureRecognizer.cancelsTouchesInView = false
        dismissPanGestureRecognizer.delegate = self
        inputBackgroundView.addGestureRecognizer(dismissPanGestureRecognizer)

        if let glassContainerView {
            addSubview(glassContainerView)
        }
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
        actionContentView.addSubview(supportGlyphView)
        actionContentView.addSubview(closeGlyphView)
        actionContentView.addSubview(supportButton)
        inputBackgroundView.contentView.addSubview(microphoneView)
        microphoneView.addSubview(microphoneGlyphView)
        microphoneView.addSubview(microphoneButton)
        inputBackgroundView.contentView.addSubview(sendHighlightView)
        sendHighlightView.addSubview(sendGlyphView)
        inputBackgroundView.contentView.addSubview(sendButton)
        inputBackgroundView.contentView.addSubview(recordingCancelView)
        recordingCancelView.addSubview(recordingCancelGlyphView)
        inputBackgroundView.contentView.addSubview(recordingCancelButton)
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
            textBottomConstraint,

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

            supportGlyphView.centerXAnchor.constraint(equalTo: actionContentView.centerXAnchor),
            supportGlyphView.centerYAnchor.constraint(equalTo: actionContentView.centerYAnchor),
            supportButton.leadingAnchor.constraint(equalTo: actionContentView.leadingAnchor),
            supportButton.trailingAnchor.constraint(equalTo: actionContentView.trailingAnchor),
            supportButton.topAnchor.constraint(equalTo: actionContentView.topAnchor),
            supportButton.bottomAnchor.constraint(equalTo: actionContentView.bottomAnchor),
            closeGlyphView.centerXAnchor.constraint(equalTo: actionContentView.centerXAnchor),
            closeGlyphView.centerYAnchor.constraint(equalTo: actionContentView.centerYAnchor),

            // The send button keeps to the field's bottom line as the text grows above it, as in Telegram
            sendHighlightView.trailingAnchor.constraint(equalTo: field.trailingAnchor, constant: -AgentComposerMetrics.sendButtonInset),
            sendHighlightView.bottomAnchor.constraint(equalTo: field.bottomAnchor, constant: -AgentComposerMetrics.sendButtonInset),
            sendHighlightView.widthAnchor.constraint(equalToConstant: AgentComposerMetrics.sendButtonSize.width),
            sendHighlightView.heightAnchor.constraint(equalToConstant: AgentComposerMetrics.sendButtonSize.height),
            sendGlyphView.centerXAnchor.constraint(equalTo: sendHighlightView.centerXAnchor),
            sendGlyphView.centerYAnchor.constraint(equalTo: sendHighlightView.centerYAnchor),

            // The microphone keeps to the field's bottom line beside the send button, its touch target a little larger
            microphoneTrailingConstraint,
            microphoneView.bottomAnchor.constraint(equalTo: field.bottomAnchor, constant: -AgentComposerMetrics.sendButtonInset),
            microphoneView.widthAnchor.constraint(equalToConstant: AgentComposerMetrics.fieldMicrophoneSize),
            microphoneView.heightAnchor.constraint(equalToConstant: AgentComposerMetrics.fieldMicrophoneSize),
            microphoneGlyphView.centerXAnchor.constraint(equalTo: microphoneView.centerXAnchor),
            microphoneGlyphView.centerYAnchor.constraint(equalTo: microphoneView.centerYAnchor),
            microphoneButton.leadingAnchor.constraint(equalTo: microphoneView.leadingAnchor, constant: -4),
            microphoneButton.trailingAnchor.constraint(equalTo: microphoneView.trailingAnchor, constant: 4),
            microphoneButton.topAnchor.constraint(equalTo: microphoneView.topAnchor, constant: -4),
            microphoneButton.bottomAnchor.constraint(equalTo: microphoneView.bottomAnchor, constant: 4),

            // A touch target a little larger than the capsule, to the field's edge
            sendButton.leadingAnchor.constraint(equalTo: sendHighlightView.leadingAnchor, constant: -6),
            sendButton.trailingAnchor.constraint(equalTo: field.trailingAnchor),
            sendButton.topAnchor.constraint(equalTo: sendHighlightView.topAnchor, constant: -6),
            sendButton.bottomAnchor.constraint(equalTo: field.bottomAnchor),

            stripLeadingConstraint,
            dictationStripView.trailingAnchor.constraint(equalTo: field.trailingAnchor, constant: -Self.stripTrailingInset),
            dictationStripView.heightAnchor.constraint(equalToConstant: AgentComposerMetrics.minInputHeight),
            dictationStripView.bottomAnchor.constraint(equalTo: field.bottomAnchor),

            // The recording's cross keeps to the field's bottom line at its leading end, as Send at its trailing one
            recordingCancelView.leadingAnchor.constraint(equalTo: field.leadingAnchor, constant: AgentComposerMetrics.sendButtonInset),
            recordingCancelView.bottomAnchor.constraint(equalTo: field.bottomAnchor, constant: -AgentComposerMetrics.sendButtonInset),
            recordingCancelView.widthAnchor.constraint(equalToConstant: AgentComposerMetrics.sendButtonSize.width),
            recordingCancelView.heightAnchor.constraint(equalToConstant: AgentComposerMetrics.sendButtonSize.height),
            recordingCancelGlyphView.centerXAnchor.constraint(equalTo: recordingCancelView.centerXAnchor),
            recordingCancelGlyphView.centerYAnchor.constraint(equalTo: recordingCancelView.centerYAnchor),
            recordingCancelButton.leadingAnchor.constraint(equalTo: field.leadingAnchor),
            recordingCancelButton.trailingAnchor.constraint(equalTo: recordingCancelView.trailingAnchor, constant: 6),
            recordingCancelButton.topAnchor.constraint(equalTo: recordingCancelView.topAnchor, constant: -6),
            recordingCancelButton.bottomAnchor.constraint(equalTo: field.bottomAnchor),
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
        // What the field holds, its microphone and Send among it, moves with the field in the same pass, and in the
        // same animation if any: glass in a host's container is laid out apart from the composer
        inputBackgroundView.layoutIfNeeded()
        place(
            actionGlassView,
            frame: actionFrame.offsetBy(dx: dx + actionFlightOffset, dy: dy),
            swell: actionSwapSwell,
            shouldResize: true
        )
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

    /// Turns the trailing circle's headset into a close cross, for a host whose close button takes its place: 0 shows
    /// the headset, 1 the cross, the circle coming out of the field for it. The circle swells through the swap as the
    /// bar's morphing glass does, settling with the spring's slight bounce, while the leaving glyph shrinks away as the
    /// arriving one grows in, as the header capsules swap their content.
    var actionGlyphSwap: CGFloat = 0 {
        didSet {
            guard actionGlyphSwap != oldValue else { return }
            let swap = min(1, max(0, actionGlyphSwap))
            let hidden = GlassMotion.matchScale
            supportGlyphView.alpha = 1 - swap
            supportGlyphView.transform = CGAffineTransform(scaleX: 1 + (hidden - 1) * swap, y: 1 + (hidden - 1) * swap)
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
        actionContentView.alpha = contentAlpha
        inputBackgroundView.isHidden = isGlassHidden
        // Glass doesn't fade with its alpha, and neither does blur; they materialize instead
        let isMaterialized = glassAlpha > 0.01
        inputBackgroundView.setMaterialized(isMaterialized)
        // The circle keeps its glass and glyph as it flies off, apart from the field, and hides once past the edge:
        // hidden at once, a glass container would flow it into the field
        actionGlassView.setMaterialized(isMaterialized)
        actionGlassView.isHidden = isGlassHidden || separation < 0.01 && !isActionFlightAnimating
        actionGlassView.isUserInteractionEnabled = separation > 0.01
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
        isActionFlightAnimating = true
        UIView.animate(
            withDuration: AgentComposerMetrics.actionSeparationDuration,
            delay: 0,
            usingSpringWithDamping: AgentComposerMetrics.actionSeparationDamping,
            initialSpringVelocity: 0,
            options: [.beginFromCurrentState, .allowUserInteraction]
        ) {
            self.layoutGlass()
            self.inputBackgroundView.layoutIfNeeded()
        } completion: { isFinished in
            guard isFinished else { return }
            self.isActionFlightAnimating = false
            self.applyGlassAppearance()
        }
        updateInputHeightIfNeeded()
    }

    @objc private func sendButtonPressed() {
        if isStopDisplayed {
            onStop?()
            return
        }
        if dictationState.phase == .handsFree {
            dictationController?.finishAndSend()
            return
        }
        settleTextReveal()
        onSend?()
    }

    @objc private func supportButtonPressed() {
        onSupport?()
    }

    @objc private func recordingCancelPressed() {
        guard isRecordingCancelDisplayed else { return }
        dictationController?.cancel()
    }

    /// The recording's cross grows in at the field's leading end as Send does at its trailing end, on Telegram's
    /// layout spring, and the hint and the voice make room for it
    private func setRecordingCancelShown(_ isShown: Bool) {
        guard isShown != isRecordingCancelDisplayed else { return }
        isRecordingCancelDisplayed = isShown
        recordingCancelButton.isHidden = !isShown
        let content = inputBackgroundView.contentView
        let animated = window != nil && UIView.areAnimationsEnabled
        if animated {
            UIView.performWithoutAnimation { content.layoutIfNeeded() }
        }
        stripLeadingConstraint.constant = isShown
            ? AgentComposerMetrics.sendButtonInset + AgentComposerMetrics.sendButtonSize.width + Self.recordingCancelSpacing
            : AgentComposerMetrics.contentHorizontalInset
        let hiddenTransform = UIAccessibility.isReduceMotionEnabled
            ? .identity
            : CGAffineTransform(scaleX: Self.hiddenGlyphScale, y: Self.hiddenGlyphScale)
        let apply = {
            self.recordingCancelView.transform = isShown ? .identity : hiddenTransform
            content.layoutIfNeeded()
        }
        let fade = {
            self.recordingCancelView.alpha = isShown ? 1 : 0
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
        spring.startAnimation()
        UIViewPropertyAnimator(duration: Self.glyphFadeDuration, curve: .easeInOut, animations: fade).startAnimation()
    }

    /// The cross turns red while letting go of the held microphone would cancel, and is quiet otherwise
    private func applyRecordingCancelAppearance() {
        let isHighlighted = dictationState.phase == .holding && dictationState.isHeld && dictationState.holdZone == .cancel
        recordingCancelView.backgroundColor = isHighlighted ? .systemRed : Self.disabledSendBackgroundColor
        recordingCancelGlyphView.tintColor = isHighlighted ? .white : .label
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

    @objc private func microphoneButtonPressed() {
        guard dictationState.phase == .handsFree else { return }
        dictationController?.finish()
    }

    @objc private func handleMicrophoneGesture(_ gestureRecognizer: UILongPressGestureRecognizer) {
        // Starting a recording can shrink and move the composer under the finger.
        let point = gestureRecognizer.location(in: window)
        switch gestureRecognizer.state {
        case .began:
            guard shouldStartDictation?() != false else {
                // The press ends here; the host starts the recording once it may
                gestureRecognizer.isEnabled = false
                gestureRecognizer.isEnabled = true
                return
            }
            microphoneTouchOrigin = point
            dictationController?.touchBegan(isRightToLeft: effectiveUserInterfaceLayoutDirection == .rightToLeft)
        case .changed:
            dictationController?.touchMoved(x: Double(point.x - microphoneTouchOrigin.x))
        case .ended:
            dictationController?.touchEnded(x: Double(point.x - microphoneTouchOrigin.x))
        case .cancelled, .failed:
            // A recording that stops by itself, as at its limit, disables the active recognizer
            if dictationState.phase == .holding || dictationState.phase == .idle {
                dictationController?.cancel()
            }
        default:
            break
        }
    }

    private func updateDictationState(_ state: AgentDictationState) {
        let previousPhase = dictationState.phase
        let wasDictatingIntoText = isDictatingIntoText
        switch state.phase {
        case .holding, .handsFree:
            if recordingAnchor == nil, let window {
                recordingAnchor = convert(microphoneCenter, to: nil)
                recordingAnchorWindowWidth = window.bounds.width
            }
        case .idle, .failed:
            recordingAnchor = nil
            recordingAnchorWindowWidth = nil
        case .recognizing:
            break
        }
        let wasHoldShown = previousPhase == .holding && dictationState.isHeld
        // As in Telegram, the field's placeholder fades out as the hint comes in
        let placeholderSnapshot = !placeholderLabel.isHidden && !isPlaceholderShown(for: state) && state.phase != .idle
            && window != nil && UIView.areAnimationsEnabled && !UIAccessibility.isReduceMotionEnabled
            ? placeholderLabel.snapshotView(afterScreenUpdates: false)
            : nil
        dictationState = state
        if state.phase == .holding || state.phase == .handsFree {
            settleTextReveal()
        }
        let isHoldShown = state.phase == .holding && state.isHeld
        let isDictating = self.isDictating
        textView.isInputBlocked = isDictating || textReveal != nil
        textView.isHidden = isDictating && !isFieldTextShownWhileDictating
        // Shown before its update, so its hint comes in, and hidden after it
        let isStripShown = isDictating
        if isStripShown { dictationStripView.isHidden = false }
        dictationStripView.update(state)
        if !isStripShown { dictationStripView.isHidden = true }
        // The field grows a line for the recording's row under its text, and shrinks back after it, on Telegram's
        // input panel transition, the text riding up and down with the field's top
        if wasDictatingIntoText != isDictatingIntoText, window != nil, UIView.areAnimationsEnabled,
           !UIAccessibility.isReduceMotionEnabled {
            let animator = UIViewPropertyAnimator(duration: 0.4, timingParameters: AgentComposerMetrics.makeTelegramCubicTiming())
            animator.addAnimations { [weak self] in
                guard let self else { return }
                applyTextInsets()
                (superview ?? self).layoutIfNeeded()
            }
            animator.startAnimation()
        } else {
            applyTextInsets()
        }
        // No caret blinks in the field while it records or recognizes; the field keeps the keyboard
        textView.tintColor = isDictating ? .clear : nil
        setRecordingCancelShown(isRecordingControlsShown)
        updateDictationTouchPosition()
        dictationTouchView.update(state)
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
                showMicrophoneDeniedAlert()
            }
            updateInputHeightIfNeeded()
            if state.phase == .handsFree && !isDictationStartedWithVoiceOver {
                UIAccessibility.post(notification: .layoutChanged, argument: microphoneButton)
            } else if state.phase == .recognizing {
                UIAccessibility.post(
                    notification: .layoutChanged,
                    argument: isDictatingIntoText ? textView : dictationStripView.statusAccessibilityElement
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
        if state.phase != previousPhase || isHoldShown != wasHoldShown {
            onDictationPhaseChanged?()
        }
    }

    /// Shows the toast over the field, which floats over the chat list's screen, so that the field never covers it
    func showToast(_ config: ToastConfig) {
        let owner = sequence(first: next, next: { $0?.next }).lazy.compactMap { $0 as? WViewController }.first
        guard let owner else {
            AppActions.showToast(config)
            return
        }
        owner.toastController.showToast(config, keepingAbove: inputTopGuide, spacing: AgentVCLayout.toastSpacingToComposer)
    }

    /// Says the microphone is denied in a dialog, as Android does, with a button to the app's page in Settings, which
    /// alone gives the microphone back once it is denied
    private func showMicrophoneDeniedAlert() {
        let owner = sequence(first: next, next: { $0?.next }).lazy.compactMap { $0 as? UIViewController }.first
        owner?.showAlert(
            title: nil,
            text: lang("$agent_dictation_microphone_denied_device"),
            button: lang("Open Settings"),
            buttonPressed: {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            },
            secondaryButton: lang("Cancel")
        )
    }

    /// As the hint goes, after a held recording or a tap, the placeholder comes back the way the hint took its
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
        // Stop with an empty field while an answer can be stopped, Send with text, as Android and the web have them: a
        // question sent during the answer waits for it. Send keeps its place whatever a dictation into the text does.
        isStopDisplayed = isStopAvailable && phase == .idle && !hasText
        let isRecordingControlsShown = self.isRecordingControlsShown
        let isCapsuleShown = hasText || isStopDisplayed || isSendAlwaysShown || isRecordingControlsShown
        sendButton.isHidden = !isCapsuleShown
        sendButton.isEnabled = isStopDisplayed || isRecordingControlsShown || isSendEnabled && hasText
        // While recording hands-free it sends the recording at once; while held, letting go over it does
        sendButton.isUserInteractionEnabled = !isDictating || phase == .handsFree
        sendButton.accessibilityLabel = lang(isStopDisplayed ? "$agent_stop_answer" : "Send")
        sendButton.accessibilityIdentifier = isStopDisplayed ? "agent_stop" : "agent_send"
        // The microphone gives way to the recognition's strip, and to the recording circle while it shows, which grows out
        // of it and goes back into it
        microphoneView.isHidden = phase == .recognizing || isRecordingControlsShown
        microphoneButton.isEnabled = hasDictation
        microphoneButton.accessibilityLabel = lang(phase == .handsFree ? "$agent_dictation_finish" : "$agent_dictation_start")
        microphoneGestureRecognizer.isEnabled = hasDictation && (phase == .idle || phase == .holding || phase == .failed)
        supportGlyphView.isHidden = !isSupportOffered
        supportGlyphView.tintColor = isSupportEnabled ? Self.idleMicrophoneColor : .tertiaryLabel
        supportButton.isEnabled = isSupportOffered && isSupportEnabled
        // Send is accented when it would send: with text, for a recording once it has heard something to recognize, and
        // for the held microphone over Send
        let isSendAccented = isStopDisplayed || phase == .handsFree && dictationState.hasSpeech
            || phase == .holding && dictationState.isHeld
                && (dictationState.holdZone == .send || dictationState.hasSpeech)
            || !isDictating && isSendEnabled && hasText
        applySendAppearance(
            isVisible: isCapsuleShown,
            isStop: isStopDisplayed,
            isAccented: isSendAccented,
            animated: window != nil && UIView.areAnimationsEnabled
        )
        applyRecordingCancelAppearance()
        updateActionSeparation(animated: true)
    }

    /// The send button inside the field: an accent capsule with a white arrow, or a quiet one while sending isn't
    /// possible, and the accent capsule with Stop's square while an answer can be stopped. It grows in at the field's
    /// end on Telegram's layout spring as the microphone steps aside for it, and the text makes room for both.
    private func applySendAppearance(isVisible: Bool, isStop: Bool, isAccented: Bool, animated: Bool) {
        sendHighlightView.backgroundColor = isAccented ? tintColor : Self.disabledSendBackgroundColor
        sendGlyphView.tintColor = isAccented ? tintColor.foregroundForTintedBackground : Self.disabledSendForegroundColor
        let glyph = isStop ? Self.stopImage : AgentComposerMetrics.sendArrowImage
        if sendGlyphView.image !== glyph {
            // Stop and the arrow cross-fade where the capsule stays, as typing during an answer turns one into the other
            if animated, isVisible, isSendDisplayed {
                UIView.transition(
                    with: sendGlyphView,
                    duration: Self.glyphFadeDuration,
                    options: [.transitionCrossDissolve, .allowUserInteraction]
                ) {
                    self.sendGlyphView.image = glyph
                }
            } else {
                sendGlyphView.image = glyph
            }
        }
        textTrailingInset = AgentComposerMetrics.fieldMicrophoneReserve + (isVisible ? AgentComposerMetrics.fieldMicrophoneShift : 0)
        applyTextInsets()
        guard isVisible != isSendDisplayed else { return }
        isSendDisplayed = isVisible
        updateDictationTouchPosition()
        for animator in glyphAnimators where animator.state == .active {
            animator.stopAnimation(true)
        }
        glyphAnimators = []
        let hiddenTransform = UIAccessibility.isReduceMotionEnabled
            ? .identity
            : CGAffineTransform(scaleX: Self.hiddenGlyphScale, y: Self.hiddenGlyphScale)
        microphoneTrailingConstraint.constant = -AgentComposerMetrics.sendButtonInset
            - (isVisible ? AgentComposerMetrics.fieldMicrophoneShift : 0)
        let apply = {
            self.sendHighlightView.transform = isVisible ? .identity : hiddenTransform
            self.inputBackgroundView.contentView.layoutIfNeeded()
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
    /// Between the recording's cross and the hint after it
    private static let recordingCancelSpacing: CGFloat = 10
    private static let recordingCancelImage = UIImage(
        systemName: "xmark",
        withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
    )
    private static let glyphFadeDuration: TimeInterval = 0.2
    private static let hiddenGlyphScale: CGFloat = 0.01
    private static let highlightedSendAlpha: CGFloat = 0.4

    static let microphoneImage = UIImage(
        systemName: "mic",
        withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
    )

    private static let supportImage = UIImage(
        systemName: "headphones",
        withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
    )

    /// A filled square, as in ChatGPT's and Telegram's stop states, weighing as much as the arrow in the capsule
    private static let stopImage = UIImage(
        systemName: "stop.fill",
        withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .regular)
    )

    private static let disabledSendForegroundColor = UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.3) : UIColor(hex: "#BEBEC3")
    }

    private static let disabledSendBackgroundColor = UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.08) : UIColor(white: 0, alpha: 0.05)
    }

    /// The idle microphone reads as a control, like the toolbar's icons
    static let idleMicrophoneColor = UIColor.label
    /// The field's microphone is gray, as the root search field's is, so the field's text leads
    static let fieldMicrophoneColor = UIColor.secondaryLabel

    /// The recording circle grows out of the field's microphone, so it is centred on it rather than on the finger
    private func updateDictationTouchPosition() {
        guard dictationState.phase != .idle else { return }
        // A rotated or resized window moves the field, so the circle goes to where the microphone now stands
        if recordingAnchor != nil, let window, window.bounds.width != recordingAnchorWindowWidth {
            recordingAnchor = convert(microphoneCenter, to: nil)
            recordingAnchorWindowWidth = window.bounds.width
        }
        // The circle stays where the finger pressed the microphone, under it, as the field widens around it
        var anchor = recordingAnchor.map { convert($0, from: nil) } ?? microphoneCenter
        // The field can move under a recording, as when the keyboard closes, and the circle stays in its row
        anchor.y = microphoneCenter.y
        let cancelX = recordingCancelView.convert(CGPoint(x: recordingCancelView.bounds.midX, y: 0), to: self).x
        let sendX = sendHighlightView.convert(CGPoint(x: sendHighlightView.bounds.midX, y: 0), to: self).x
        // A hands-free recording's circle is its stop, which a tap must reach apart from Send: where the microphone
        // stood in Send's place, the circle rests before Send, where the microphone steps aside to
        let sendClearance = AgentComposerMetrics.fieldMicrophoneShift
        if dictationState.phase == .handsFree, abs(sendX - anchor.x) < sendClearance {
            anchor.x = sendX + (cancelX < sendX ? -sendClearance : sendClearance)
        }
        dictationTouchView.setAnchor(anchor)
        // The held circle travels from the microphone to the cross one way and to Send the other, and the zones that
        // decide what letting go does meet halfway to each, with a minimum Stop zone toward Send
        let microphoneX = anchor.x
        dictationTouchView.horizontalTravel = (min(cancelX, sendX) - microphoneX)...(max(cancelX, sendX) - microphoneX)
        dictationController?.cancelZoneTravel = Double(abs(cancelX - microphoneX) / 2)
        dictationController?.sendZoneTravel = max(AgentDictationController.sendZoneDistance, Double(abs(sendX - microphoneX) / 2))
        // The strip's hint and voice keep clear of the circle where it rests
        let circleRadius = dictationState.phase == .handsFree
            ? AgentComposerMetrics.sendButtonSize.height / 2
            : AgentVoiceRecordingMetrics.circleDiameter / 2
        let strip = convert(dictationStripView.bounds, from: dictationStripView)
        let circleStart = effectiveUserInterfaceLayoutDirection == .rightToLeft
            ? anchor.x + circleRadius + Self.stripCircleSpacing - strip.minX
            : strip.maxX - (anchor.x - circleRadius - Self.stripCircleSpacing)
        dictationStripView.trailingClearance = max(0, circleStart)
        dictationStripView.stopCenter = dictationStripView.convert(anchor, from: self).x
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

    /// The text's insets: at the leading end past a recording's cross, at the trailing end past the microphone
    /// and Send
    private func applyTextInsets() {
        placeholderTrailingConstraint.constant = -textTrailingInset
        let leadingInset = AgentComposerMetrics.contentHorizontalInset
        var insets = textView.textContainerInset
        if effectiveUserInterfaceLayoutDirection == .rightToLeft {
            insets.left = textTrailingInset
            insets.right = leadingInset
        } else {
            insets.left = leadingInset
            insets.right = textTrailingInset
        }
        // While recording into text, the text keeps a line up, over the recording's row: the text view stops above
        // the row, so a text long enough to scroll shows its end there and nothing under the row
        insets.bottom = AgentComposerMetrics.contentVerticalInset
        let textBottom = -textRecordingRowHeight
        let isTextBottomChanged = textBottomConstraint.constant != textBottom
        textBottomConstraint.constant = textBottom
        if textView.textContainerInset != insets || isTextBottomChanged {
            textView.textContainerInset = insets
            updateInputHeightIfNeeded()
        }
        if isTextBottomChanged, isDictatingIntoText {
            scrollTextToEnd()
        }
    }

    /// Shows the text's end, where a recording adds to it
    private func scrollTextToEnd() {
        guard textView.isScrollEnabled else { return }
        textView.layoutIfNeeded()
        let bottom = textView.contentSize.height + textView.adjustedContentInset.bottom - textView.bounds.height
        textView.contentOffset.y = max(-textView.adjustedContentInset.top, bottom)
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
            max(AgentComposerMetrics.minInputHeight, ceil(fittingSize.height) + textRecordingRowHeight),
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
        updatePlaceholderVisibility()
        updateInputHeightIfNeeded()
        onDraftTextChanged?()
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        onEndEditing?()
    }
}
