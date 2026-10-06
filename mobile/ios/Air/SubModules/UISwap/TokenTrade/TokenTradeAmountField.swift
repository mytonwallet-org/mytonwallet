import SwiftUI
import UIKit
import UIComponents
import WalletContext

struct TokenTradeAmountField: UIViewRepresentable {
    let model: TokenTradeModel
    let editor: TokenTradeEditor
    let maximumHeight: CGFloat

    func makeUIView(context: Context) -> TokenTradeTextField {
        let field = TokenTradeTextField()
        field.onChange = { [model] in model.userEditedInput($0) }
        editor.field = field
        return field
    }

    func updateUIView(_ field: TokenTradeTextField, context: Context) {
        field.maximumHeight = maximumHeight
        field.accessibilityLabel = lang("Amount") + ", " + (model.isTokenAmount ? model.token.symbol : model.currency.rawValue)
        field.configure(input: model.input, decimals: model.inputDecimals,
                        prefix: model.isTokenAmount ? "" : model.currency.sign,
                        suffix: model.isTokenAmount ? " " + model.token.symbol : "",
                        hasAmount: model.hasAmount)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: TokenTradeTextField, context: Context) -> CGSize? {
        let width = proposal.width ?? uiView.intrinsicContentSize.width
        return CGSize(width: width, height: uiView.fittingHeight(forWidth: width))
    }

    static func dismantleUIView(_ field: TokenTradeTextField, coordinator: ()) {
        field.resignFirstResponder()
    }
}

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

/// Only the number is editable. Affixes use the same scale and baseline as the number.
final class TokenTradeTextField: UITextField, UITextFieldDelegate {
    var onChange: ((TokenTradeAmountInput) -> Void)?
    var maximumHeight: CGFloat?
    private(set) var amountInput = TokenTradeAmountInput()
    private var decimals = 2
    private var hasAmount = false
    private let prefixLabel = UILabel()
    private let suffixLabel = UILabel()
    private var numberWidth: CGFloat = 0
    private var formattedSize: CGSize = .zero
    private var needsFormatting = true
    private let clearAmountButton = UIButton(type: .system)
    private var didRequestFocus = false
    private var separator: String { Locale.forNumberFormatters.decimalSeparator ?? "." }

    init() {
        super.init(frame: .zero)
        delegate = self
        borderStyle = .none
        keyboardType = .default
        if #available(iOS 17.0, *) { inlinePredictionType = .no }
        autocorrectionType = .no
        spellCheckingType = .no
        smartInsertDeleteType = .no
        if #available(iOS 18.0, *) { writingToolsBehavior = .none }
        inputAssistantItem.leadingBarButtonGroups = []
        inputAssistantItem.trailingBarButtonGroups = []
        contentVerticalAlignment = .top
        semanticContentAttribute = .forceLeftToRight
        textAlignment = .left
        tintColor = .tintColor
        accessibilityLabel = lang("Amount")
        accessibilityIdentifier = "tokenTrade.amount"
        leftView = prefixLabel
        rightView = suffixLabel
        leftViewMode = .always
        rightViewMode = .always
        prefixLabel.isAccessibilityElement = false
        suffixLabel.isAccessibilityElement = false
        // Suppress the system keyboard; the keypad belongs to the sheet's layout.
        inputView = UIView(frame: .zero)
        clearAmountButton.setImage(UIImage(systemName: "xmark.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17)), for: .normal)
        clearAmountButton.tintColor = .tertiaryLabel
        clearAmountButton.accessibilityLabel = lang("Clear")
        clearAmountButton.accessibilityIdentifier = "tokenTrade.clear"
        clearAmountButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            applyEdit(in: NSRange(location: 0, length: amountInput.text.utf16.count), replacement: "")
        }, for: .touchUpInside)
        addSubview(clearAmountButton)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { didRequestFocus = false }
        guard window != nil, !didRequestFocus else { return }
        didRequestFocus = true
        DispatchQueue.main.async { [weak self] in
            guard let self, window != nil else { return }
            becomeFirstResponder()
        }
    }

    func configure(input: TokenTradeAmountInput, decimals: Int, prefix: String, suffix: String, hasAmount: Bool) {
        self.decimals = decimals
        guard amountInput != input || prefixLabel.text != prefix || suffixLabel.text != suffix || self.hasAmount != hasAmount else { return }
        let changedInput = amountInput != input
        amountInput = input
        prefixLabel.text = prefix
        suffixLabel.text = suffix
        self.hasAmount = hasAmount
        needsFormatting = true
        formatAmount()
        if changedInput { selectedTextRange = textRange(from: endOfDocument, to: endOfDocument) }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        formatAmount()
        super.layoutSubviews()
        clearAmountButton.isHidden = amountInput.text.isEmpty
        let amountFont = font ?? .systemFont(ofSize: 72)
        let centerY = bounds.minY + amountFont.ascender - amountFont.capHeight / 2
        clearAmountButton.frame = CGRect(x: bounds.maxX - 44, y: max(0, centerY - 22), width: 44, height: 44)
    }

    func fittingHeight(forWidth width: CGFloat) -> CGFloat {
        formatAmount(size: CGSize(width: width, height: maximumHeight ?? 86))
        return font?.lineHeight ?? 86
    }

    private func formatAmount(size: CGSize? = nil) {
        let size = size ?? CGSize(width: bounds.width, height: maximumHeight ?? bounds.height)
        guard needsFormatting || formattedSize != size else { return }
        needsFormatting = false
        formattedSize = size
        let selection = selectedTextRange.map {
            (offset(from: beginningOfDocument, to: $0.start), offset(from: beginningOfDocument, to: $0.end))
        }
        let secondary: UIColor = hasAmount ? .air.secondaryLabel : .tertiaryLabel
        let number = amountInput.text.replacingOccurrences(of: ".", with: separator)
        let visibleNumber = number.isEmpty ? "0" : number

        func attributes(_ size: CGFloat, _ color: UIColor, scale: CGFloat) -> [NSAttributedString.Key: Any] {
            [.font: UIFont.roundedNative(ofSize: size * scale, weight: .bold), .foregroundColor: color, .kern: -0.4 * scale]
        }
        func styledNumber(scale: CGFloat) -> NSAttributedString {
            let value = NSMutableAttributedString(string: visibleNumber, attributes: attributes(72, hasAmount ? .label : secondary, scale: scale))
            if let range = visibleNumber.range(of: separator) {
                let fraction = NSRange(range.lowerBound..<visibleNumber.endIndex, in: visibleNumber)
                value.addAttributes(attributes(56, secondary, scale: scale), range: fraction)
            }
            return value
        }
        func fullWidth(scale: CGFloat) -> CGFloat {
            styledNumber(scale: scale).size().width
                + ceil(NSAttributedString(string: prefixLabel.text ?? "", attributes: attributes(64, secondary, scale: scale)).size().width)
                + ceil(NSAttributedString(string: suffixLabel.text ?? "", attributes: attributes(32, secondary, scale: scale)).size().width)
        }
        let availableWidth = max(1, size.width - clearButtonReservedWidth - 4)
        var scale = min(1, max(0.2, size.height / 86), max(0.2, availableWidth / max(1, fullWidth(scale: 1))))
        // Rounded font metrics change with point size; measure again after scaling.
        for _ in 0..<3 {
            let width = fullWidth(scale: scale)
            guard width > availableWidth else { break }
            scale = max(0.2, scale * (availableWidth - 1) / width)
        }
        font = .roundedNative(ofSize: 72 * scale, weight: .bold)
        prefixLabel.font = .roundedNative(ofSize: 64 * scale, weight: .bold)
        suffixLabel.font = .roundedNative(ofSize: 32 * scale, weight: .bold)
        prefixLabel.attributedText = NSAttributedString(string: prefixLabel.text ?? "", attributes: attributes(64, secondary, scale: scale))
        suffixLabel.attributedText = NSAttributedString(string: suffixLabel.text ?? "", attributes: attributes(32, secondary, scale: scale))
        let styled = styledNumber(scale: scale)
        numberWidth = styled.size().width
        defaultTextAttributes = attributes(72, .label, scale: scale)
        attributedText = number.isEmpty ? NSAttributedString(string: "") : styled
        attributedPlaceholder = number.isEmpty ? styled : nil
        if let selection { select(start: selection.0, end: selection.1) }
    }

    override func textRect(forBounds bounds: CGRect) -> CGRect {
        let width = prefixLabel.intrinsicContentSize.width
        return CGRect(x: bounds.minX + max(0, width), y: bounds.minY,
                      width: max(0, bounds.width - clearButtonReservedWidth - max(0, width) - max(0, suffixLabel.intrinsicContentSize.width)),
                      height: font?.lineHeight ?? 86)
    }

    private var clearButtonReservedWidth: CGFloat { amountInput.text.isEmpty ? 0 : 52 }

    override func editingRect(forBounds bounds: CGRect) -> CGRect { textRect(forBounds: bounds) }
    override func placeholderRect(forBounds bounds: CGRect) -> CGRect { textRect(forBounds: bounds) }

    override func caretRect(for position: UITextPosition) -> CGRect {
        var rect = super.caretRect(for: position)
        guard let attributedText, let font else { return rect }
        let decimalRange = (attributedText.string as NSString).range(of: separator)
        guard decimalRange.location != NSNotFound,
              offset(from: beginningOfDocument, to: position) >= NSMaxRange(decimalRange),
              let fractionFont = attributedText.attribute(.font, at: decimalRange.location, effectiveRange: nil) as? UIFont else { return rect }
        rect.origin.y = editingRect(forBounds: bounds).minY + font.ascender - fractionFont.ascender
        rect.size.height = fractionFont.lineHeight
        return rect
    }

    private func affixRect(_ label: UILabel, x: CGFloat, bounds: CGRect) -> CGRect {
        let baseline = bounds.minY + (font?.ascender ?? 0)
        return CGRect(x: x, y: baseline - label.font.ascender, width: max(0, label.intrinsicContentSize.width), height: label.font.lineHeight)
    }

    override func leftViewRect(forBounds bounds: CGRect) -> CGRect { affixRect(prefixLabel, x: bounds.minX, bounds: bounds) }
    override func rightViewRect(forBounds bounds: CGRect) -> CGRect {
        affixRect(suffixLabel, x: textRect(forBounds: bounds).minX + numberWidth + 2, bounds: bounds)
    }

    private func select(start: Int, end: Int) {
        let count = (text ?? "").utf16.count
        guard let start = position(from: beginningOfDocument, offset: min(start, count)),
              let end = position(from: beginningOfDocument, offset: min(end, count)) else { return }
        selectedTextRange = textRange(from: start, to: end)
    }

    private var selectionRange: NSRange {
        guard let selection = selectedTextRange else { return NSRange(location: amountInput.text.utf16.count, length: 0) }
        return NSRange(location: offset(from: beginningOfDocument, to: selection.start),
                       length: offset(from: selection.start, to: selection.end))
    }

    override func insertText(_ text: String) {
        applyEdit(in: selectionRange, replacement: text)
    }

    override func replace(_ range: UITextRange, withText text: String) {
        applyEdit(in: NSRange(location: offset(from: beginningOfDocument, to: range.start),
                              length: offset(from: range.start, to: range.end)), replacement: text)
    }

    override func deleteBackward() {
        var range = selectionRange
        if range.length == 0 {
            guard range.location > 0 else { return }
            range.location -= 1
            range.length = 1
        }
        applyEdit(in: range, replacement: "")
    }

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        applyEdit(in: range, replacement: string)
        return false
    }

    private func applyEdit(in range: NSRange, replacement string: String) {
        guard let edit = amountInput.replacing(range, with: string, decimals: decimals) else { return }
        amountInput = edit.input
        hasAmount = amountInput.amount(decimals: decimals) > 0
        needsFormatting = true
        formatAmount()
        select(start: edit.caret, end: edit.caret)
        setNeedsLayout()
        onChange?(amountInput)
        sendActions(for: .editingChanged)
    }
}

struct TokenTradeKeypadView: UIViewRepresentable {
    let editor: TokenTradeEditor
    let hasText: Bool

    func makeUIView(context: Context) -> TokenTradeKeypad { TokenTradeKeypad(editor: editor) }
    func updateUIView(_ view: TokenTradeKeypad, context: Context) { view.updateDelete(isEnabled: hasText) }
}

final class TokenTradeKeypad: UIView {
    private let deleteButton = TokenTradeKeyButton()

    init(editor: TokenTradeEditor) {
        super.init(frame: .zero)
        backgroundColor = .air.background
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
                let button = isDelete ? deleteButton : TokenTradeKeyButton()
                button.tintColor = .label
                if isDelete {
                    button.setImage(UIImage(systemName: "delete.left.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 23)), for: .normal)
                } else {
                    button.setTitle(key, for: .normal)
                    button.setTitleColor(.label, for: .normal)
                    button.titleLabel?.font = .systemFont(ofSize: 26)
                }
                button.accessibilityTraits.insert(.keyboardKey)
                button.accessibilityLabel = isDelete ? lang("Delete") : key
                button.accessibilityIdentifier = isDelete ? "tokenTrade.delete" : "tokenTrade.key." + key
                button.addAction(UIAction { [weak editor] _ in
                    if isDelete { editor?.deleteBackward() } else { editor?.insert(key) }
                    Haptics.play(.lightTap)
                }, for: .touchUpInside)
                columns.addArrangedSubview(button)
            }
        }
        updateDelete(isEnabled: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func updateDelete(isEnabled: Bool) {
        deleteButton.isEnabled = isEnabled
        deleteButton.alpha = isEnabled ? 1 : 0
        deleteButton.accessibilityElementsHidden = !isEnabled
    }
}

/// Animate the visible key without shrinking its touch target.
private final class TokenTradeKeyButton: UIButton {
    private let pressedBackground = UIView()

    init() {
        super.init(frame: .zero)
        pressedBackground.backgroundColor = .air.secondaryFill
        pressedBackground.layer.cornerRadius = 16
        pressedBackground.layer.cornerCurve = .continuous
        pressedBackground.isUserInteractionEnabled = false
        pressedBackground.alpha = 0
        insertSubview(pressedBackground, at: 0)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        pressedBackground.bounds = CGRect(origin: .zero, size: bounds.insetBy(dx: 4, dy: 4).size)
        pressedBackground.center = CGPoint(x: bounds.midX, y: bounds.midY)
    }

    override var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue else { return }
            let pressed = isHighlighted
            let transform = pressed && !UIAccessibility.isReduceMotionEnabled
                ? CGAffineTransform(translationX: 0, y: 2).scaledBy(x: 0.88, y: 0.88)
                : .identity
            UIView.animate(withDuration: pressed ? 0.1 : 0.2, delay: 0,
                           options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut]) {
                self.titleLabel?.transform = transform
                self.imageView?.transform = transform
                self.pressedBackground.transform = transform
                self.pressedBackground.alpha = pressed ? 1 : 0
            }
        }
    }
}
