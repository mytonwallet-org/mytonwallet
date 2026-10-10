import UIKit
import UIComponents
import WalletContext

private enum AgentComposerMetrics {
    static let composerBackgroundColor = UIColor.clear
    static let inputCornerRadius: CGFloat = 22
    static let sendButtonCornerRadius: CGFloat = 16
    static let minInputHeight: CGFloat = 44
    static let maxInputHeight: CGFloat = 132
    static let horizontalInset: CGFloat = 16
    static let verticalInset: CGFloat = 12
    static let contentHorizontalInset: CGFloat = 14
    static let contentVerticalInset: CGFloat = 10
    static let sendButtonInset: CGFloat = 6
    static let sendButtonWidth: CGFloat = 40
    static let sendButtonHeight: CGFloat = 32
    static let reservedTrailingTextInset: CGFloat = 56
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
    private let sendButton = UIButton(type: .system)
    private let dismissPanGestureRecognizer = UIPanGestureRecognizer()

    private lazy var inputHeightConstraint = inputBackgroundView.heightAnchor.constraint(equalToConstant: AgentComposerMetrics.minInputHeight)

    var onDraftTextChanged: (() -> Void)?
    var onSend: (() -> Void)?
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
        updateTextContainerInsets()
        updateInputHeightIfNeeded()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateTextContainerInsets()
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
        setSendEnabled(sendButton.isEnabled)
    }

    func setSendEnabled(_ isEnabled: Bool) {
        sendButton.isEnabled = isEnabled
        let foregroundColor: UIColor = isEnabled ? tintColor.foregroundForTintedBackground : .air.secondaryLabel
        sendButton.tintColor = foregroundColor
        var buttonConfiguration = sendButton.configuration ?? .plain()
        buttonConfiguration.baseForegroundColor = foregroundColor
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

    private func setupViews() {
        translatesAutoresizingMaskIntoConstraints = false

        inputBackgroundView.translatesAutoresizingMaskIntoConstraints = false

        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.backgroundColor = .clear
        textView.applyTextStyle(.body)
        textView.isScrollEnabled = false
        textView.alwaysBounceVertical = false
        textView.keyboardDismissMode = .interactive
        textView.textContainer.lineFragmentPadding = 0
        updateTextContainerInsets()
        textView.returnKeyType = .default
        textView.autocapitalizationType = .sentences
        textView.delegate = self
        textView.onHardwareSend = { [weak self] in
            self?.onSend?()
        }

        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.applyTextStyle(.body)
        placeholderLabel.text = lang("Ask anything")
        placeholderLabel.isUserInteractionEnabled = false

        var buttonConfiguration = UIButton.Configuration.plain()
        buttonConfiguration.contentInsets = .zero
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
                lessThanOrEqualTo: sendButton.leadingAnchor,
                constant: -8
            ),
            placeholderLabel.topAnchor.constraint(
                equalTo: inputBackgroundView.contentView.topAnchor,
                constant: AgentComposerMetrics.contentVerticalInset
            ),

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

        updatePlaceholderVisibility()
        updateInputHeightIfNeeded()
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

    private func updateTextContainerInsets() {
        let reservedInset = AgentComposerMetrics.reservedTrailingTextInset
        if effectiveUserInterfaceLayoutDirection == .rightToLeft {
            textView.textContainerInset = UIEdgeInsets(
                top: AgentComposerMetrics.contentVerticalInset,
                left: reservedInset,
                bottom: AgentComposerMetrics.contentVerticalInset,
                right: AgentComposerMetrics.contentHorizontalInset
            )
        } else {
            textView.textContainerInset = UIEdgeInsets(
                top: AgentComposerMetrics.contentVerticalInset,
                left: AgentComposerMetrics.contentHorizontalInset,
                bottom: AgentComposerMetrics.contentVerticalInset,
                right: reservedInset
            )
        }
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
