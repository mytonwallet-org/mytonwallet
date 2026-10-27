import UIKit
import UIComponents
import WalletContext

@MainActor final class TokenTradeEditor {
    weak var field: TokenTradeTextField?

    func insert(_ text: String) {
        field?.becomeFirstResponder()
        field?.insertText(text)
    }

    func deleteBackward() {
        field?.becomeFirstResponder()
        field?.deleteBackward()
    }
}

/// Buy/Sell supplies decimal validation; the reusable field owns editing and motion.
final class TokenTradeTextField: HeroAmountField {
    var onChange: ((TokenTradeAmountInput) -> Void)?
    var amountInput: TokenTradeAmountInput { TokenTradeAmountInput(text: inputText) }
    private var decimals = 2

    override init() {
        super.init()
        accessibilityIdentifier = "tokenTrade.amount"
        clearAccessibilityIdentifier = "tokenTrade.clear"
        edit = { [weak self] text, range, replacement in
            guard let self,
                  let edit = TokenTradeAmountInput(text: text).replacing(range, with: replacement, decimals: decimals) else { return nil }
            return Edit(text: edit.input.text, caret: edit.caret)
        }
        onTextChange = { [weak self] text in self?.onChange?(TokenTradeAmountInput(text: text)) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(input: TokenTradeAmountInput, decimals: Int, prefix: String, suffix: String, hasAmount: Bool) {
        self.decimals = decimals
        configure(text: input.text, prefix: prefix, suffix: suffix, hasAmount: hasAmount)
    }
}

final class TokenTradeKeypad: UIView {
    private let deleteButton = TokenTradeKeyButton(
        image: UIImage(systemName: "delete.left.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 23)),
        repeatsOnHold: true
    )

    init(editor: TokenTradeEditor) {
        super.init(frame: .zero)
        backgroundColor = .air.pickerBackground
        autoresizingMask = [.flexibleWidth]
        let rows = UIStackView()
        rows.axis = .vertical
        rows.spacing = 0
        rows.distribution = .fillEqually
        rows.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rows)
        let preferredWidth = rows.widthAnchor.constraint(equalTo: widthAnchor, constant: -32)
        preferredWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            rows.centerXAnchor.constraint(equalTo: centerXAnchor),
            rows.widthAnchor.constraint(lessThanOrEqualToConstant: 420),
            rows.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
            preferredWidth,
            rows.topAnchor.constraint(equalTo: topAnchor),
            rows.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        for row in 0..<4 {
            let columns = UIStackView()
            columns.spacing = 0
            columns.distribution = .fillEqually
            rows.addArrangedSubview(columns)
            for column in 0..<3 {
                let isDelete = row == 3 && column == 2
                let key = row < 3 ? String(row * 3 + column + 1) : column == 0 ? (Locale.forNumberFormatters.decimalSeparator ?? ".") : "0"
                let button = isDelete ? deleteButton : TokenTradeKeyButton(title: key)
                button.accessibilityTraits.insert(.keyboardKey)
                button.accessibilityLabel = isDelete ? lang("Delete") : key
                button.accessibilityIdentifier = isDelete ? "tokenTrade.delete" : "tokenTrade.key." + key
                button.onPress = { [weak editor] in
                    if isDelete { editor?.deleteBackward() } else { editor?.insert(key) }
                    Haptics.play(.lightTap)
                }
                columns.addArrangedSubview(button)
            }
        }
        updateDelete(isEnabled: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func updateDelete(isEnabled: Bool) {
        guard deleteButton.isEnabled != isEnabled else { return }
        deleteButton.isEnabled = isEnabled
        deleteButton.accessibilityElementsHidden = !isEnabled
        let environment = CardBackgroundAnimationEnvironment.shared
        let animated = window != nil && environment.animationsEnabled && environment.applicationActive
            && !environment.lowPowerMode && !environment.reduceMotion
        let changes = {
            self.deleteButton.alpha = isEnabled ? 1 : 0
            self.deleteButton.transform = isEnabled || !animated ? .identity : CGAffineTransform(scaleX: 0.8, y: 0.8)
        }
        if animated {
            if isEnabled, deleteButton.alpha == 0 { deleteButton.transform = CGAffineTransform(scaleX: 0.8, y: 0.8) }
            UIView.animate(withDuration: 0.24, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut], animations: changes)
        } else {
            deleteButton.layer.removeAllAnimations()
            UIView.performWithoutAnimation(changes)
        }
    }
}

/// Animate the visible key without shrinking its touch target.
private final class TokenTradeKeyButton: UIButton {
    var onPress: (() -> Void)?
    private let contentView = UIView()
    private let pressedBackground = UIView()
    private let keyLabel = UILabel()
    private let keyImageView = UIImageView()
    private let repeatsOnHold: Bool
    private var repeatTask: Task<Void, Never>?
    private var didRepeat = false

    init(title: String? = nil, image: UIImage? = nil, repeatsOnHold: Bool = false) {
        self.repeatsOnHold = repeatsOnHold
        super.init(frame: .zero)
        contentView.isUserInteractionEnabled = false
        contentView.accessibilityElementsHidden = true
        addSubview(contentView)
        pressedBackground.backgroundColor = .air.secondaryFill
        pressedBackground.layer.cornerRadius = 16
        pressedBackground.layer.cornerCurve = .continuous
        pressedBackground.alpha = 0
        contentView.addSubview(pressedBackground)
        keyLabel.text = title
        keyLabel.font = .systemFont(ofSize: 26)
        keyLabel.textColor = .label
        keyLabel.textAlignment = .center
        contentView.addSubview(keyLabel)
        keyImageView.image = image
        keyImageView.tintColor = .label
        keyImageView.contentMode = .center
        contentView.addSubview(keyImageView)
        addAction(UIAction { [weak self] _ in
            self?.didRepeat = false
            self?.startRepeating()
        }, for: .touchDown)
        addAction(UIAction { [weak self] _ in self?.startRepeating() }, for: .touchDragEnter)
        addAction(UIAction { [weak self] _ in
            guard let self else { return }
            stopRepeating()
            if !didRepeat { onPress?() }
        }, for: .touchUpInside)
        addAction(UIAction { [weak self] _ in self?.stopRepeating() }, for: [.touchUpOutside, .touchCancel, .touchDragExit])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { repeatTask?.cancel() }

    private func startRepeating() {
        stopRepeating()
        guard repeatsOnHold, isEnabled else { return }
        repeatTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            while !Task.isCancelled {
                if let self {
                    didRepeat = true
                    onPress?()
                } else {
                    return
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    private func stopRepeating() {
        repeatTask?.cancel()
        repeatTask = nil
    }

    override var isEnabled: Bool {
        didSet { if !isEnabled { stopRepeating() } }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { stopRepeating() }
    }

    override func accessibilityActivate() -> Bool {
        guard isEnabled else { return false }
        onPress?()
        return true
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // UIKit relayouts its own title/image views when highlighted; animate our container instead.
        contentView.bounds = bounds
        contentView.center = CGPoint(x: bounds.midX, y: bounds.midY)
        pressedBackground.frame = contentView.bounds.insetBy(dx: 4, dy: 4)
        keyLabel.frame = contentView.bounds
        keyImageView.frame = contentView.bounds
    }

    override var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue else { return }
            let pressed = isHighlighted
            let environment = CardBackgroundAnimationEnvironment.shared
            let animated = environment.animationsEnabled && environment.applicationActive
                && !environment.lowPowerMode && !environment.reduceMotion
            let transform = pressed && animated
                ? CGAffineTransform(translationX: 0, y: 2).scaledBy(x: 0.88, y: 0.88)
                : .identity
            let changes = {
                self.contentView.transform = transform
                self.pressedBackground.alpha = pressed ? 1 : 0
            }
            if animated {
                UIView.animate(withDuration: pressed ? 0.1 : 0.2, delay: 0,
                               options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut], animations: changes)
            } else {
                contentView.layer.removeAllAnimations()
                pressedBackground.layer.removeAllAnimations()
                UIView.performWithoutAnimation(changes)
            }
        }
    }
}
