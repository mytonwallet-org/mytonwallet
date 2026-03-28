import UIKit
import WalletContext

private enum AgentComposerMetrics {
    static let composerBackgroundColor = UIColor.clear
    static let textFont = UIFont.systemFont(ofSize: 17, weight: .regular)
    static let placeholderFont = UIFont.systemFont(ofSize: 17, weight: .regular)
    static let inputCornerRadius: CGFloat = 22
    static let sendButtonCornerRadius: CGFloat = 16
    static let minInputHeight: CGFloat = 44
    static let maxInputHeight: CGFloat = 132
    static let horizontalInset: CGFloat = 16
    static let verticalInset: CGFloat = 12
    static let contentHorizontalInset: CGFloat = 14
    static let contentVerticalInset: CGFloat = 10
    static let sendButtonInset: CGFloat = 6
    static let buttonSpacing: CGFloat = 12
    static let sendButtonWidth: CGFloat = 40
    static let sendButtonHeight: CGFloat = 32
    static let hintsButtonWidth: CGFloat = 24
    static let hintsButtonHeight: CGFloat = 24
    static let reservedTrailingTextInsetWithoutHints: CGFloat = 56
    static let reservedTrailingTextInsetWithHints: CGFloat = 92
}

final class AgentComposerTextView: UITextView {
    var onHardwareSend: (() -> Void)?

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
    private let inputBackgroundView = AgentMaterialBackgroundView(cornerRadius: AgentComposerMetrics.inputCornerRadius)
    private let textView = AgentComposerTextView()
    private let placeholderLabel = UILabel()
    private let hintsButton = UIButton(type: .system)
    private let sendButton = UIButton(type: .system)
    private let dismissPanGestureRecognizer = UIPanGestureRecognizer()
    private var isHintsToggleVisible = false

    private lazy var inputHeightConstraint = inputBackgroundView.heightAnchor.constraint(equalToConstant: AgentComposerMetrics.minInputHeight)
    private lazy var hintsButtonWidthConstraint = hintsButton.widthAnchor.constraint(equalToConstant: 0)
    private lazy var hintsButtonTrailingConstraint = hintsButton.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor)

    var onDraftTextChanged: (() -> Void)?
    var onSend: (() -> Void)?
    var onHintsToggle: (() -> Void)?
    var onBeginEditing: (() -> Void)?
    var onEndEditing: (() -> Void)?
    var onLayoutHeightChanged: (() -> Void)?

    var draftText: String? {
        textView.text
    }

    var isTextInputActive: Bool {
        textView.isFirstResponder
    }

    var inputTopAnchor: NSLayoutYAxisAnchor {
        inputBackgroundView.topAnchor
    }

    var inputBackgroundFrame: CGRect {
        inputBackgroundView.frame
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
        applyTheme()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateInputHeightIfNeeded()
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        applyTheme()
    }

    func applyTheme() {
        backgroundColor = AgentComposerMetrics.composerBackgroundColor
        inputBackgroundView.applyEffect()
        textView.textColor = UIColor.label
        textView.tintColor = .tintColor
        placeholderLabel.textColor = .air.secondaryLabel
        updateHintsButtonAppearance()
        setSendEnabled(sendButton.isEnabled)
    }

    func setSendEnabled(_ isEnabled: Bool) {
        sendButton.isEnabled = isEnabled
        sendButton.tintColor = isEnabled ? .white : .air.secondaryLabel
        var buttonConfiguration = sendButton.configuration ?? .plain()
        buttonConfiguration.baseForegroundColor = isEnabled ? .white : .air.secondaryLabel
        sendButton.configuration = buttonConfiguration
        sendButton.backgroundColor = isEnabled ? tintColor : .air.secondaryFill
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

    func setHintsToggleVisible(_ isVisible: Bool, isSelected: Bool) {
        isHintsToggleVisible = isVisible
        hintsButton.isSelected = isSelected
        hintsButton.isHidden = !isVisible
        hintsButtonWidthConstraint.constant = isVisible ? AgentComposerMetrics.hintsButtonWidth : 0
        hintsButtonTrailingConstraint.constant = isVisible ? -AgentComposerMetrics.buttonSpacing : 0
        updateTrailingTextInset()
        updateHintsButtonAppearance()
        setNeedsLayout()
        updateInputHeightIfNeeded()
    }

    private func setupViews() {
        translatesAutoresizingMaskIntoConstraints = false

        inputBackgroundView.translatesAutoresizingMaskIntoConstraints = false

        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.backgroundColor = .clear
        textView.font = AgentComposerMetrics.textFont
        textView.isScrollEnabled = false
        textView.alwaysBounceVertical = false
        textView.keyboardDismissMode = .interactive
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainerInset = UIEdgeInsets(
            top: AgentComposerMetrics.contentVerticalInset,
            left: AgentComposerMetrics.contentHorizontalInset,
            bottom: AgentComposerMetrics.contentVerticalInset,
            right: AgentComposerMetrics.reservedTrailingTextInsetWithoutHints
        )
        textView.returnKeyType = .default
        textView.autocapitalizationType = .sentences
        textView.delegate = self
        textView.onHardwareSend = { [weak self] in
            self?.onSend?()
        }

        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.font = AgentComposerMetrics.placeholderFont
        placeholderLabel.text = lang("Ask anything")
        placeholderLabel.isUserInteractionEnabled = false

        var buttonConfiguration = UIButton.Configuration.plain()
        buttonConfiguration.contentInsets = .zero
        hintsButton.configuration = buttonConfiguration
        hintsButton.translatesAutoresizingMaskIntoConstraints = false
        hintsButton.tintAdjustmentMode = .normal
        hintsButton.backgroundColor = .clear
        hintsButton.setImage(
            UIImage(named: "ShowHints", in: AirBundle, compatibleWith: nil)?.withRenderingMode(.alwaysTemplate),
            for: .normal
        )
        hintsButton.setImage(
            UIImage(named: "HideHints", in: AirBundle, compatibleWith: nil)?.withRenderingMode(.alwaysTemplate),
            for: .selected
        )
        hintsButton.contentHorizontalAlignment = .center
        hintsButton.contentVerticalAlignment = .center
        hintsButton.imageView?.contentMode = .center
        hintsButton.addTarget(self, action: #selector(hintsButtonPressed), for: .touchUpInside)

        sendButton.configuration = buttonConfiguration
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        sendButton.tintAdjustmentMode = .normal
        sendButton.setImage(
            UIImage(named: "SendMessage", in: AirBundle, compatibleWith: nil)?.withRenderingMode(.alwaysTemplate),
            for: .normal
        )
        sendButton.layer.cornerRadius = AgentComposerMetrics.sendButtonCornerRadius
        sendButton.layer.cornerCurve = .continuous
        sendButton.clipsToBounds = true
        sendButton.contentHorizontalAlignment = .center
        sendButton.contentVerticalAlignment = .center
        sendButton.addTarget(self, action: #selector(sendButtonPressed), for: .touchUpInside)
        sendButton.imageView?.contentMode = .center

        dismissPanGestureRecognizer.addTarget(self, action: #selector(handleDismissPan(_:)))
        dismissPanGestureRecognizer.cancelsTouchesInView = false
        inputBackgroundView.addGestureRecognizer(dismissPanGestureRecognizer)

        addSubview(inputBackgroundView)
        inputBackgroundView.contentView.addSubview(textView)
        inputBackgroundView.contentView.addSubview(placeholderLabel)
        inputBackgroundView.contentView.addSubview(hintsButton)
        inputBackgroundView.contentView.addSubview(sendButton)

        NSLayoutConstraint.activate([
            inputBackgroundView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: AgentComposerMetrics.horizontalInset),
            inputBackgroundView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -AgentComposerMetrics.horizontalInset),
            inputBackgroundView.topAnchor.constraint(equalTo: topAnchor, constant: AgentComposerMetrics.verticalInset),
            inputBackgroundView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -AgentComposerMetrics.verticalInset),
            inputHeightConstraint,

            textView.leadingAnchor.constraint(equalTo: inputBackgroundView.contentView.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: inputBackgroundView.contentView.trailingAnchor),
            textView.topAnchor.constraint(equalTo: inputBackgroundView.contentView.topAnchor),
            textView.bottomAnchor.constraint(equalTo: inputBackgroundView.contentView.bottomAnchor),

            placeholderLabel.leadingAnchor.constraint(
                equalTo: inputBackgroundView.contentView.leadingAnchor,
                constant: AgentComposerMetrics.contentHorizontalInset
            ),
            placeholderLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: hintsButton.leadingAnchor,
                constant: -8
            ),
            placeholderLabel.topAnchor.constraint(
                equalTo: inputBackgroundView.contentView.topAnchor,
                constant: AgentComposerMetrics.contentVerticalInset
            ),

            hintsButtonTrailingConstraint,
            hintsButtonWidthConstraint,
            hintsButton.heightAnchor.constraint(equalToConstant: AgentComposerMetrics.hintsButtonHeight),
            hintsButton.centerYAnchor.constraint(equalTo: sendButton.centerYAnchor),

            sendButton.trailingAnchor.constraint(
                equalTo: inputBackgroundView.contentView.trailingAnchor,
                constant: -AgentComposerMetrics.sendButtonInset
            ),
            sendButton.topAnchor.constraint(
                equalTo: inputBackgroundView.contentView.topAnchor,
                constant: AgentComposerMetrics.sendButtonInset
            ),
            sendButton.widthAnchor.constraint(equalToConstant: AgentComposerMetrics.sendButtonWidth),
            sendButton.heightAnchor.constraint(equalToConstant: AgentComposerMetrics.sendButtonHeight)
        ])

        setHintsToggleVisible(false, isSelected: false)
        updatePlaceholderVisibility()
        updateInputHeightIfNeeded()
    }

    @objc private func hintsButtonPressed() {
        onHintsToggle?()
    }

    @objc private func sendButtonPressed() {
        onSend?()
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
        placeholderLabel.isHidden = !(textView.text?.isEmpty ?? true)
    }

    private func updateTrailingTextInset() {
        textView.textContainerInset.right = isHintsToggleVisible
            ? AgentComposerMetrics.reservedTrailingTextInsetWithHints
            : AgentComposerMetrics.reservedTrailingTextInsetWithoutHints
    }

    private func updateHintsButtonAppearance() {
        hintsButton.tintColor = .air.secondaryLabel
        var buttonConfiguration = hintsButton.configuration ?? .plain()
        buttonConfiguration.baseForegroundColor = .air.secondaryLabel
        buttonConfiguration.baseBackgroundColor = .clear
        hintsButton.configuration = buttonConfiguration
        hintsButton.backgroundColor = .clear
    }

    private func updateInputHeightIfNeeded() {
        guard inputBackgroundView.bounds.width > 0 else { return }

        let fittingSize = textView.sizeThatFits(
            CGSize(
                width: inputBackgroundView.bounds.width,
                height: .greatestFiniteMagnitude
            )
        )
        let clampedHeight = min(
            max(AgentComposerMetrics.minInputHeight, ceil(fittingSize.height)),
            AgentComposerMetrics.maxInputHeight
        )

        guard abs(inputHeightConstraint.constant - clampedHeight) > 0.5 else {
            textView.isScrollEnabled = clampedHeight >= AgentComposerMetrics.maxInputHeight
            return
        }

        inputHeightConstraint.constant = clampedHeight
        textView.isScrollEnabled = clampedHeight >= AgentComposerMetrics.maxInputHeight
        invalidateIntrinsicContentSize()
        superview?.setNeedsLayout()
        onLayoutHeightChanged?()
    }
}

extension AgentComposerView: UITextViewDelegate {
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
