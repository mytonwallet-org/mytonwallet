import UIKit
import CoreText
import WalletContext

/// Only the number is editable. Affixes use the same scale and baseline as the number.
open class HeroAmountField: UITextField, UITextFieldDelegate {
    public struct Edit {
        public let text: String
        public let caret: Int

        public init(text: String, caret: Int) {
            self.text = text
            self.caret = caret
        }
    }

    /// Validation belongs to the feature; a rejected edit returns nil.
    public var edit: ((_ text: String, _ range: NSRange, _ replacement: String) -> Edit?)?
    public var onTextChange: ((String) -> Void)?
    public var maximumHeight: CGFloat? {
        didSet {
            if maximumHeight != oldValue {
                animateNextLayout = hasConfiguration
                needsFormatting = true
                setNeedsLayout()
            }
        }
    }
    public var clearAccessibilityIdentifier: String? {
        get { clearAmountButton.accessibilityIdentifier }
        set { clearAmountButton.accessibilityIdentifier = newValue }
    }
    public var focusesOnAppearance = true
    public var usesSystemKeyboard = false {
        didSet { inputView = usesSystemKeyboard ? nil : UIView(frame: .zero); reloadInputViews() }
    }
    public var caretColor: UIColor = .systemBlue {
        didSet { updateSelectionAppearance(); setNeedsLayout() }
    }
    public var isError = false {
        didSet {
            if isError != oldValue {
                animateNextLayout = hasConfiguration
                needsFormatting = true
                setNeedsLayout()
            }
        }
    }
    public private(set) var inputText = ""
    private var hasAmount = false
    private let prefixLabel = UILabel()
    private let suffixLabel = UILabel()
    private var numberWidth: CGFloat = 0
    private var nativeTextOrigin: CGFloat?
    private var nativeTextBaseline: CGFloat?
    private var formattedSize: CGSize = .zero
    private var needsFormatting = true
    private let clearAmountButton = UIButton(type: .system)
    private var didRequestFocus = false
    public let amountPresentation = TelegramAmountPresentation(frame: .zero)
    private var presentationText = NSAttributedString(string: "0")
    private var animateNextLayout = false
    private var switchesUnit = false
    private var replacesValue = false
    private var motionEnabled = true
    private var clearButtonVisible = false
    private var increasesValue = true
    private var hasConfiguration = false
    private var applyingText = false
    private var nativeInteraction = false
    private var lastSelection = NSRange(location: 0, length: 0)
    private var separator: String { Locale.forNumberFormatters.decimalSeparator ?? "." }
    private static let amountParagraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.alignment = .left
        style.baseWritingDirection = .leftToRight
        return style
    }()

    public init() {
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
        defaultTextAttributes[.paragraphStyle] = Self.amountParagraphStyle
        tintColor = .clear
        accessibilityLabel = lang("Amount")
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
        clearAmountButton.alpha = 0
        clearAmountButton.isUserInteractionEnabled = false
        clearAmountButton.accessibilityLabel = lang("Clear")
        clearAmountButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            applyEdit(in: NSRange(location: 0, length: inputText.utf16.count), replacement: "")
        }, for: .touchUpInside)
        addSubview(clearAmountButton)
        amountPresentation.onPresentationChanged = { [weak self] presenting in
            self?.setNativeTextVisible(!presenting)
        }
        addSubview(amountPresentation)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override func baseWritingDirection(for position: UITextPosition, in direction: UITextStorageDirection) -> NSWritingDirection {
        .leftToRight
    }

    public override func setBaseWritingDirection(_ writingDirection: NSWritingDirection, for range: UITextRange) {
        super.setBaseWritingDirection(.leftToRight, for: range)
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            didRequestFocus = false
            amountPresentation.cancelInteraction()
        }
        guard focusesOnAppearance, window != nil, !didRequestFocus else { return }
        didRequestFocus = true
        DispatchQueue.main.async { [weak self] in
            guard let self, window != nil else { return }
            becomeFirstResponder()
        }
    }

    public func configure(text: String, prefix: String, suffix: String, hasAmount: Bool) {
        let suffix = suffix.trimmingCharacters(in: .whitespaces)
        guard inputText != text || prefixLabel.text != prefix || suffixLabel.text != suffix || self.hasAmount != hasAmount else { return }
        let changedInput = inputText != text
        switchesUnit = hasConfiguration && (prefixLabel.text != prefix || suffixLabel.text != suffix)
        replacesValue = changedInput && !switchesUnit
        animateNextLayout = animateNextLayout || (hasConfiguration && (changedInput || switchesUnit || self.hasAmount != hasAmount))
        increasesValue = (Decimal(string: text) ?? 0) >= (Decimal(string: inputText) ?? 0)
        hasConfiguration = true
        if changedInput || switchesUnit { nativeInteraction = false }
        inputText = text
        prefixLabel.text = prefix
        suffixLabel.text = suffix
        self.hasAmount = hasAmount
        needsFormatting = true
        formatAmount()
        if changedInput {
            applyingText = true
            selectedTextRange = textRange(from: endOfDocument, to: endOfDocument)
            lastSelection = selectionRange
            applyingText = false
        }
        setNeedsLayout()
    }

    public func configureAnimation(active: Bool, animated: Bool) {
        motionEnabled = active && animated
        amountPresentation.configure(active: active, animated: animated)
        if !motionEnabled {
            clearAmountButton.layer.removeAllAnimations()
            clearAmountButton.alpha = inputText.isEmpty ? 0 : 1
            clearAmountButton.transform = .identity
        }
        setNeedsLayout()
    }

    public override func layoutSubviews() {
        formatAmount()
        nativeTextOrigin = nil
        nativeTextBaseline = nil
        super.layoutSubviews()
        let nativeCaret = super.caretRect(for: beginningOfDocument)
        // UIKit can return its unlaid-out origin (zero) even with a window.
        // It must not move the number into the prefix's reserved space.
        if window != nil, !inputText.isEmpty, !nativeCaret.isNull, !nativeCaret.isInfinite,
           nativeCaret.height > 0, nativeCaret.minX >= textRect(forBounds: bounds).minX, let font {
            nativeTextOrigin = nativeCaret.minX
            nativeTextBaseline = nativeCaret.midY + (font.ascender + font.descender) / 2
        }
        prefixLabel.frame = leftViewRect(forBounds: bounds)
        suffixLabel.frame = rightViewRect(forBounds: bounds)
        updateClearButton()
        let amountFont = font ?? .systemFont(ofSize: 72)
        let centerY = amountTextBaseline - amountFont.capHeight / 2
        clearAmountButton.bounds = CGRect(x: 0, y: 0, width: 44, height: 44)
        clearAmountButton.center = CGPoint(x: bounds.maxX - 22, y: max(22, centerY))
        // The renderer interpolates glyphs and the caret itself. A parent layout animation
        // must not also animate its canvas from the previous (initially empty) frame.
        UIView.performWithoutAnimation { updatePresentation() }
    }

    private func updatePresentation() {
        amountPresentation.frame = bounds
        let baseline = amountTextBaseline
        let prefix = prefixLabel.attributedText ?? NSAttributedString(string: "")
        let suffix = suffixLabel.attributedText ?? NSAttributedString(string: "")
        let runs: [TelegramAmountPresentation.TextRun] = [
            .init(text: prefix, origin: CGPoint(x: leftViewRect(forBounds: bounds).minX, y: baseline), part: .prefix),
            .init(text: presentationText, origin: CGPoint(x: amountTextOrigin, y: baseline)),
            .init(text: suffix, origin: CGPoint(x: rightViewRect(forBounds: bounds).minX, y: baseline), part: .suffix)
        ]
        let caret = isFirstResponder && selectionRange.length == 0
            ? amountCaretRect(for: selectedTextRange?.end ?? endOfDocument) : nil
        amountPresentation.update(runs: runs, decimalSeparator: separator, caret: caret,
            caretColor: caretColor, placeholder: inputText.isEmpty,
            animated: animateNextLayout && !nativeInteraction && selectionRange.length == 0,
            switchesUnit: switchesUnit, increasesValue: increasesValue, replacesValue: replacesValue)
        animateNextLayout = false
        switchesUnit = false
        replacesValue = false
        bringSubviewToFront(amountPresentation)
        bringSubviewToFront(clearAmountButton)
    }

    private func updateClearButton() {
        let visible = !inputText.isEmpty
        guard clearButtonVisible != visible else { return }
        clearButtonVisible = visible
        clearAmountButton.isUserInteractionEnabled = visible
        clearAmountButton.accessibilityElementsHidden = !visible
        let changes = {
            self.clearAmountButton.alpha = visible ? 1 : 0
            self.clearAmountButton.transform = visible ? .identity : CGAffineTransform(scaleX: 0.75, y: 0.75)
        }
        if motionEnabled, window != nil, !UIAccessibility.isReduceMotionEnabled {
            if visible, clearAmountButton.alpha == 0 { clearAmountButton.transform = CGAffineTransform(scaleX: 0.75, y: 0.75) }
            UIView.animate(withDuration: 0.24, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut], animations: changes)
        } else {
            UIView.performWithoutAnimation(changes)
        }
    }

    private func setNativeTextVisible(_ visible: Bool) {
        let previous = applyingText
        applyingText = true
        defer { applyingText = previous }
        let selection = selectionRange
        let value = NSMutableAttributedString(attributedString: presentationText)
        if !visible { value.addAttribute(.foregroundColor, value: UIColor.clear, range: NSRange(location: 0, length: value.length)) }
        let nativeText = inputText.isEmpty ? NSAttributedString(string: "") : value
        if attributedText?.isEqual(to: nativeText) != true { attributedText = nativeText }
        attributedPlaceholder = inputText.isEmpty ? value : nil
        prefixLabel.alpha = visible ? 1 : 0
        suffixLabel.alpha = visible ? 1 : 0
        select(start: selection.location, end: NSMaxRange(selection))
        bringSubviewToFront(amountPresentation)
        bringSubviewToFront(clearAmountButton)
    }

    public func fittingHeight(forWidth width: CGFloat) -> CGFloat {
        // SwiftUI can measure several proposals before UIKit receives its final bounds.
        // Measuring must not rewrite the field and invalidate the layout being measured.
        amountFormat(size: CGSize(width: width, height: maximumHeight ?? 86)).font.lineHeight
    }

    private struct AmountFormat {
        let font: UIFont
        let prefixFont: UIFont
        let suffixFont: UIFont
        let prefix: NSAttributedString
        let suffix: NSAttributedString
        let number: NSAttributedString
        let defaultAttributes: [NSAttributedString.Key: Any]
    }

    private func formatAmount() {
        let size = CGSize(width: bounds.width, height: maximumHeight ?? bounds.height)
        guard needsFormatting || formattedSize != size else { return }
        let previous = applyingText
        applyingText = true
        defer { applyingText = previous }
        needsFormatting = false
        formattedSize = size
        let selection = selectedTextRange.map {
            (offset(from: beginningOfDocument, to: $0.start), offset(from: beginningOfDocument, to: $0.end))
        }
        let format = amountFormat(size: size)
        font = format.font
        prefixLabel.font = format.prefixFont
        suffixLabel.font = format.suffixFont
        prefixLabel.attributedText = format.prefix
        suffixLabel.attributedText = format.suffix
        presentationText = format.number
        numberWidth = format.number.size().width
        defaultTextAttributes = format.defaultAttributes
        attributedText = inputText.isEmpty ? NSAttributedString(string: "") : format.number
        attributedPlaceholder = inputText.isEmpty ? format.number : nil
        if let selection { select(start: selection.0, end: selection.1) }
        if amountPresentation.isPresentingText { setNativeTextVisible(false) }
    }

    private func amountFormat(size: CGSize) -> AmountFormat {
        let secondary: UIColor = isError ? .air.error : hasAmount ? .air.secondaryLabel : .tertiaryLabel
        let numberColor: UIColor = isError ? .air.error : hasAmount ? .label : secondary
        let number = inputText.replacingOccurrences(of: ".", with: separator)
        let visibleNumber = number.isEmpty ? "0" : number

        func attributes(_ size: CGFloat, _ color: UIColor, scale: CGFloat) -> [NSAttributedString.Key: Any] {
            [.font: UIFont.roundedNative(ofSize: size * scale, weight: .bold), .foregroundColor: color,
             .kern: -0.4 * scale, .paragraphStyle: Self.amountParagraphStyle]
        }
        func styledNumber(scale: CGFloat) -> NSAttributedString {
            let value = NSMutableAttributedString(string: visibleNumber, attributes: attributes(72, numberColor, scale: scale))
            if let range = visibleNumber.range(of: separator) {
                let fraction = NSRange(range.lowerBound..<visibleNumber.endIndex, in: visibleNumber)
                value.addAttributes(attributes(56, numberColor, scale: scale), range: fraction)
            }
            return value
        }
        func fullWidth(scale: CGFloat) -> CGFloat {
            styledNumber(scale: scale).size().width
                + ceil(NSAttributedString(string: prefixLabel.text ?? "", attributes: attributes(64, secondary, scale: scale)).size().width)
                + ceil(NSAttributedString(string: suffixLabel.text ?? "", attributes: attributes(32, secondary, scale: scale)).size().width)
                + suffixSpacing
        }
        let availableWidth = max(1, size.width - clearButtonReservedWidth - 4)
        var scale = min(1, max(0.2, size.height / 86), availableWidth / max(1, fullWidth(scale: 1)))
        // Rounded font metrics change with point size; measure again after scaling.
        for _ in 0..<3 {
            let width = fullWidth(scale: scale)
            guard width > availableWidth else { break }
            scale = max(0.01, scale * max(1, availableWidth - 1) / width)
        }
        return AmountFormat(
            font: .roundedNative(ofSize: 72 * scale, weight: .bold),
            prefixFont: .roundedNative(ofSize: 64 * scale, weight: .bold),
            suffixFont: .roundedNative(ofSize: 32 * scale, weight: .bold),
            prefix: NSAttributedString(string: prefixLabel.text ?? "", attributes: attributes(64, secondary, scale: scale)),
            suffix: NSAttributedString(string: suffixLabel.text ?? "", attributes: attributes(32, secondary, scale: scale)),
            number: styledNumber(scale: scale),
            defaultAttributes: attributes(72, isError ? .air.error : .label, scale: scale)
        )
    }

    public override func textRect(forBounds bounds: CGRect) -> CGRect {
        let width = prefixLabel.intrinsicContentSize.width
        return CGRect(x: bounds.minX + max(0, width), y: bounds.minY,
                      width: max(0, bounds.width - clearButtonReservedWidth - max(0, width) - max(0, suffixLabel.intrinsicContentSize.width) - suffixSpacing),
                      height: font?.lineHeight ?? 86)
    }

    private var clearButtonReservedWidth: CGFloat { inputText.isEmpty ? 0 : 52 }
    private var suffixSpacing: CGFloat { suffixLabel.text?.isEmpty == false ? 18 : 0 }

    public override func editingRect(forBounds bounds: CGRect) -> CGRect { textRect(forBounds: bounds) }
    public override func placeholderRect(forBounds bounds: CGRect) -> CGRect { textRect(forBounds: bounds) }

    public override func caretRect(for position: UITextPosition) -> CGRect {
        // UIKit may cache the insertion view before our first layout. Keep its
        // geometry and tint suppressed independently of the animation lifecycle.
        if selectionRange.length == 0 { return .zero }
        return amountCaretRect(for: position)
    }

    public func amountCaretRect(for position: UITextPosition) -> CGRect {
        guard let font else { return .zero }
        let offset = self.offset(from: beginningOfDocument, to: position)
        let index = min(presentationText.length - 1, max(0, offset - 1))
        let caretFont = presentationText.length > 0
            ? (presentationText.attribute(.font, at: index, effectiveRange: nil) as? UIFont ?? font) : font
        let scale = font.pointSize / 72
        // Figma's hidden carets share the bottom of the 62pt amount line box:
        // 58pt beside integers, 48pt beside decimals, both 2.5pt wide.
        let height = (caretFont.pointSize < font.pointSize ? 48 : 58) * scale
        let bottom = amountTextBaseline + (62 * scale - font.ascender - font.descender) / 2
        let line = CTLineCreateWithAttributedString(presentationText)
        let visibleOffset = inputText.isEmpty ? presentationText.length : min(offset, presentationText.length)
        let advance = CTLineGetOffsetForStringIndex(line, visibleOffset, nil)
        let trailingGap: CGFloat = visibleOffset == presentationText.length ? 2.5 * scale : 0
        let x = amountTextOrigin + advance + trailingGap
        return CGRect(x: x, y: bottom - height, width: 2.5 * scale, height: height)
    }

    public override var selectedTextRange: UITextRange? {
        didSet {
            updateSelectionAppearance()
            if !applyingText { setNeedsLayout() }
        }
    }

    private func updateSelectionAppearance() {
        let color: UIColor = selectedTextRange?.isEmpty == false ? caretColor : .clear
        if tintColor != color { tintColor = color }
    }

    public var amountTextOrigin: CGFloat {
        nativeTextOrigin ?? textRect(forBounds: bounds).minX
    }

    public var amountTextBaseline: CGFloat {
        guard let font else { return bounds.minY }
        return nativeTextBaseline ?? (textRect(forBounds: bounds).midY + (font.ascender + font.descender) / 2)
    }

    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        if self.point(inside: point, with: event), event?.type == .touches,
           hit !== clearAmountButton, hit?.isDescendant(of: clearAmountButton) != true {
            nativeInteraction = true
            amountPresentation.cancelInteraction()
            setNeedsLayout()
        }
        return hit
    }

    public func textFieldDidChangeSelection(_ textField: UITextField) {
        guard !applyingText, lastSelection != selectionRange else { return }
        lastSelection = selectionRange
        nativeInteraction = true
        animateNextLayout = false
        amountPresentation.cancelInteraction()
        updateSelectionAppearance()
        amountPresentation.resetCaretBlink()
        setNeedsLayout()
        layoutIfNeeded()
    }

    public func textFieldDidBeginEditing(_ textField: UITextField) {
        updateSelectionAppearance()
        amountPresentation.resetCaretBlink()
        setNeedsLayout()
    }

    public func textFieldDidEndEditing(_ textField: UITextField) { amountPresentation.cancelInteraction() }

    private func affixRect(_ label: UILabel, x: CGFloat, bounds: CGRect) -> CGRect {
        let baseline = amountTextBaseline
        return CGRect(x: x, y: baseline - label.font.ascender, width: max(0, label.intrinsicContentSize.width), height: label.font.lineHeight)
    }

    public override func leftViewRect(forBounds bounds: CGRect) -> CGRect { affixRect(prefixLabel, x: bounds.minX, bounds: bounds) }
    public override func rightViewRect(forBounds bounds: CGRect) -> CGRect {
        affixRect(suffixLabel, x: amountTextOrigin + numberWidth + suffixSpacing, bounds: bounds)
    }

    private func select(start: Int, end: Int) {
        let count = (text ?? "").utf16.count
        guard let start = position(from: beginningOfDocument, offset: min(start, count)),
              let end = position(from: beginningOfDocument, offset: min(end, count)) else { return }
        let range = textRange(from: start, to: end)
        if selectedTextRange != range { selectedTextRange = range }
    }

    private var selectionRange: NSRange {
        guard let selection = selectedTextRange else { return NSRange(location: inputText.utf16.count, length: 0) }
        return NSRange(location: offset(from: beginningOfDocument, to: selection.start),
                       length: offset(from: selection.start, to: selection.end))
    }

    public override func insertText(_ text: String) {
        applyEdit(in: selectionRange, replacement: text)
    }

    public override func replace(_ range: UITextRange, withText text: String) {
        applyEdit(in: NSRange(location: offset(from: beginningOfDocument, to: range.start),
                              length: offset(from: range.start, to: range.end)), replacement: text)
    }

    public override func deleteBackward() {
        var range = selectionRange
        if range.length == 0 {
            guard range.location > 0 else { return }
            range.location -= 1
            range.length = 1
        }
        applyEdit(in: range, replacement: "")
    }

    public func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        applyEdit(in: range, replacement: string)
        return false
    }

    private func applyEdit(in range: NSRange, replacement string: String) {
        guard let edit = edit?(inputText, range, string) else {
            rejectInput()
            return
        }
        applyingText = true
        defer { applyingText = false }
        nativeInteraction = false
        animateNextLayout = edit.text != inputText
        switchesUnit = false
        replacesValue = string.count > 1 || range.length > 1 || (string.isEmpty && range.length == inputText.utf16.count)
        amountPresentation.resetCaretBlink()
        inputText = edit.text
        hasAmount = inputText.contains { "123456789".contains($0) }
        needsFormatting = true
        formatAmount()
        select(start: edit.caret, end: edit.caret)
        lastSelection = selectionRange
        setNeedsLayout()
        layoutIfNeeded()
        onTextChange?(inputText)
        sendActions(for: .editingChanged)
    }

    private func rejectInput() {
        guard isFirstResponder, window != nil else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        guard CardBackgroundMotionPolicy(requested: true,
            animationsEnabled: CardBackgroundAnimationEnvironment.shared.animationsEnabled,
            lowPowerMode: CardBackgroundAnimationEnvironment.shared.lowPowerMode,
            reduceMotion: UIAccessibility.isReduceMotionEnabled,
            applicationActive: UIApplication.shared.applicationState == .active, visible: true).canAnimate else { return }
        let initialOffset = layer.presentation()?.transform.m41 ?? 0
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        animation.values = (0...60).map { step -> NSNumber in
            let t = CGFloat(step) / 60
            let carry = max(0, 1 - 6 * t)
            return NSNumber(value: Double(9 * sin(6 * .pi * t) * (1 - t) + initialOffset * carry * carry))
        }
        animation.duration = 0.42
        animation.calculationMode = .linear
        animation.isAdditive = true
        layer.add(animation, forKey: "telegramAmountInputRefusal")
    }
}
