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

    override func insertText(_ text: String) {
        guard !isInputBlocked else { return }
        super.insertText(text)
    }

    override func deleteBackward() {
        guard !isInputBlocked else { return }
        super.deleteBackward()
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
            if modifiers == UIKeyModifierFlags.shift
                || modifiers == UIKeyModifierFlags.alternate
                || modifiers == [UIKeyModifierFlags.shift, UIKeyModifierFlags.alternate] {
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
    private let inputTopGuide = UILayoutGuide()
    private let textView = AgentComposerTextView()
    private let placeholderLabel = UILabel()
    private let sendButton = UIButton(type: .system)
    private let microphoneButton = AgentDictationButton(type: .system)
    private let dictationStripView = AgentDictationStripView()
    private let dictationTouchView = AgentDictationTouchView()
    private let dismissPanGestureRecognizer = UIPanGestureRecognizer()
    private let microphoneGestureRecognizer = UILongPressGestureRecognizer()
    private var microphoneTouchOrigin = CGPoint.zero
    private var microphoneLastSample: (point: CGPoint, time: CFTimeInterval)?
    private var microphoneVelocity = CGPoint.zero
    private var dictationState = AgentDictationState()
    private var isSendEnabled = false
    private var isDictationStartedWithVoiceOver = false
    private var settledInputHeight = AgentComposerMetrics.minInputHeight
    /// 1 while the trailing circle stands apart from the field, 0 while it is merged into the field's trailing end
    private var actionSeparation: CGFloat = 0
    private var displayedActionTint: UIColor?
    private var glyphAnimators: [UIViewPropertyAnimator] = []

    var dictationController: AgentDictationController? {
        didSet {
            oldValue?.onStateChanged = nil
            dictationController?.onStateChanged = { [weak self] state in
                self?.updateDictationState(state)
            }
            updateDictationState(dictationController?.state ?? AgentDictationState())
            updateActionSeparation(animated: false)
        }
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
    var onBeginEditing: (() -> Void)?
    var onEndEditing: (() -> Void)?
    var onLayoutHeightChanged: (() -> Void)?
    var onRecordingCircleVisibilityChanged: (() -> Void)?

    /// Whether the recording circle stands over the trailing circle: while recording, and while it shows a failure
    private(set) var isRecordingCircleVisible = false

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

    /// The glass that lives in a host's container, for the host's hit testing
    var hostedGlassViews: [UIView] {
        externalGlassHost == nil ? [] : [inputBackgroundView, actionGlassView]
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

    /// The microphone circle stands apart while the field is empty; it merges into the field while a recording is
    /// recognized, when the field shows the progress, and while the field has text, when the send button is inside it
    private var shouldSeparateActionButton: Bool {
        dictationState.phase != .recognizing && !(dictationState.phase == .idle && hasText)
    }

    /// Recording or recognizing: the field shows the recording strip instead of the text
    private var isDictating: Bool {
        switch dictationState.phase {
        case .holding, .locked, .recognizing: true
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

    func clearDraft() {
        textView.text = nil
        updatePlaceholderVisibility()
        updateInputHeightIfNeeded()
    }

    func setDraftText(_ text: String, focus: Bool) {
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
            // The touch circle stays above the glass
            insertSubview(glassContainerView, belowSubview: dictationTouchView)
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
            guard self?.dictationState.phase == .idle else { return }
            self?.onSend?()
        }

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
            guard let self, let dictationController = self.dictationController else { return false }
            switch self.dictationState.phase {
            case .locked:
                dictationController.finish()
            case .idle, .failed:
                self.isDictationStartedWithVoiceOver = true
                dictationController.startHandsFree()
            case .holding, .recognizing:
                return false
            }
            return true
        }
        microphoneButton.addTarget(self, action: #selector(finishDictationPressed), for: .touchUpInside)
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

        dismissPanGestureRecognizer.addTarget(self, action: #selector(handleDismissPan(_:)))
        dismissPanGestureRecognizer.cancelsTouchesInView = false
        dismissPanGestureRecognizer.delegate = self
        inputBackgroundView.addGestureRecognizer(dismissPanGestureRecognizer)

        if let glassContainerView {
            addSubview(glassContainerView)
        }
        glassHost.addSubview(inputBackgroundView)
        glassHost.addSubview(actionGlassView)
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

            placeholderLabel.leadingAnchor.constraint(
                equalTo: field.leadingAnchor,
                constant: AgentComposerMetrics.contentHorizontalInset
            ),
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
        actionContentView.alpha = contentAlpha * glyphAlpha
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
            isMaterialized && dictationState.phase != .holding && (canMergeWithField || separation > 0.5)
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
            withDuration: 0.5,
            delay: 0,
            usingSpringWithDamping: 0.72,
            initialSpringVelocity: 0,
            options: [.beginFromCurrentState, .allowUserInteraction]
        ) {
            self.layoutGlass()
            self.inputBackgroundView.layoutIfNeeded()
        }
        updateInputHeightIfNeeded()
    }

    @objc private func sendButtonPressed() {
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

    @objc private func finishDictationPressed() {
        guard dictationState.phase == .locked else { return }
        dictationController?.finish()
    }

    @objc private func handleMicrophoneGesture(_ gestureRecognizer: UILongPressGestureRecognizer) {
        // Starting a recording can shrink and move the composer under the finger.
        let point = gestureRecognizer.location(in: window)
        let now = CACurrentMediaTime()
        switch gestureRecognizer.state {
        case .began:
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
            // Locking and automatic recognition disable the active recognizer.
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
        // As in Telegram, the field's placeholder fades out as the recording panel comes in
        let isStartingRecording = (previousPhase == .idle || previousPhase == .failed)
            && (state.phase == .holding || state.phase == .locked)
        let placeholderSnapshot = isStartingRecording && !placeholderLabel.isHidden && window != nil
            && UIView.areAnimationsEnabled && !UIAccessibility.isReduceMotionEnabled
            ? placeholderLabel.snapshotView(afterScreenUpdates: false)
            : nil
        dictationState = state
        if (previousPhase == .holding) != (state.phase == .holding) {
            if state.phase == .holding || window == nil || !UIView.areAnimationsEnabled {
                UIView.performWithoutAnimation { applyGlassAppearance() }
            } else {
                // Back under the recording circle as it goes, the microphone's circle materializes again
                UIView.animate(withDuration: 0.3, delay: 0, options: [.beginFromCurrentState, .curveEaseOut]) {
                    self.applyGlassAppearance()
                }
            }
        }
        let isDictating = self.isDictating
        textView.isInputBlocked = isDictating
        textView.isHidden = isDictating
        dictationStripView.isHidden = !isDictating
        dictationStripView.update(state)
        updateDictationTouchPosition()
        dictationTouchView.update(state, isRightToLeft: effectiveUserInterfaceLayoutDirection == .rightToLeft)
        updatePlaceholderVisibility()
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
        if state.phase != previousPhase {
            if state.phase == .failed, state.failure == .microphoneDenied {
                AppActions.showToast(ToastConfig(
                    style: .overlay, icon: .symbolImage("mic.slash"),
                    message: lang("$agent_dictation_microphone_denied"), duration: 5, transition: .scale
                ))
            }
            updateInputHeightIfNeeded()
            if state.phase == .locked && !isDictationStartedWithVoiceOver {
                UIAccessibility.post(notification: .layoutChanged, argument: microphoneButton)
            } else if state.phase == .recognizing {
                UIAccessibility.post(notification: .layoutChanged, argument: dictationStripView.cancelAccessibilityElement)
            } else if previousPhase == .recognizing, state.phase == .idle {
                UIAccessibility.post(notification: .layoutChanged, argument: textView)
            } else if state.phase == .failed, let failure = state.failure, UIAccessibility.isVoiceOverRunning {
                UIAccessibility.post(notification: .announcement, argument: failure.accessibilityAnnouncement)
            }
        }
        if state.phase == .idle {
            isDictationStartedWithVoiceOver = false
        }
    }

    private func updateRecordingCircleVisibility() {
        let phase = dictationState.phase
        let isVisible = phase == .holding || phase == .locked || phase == .failed
        guard isVisible != isRecordingCircleVisible else { return }
        isRecordingCircleVisible = isVisible
        onRecordingCircleVisibilityChanged?()
    }

    private func updateActionButtons() {
        let phase = dictationState.phase
        let hasDictation = dictationController != nil
        let isLocked = phase == .locked
        let isRecording = phase == .holding || isLocked
        let mode: ActionMode = phase == .idle && hasText ? .send : .microphone
        let isSeparate = shouldSeparateActionButton
        sendButton.isHidden = mode != .send
        sendButton.isEnabled = isSendEnabled
        microphoneButton.isHidden = mode != .microphone || !isSeparate
        microphoneButton.isEnabled = hasDictation
        microphoneButton.accessibilityLabel = lang(isLocked ? "$agent_dictation_finish" : "$agent_dictation_start")
        microphoneGestureRecognizer.isEnabled = hasDictation && (phase == .idle || phase == .holding || phase == .failed)

        let microphoneImage = isLocked ? Self.checkmarkImage : Self.microphoneImage
        if microphoneGlyphView.image !== microphoneImage {
            microphoneGlyphView.image = microphoneImage
        }
        // Telegram's idle microphone is a plain grey glyph; the recording circle covers it while recording
        microphoneGlyphView.tintColor = isRecording ? tintColor.foregroundForTintedBackground : Self.idleMicrophoneColor
        let canAnimate = window != nil && UIView.areAnimationsEnabled
        // The locked recording's checkmark sits on accent-tinted glass; otherwise the circle is clear glass
        let tint: UIColor? = isLocked ? tintColor : nil
        if tint != displayedActionTint {
            displayedActionTint = tint
            applyActionTint(tint, animated: canAnimate)
        }
        applySendAppearance(isVisible: mode == .send, animated: canAnimate)
        updateActionSeparation(animated: true)
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
        let trailingInset = isVisible ? AgentComposerMetrics.sendButtonReserve : AgentComposerMetrics.contentHorizontalInset
        var insets = textView.textContainerInset
        if effectiveUserInterfaceLayoutDirection == .rightToLeft {
            insets.left = trailingInset
            insets.right = AgentComposerMetrics.contentHorizontalInset
        } else {
            insets.left = AgentComposerMetrics.contentHorizontalInset
            insets.right = trailingInset
        }
        if textView.textContainerInset != insets {
            textView.textContainerInset = insets
            updateInputHeightIfNeeded()
        }
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
    private static let hiddenGlyphScale: CGFloat = 0.01
    private static let highlightedSendAlpha: CGFloat = 0.4

    private static let microphoneImage = UIImage(
        systemName: "mic",
        withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
    )

    private static let checkmarkImage = UIImage(
        systemName: "checkmark",
        withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
    )

    private static let disabledSendForegroundColor = UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.3) : UIColor(hex: "#BEBEC3")
    }

    private static let disabledSendBackgroundColor = UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.08) : UIColor(white: 0, alpha: 0.05)
    }

    /// The idle microphone reads as a control, like the toolbar's icons
    private static let idleMicrophoneColor = UIColor.label

    /// The recording circle grows out of the trailing circle, so it is centred on it rather than on the finger
    private func updateDictationTouchPosition() {
        guard dictationState.phase != .idle else { return }
        let frame = actionFrame
        dictationTouchView.setAnchor(CGPoint(x: frame.midX, y: frame.midY))
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
        placeholderLabel.isHidden = isDictating || !(textView.text?.isEmpty ?? true)
        updateActionButtons()
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
        let clampedHeight = isDictating ? AgentComposerMetrics.minInputHeight : min(
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
        !isDictating
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
        onBeginEditing?()
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
