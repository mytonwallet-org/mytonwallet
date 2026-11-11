import UIKit
import WalletContext
import WalletCore

/// A sheet that edits one value with a text field, Min and Max shortcuts and a preset slider,
/// such as Buy/Sell slippage or futures leverage.
open class TradeValueSheetVC: WViewController {
    public struct Configuration {
        public var title: String
        public var unit: String
        public var unitFont: UIFont
        /// Decimal places of the edited value; `draft` stores it scaled by them.
        public var fractionDigits: Int
        public var range: ClosedRange<BigInt>
        public var description: String
        public var inputAccessibilityLabel: String
        public var accessibilityPrefix: String

        public init(title: String, unit: String, unitFont: UIFont, fractionDigits: Int, range: ClosedRange<BigInt>,
                    description: String, inputAccessibilityLabel: String, accessibilityPrefix: String) {
            self.title = title
            self.unit = unit
            self.unitFont = unitFont
            self.fractionDigits = fractionDigits
            self.range = range
            self.description = description
            self.inputAccessibilityLabel = inputAccessibilityLabel
            self.accessibilityPrefix = accessibilityPrefix
        }
    }

    public let slider: TradePresetSlider
    public private(set) var draft: BigInt?
    public var isDraftValid: Bool { draft.map(configuration.range.contains) ?? false }
    private let configuration: Configuration
    private let accessory: UIView?
    private let onCommit: (BigInt) -> Void
    private let scrollView = UIScrollView()
    private let content = UIView()
    private let amountContainer = UIView()
    private let unitLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let doneButton = WButton(style: .primary)
    private var amountWidth: NSLayoutConstraint!
    private var containerWidth: NSLayoutConstraint!
    private var viewBottom: NSLayoutConstraint!
    private var keyboardBottom: NSLayoutConstraint!
    private var contentBottom: NSLayoutConstraint!
    private var sheetHeight: CGFloat = 364
    private let amountFont = UIFont.compactRounded(ofSize: 40, weight: .bold)
    private lazy var amountInput = WAmountInput(maximumFractionDigits: configuration.fractionDigits, onChange: { [weak self] value in
        guard let self else { return }
        draft = value
        updateControls()
    })
    private var animates: Bool { AppStorageHelper.animations && !UIAccessibility.isReduceMotionEnabled }

    /// - Parameter accessory: Content placed between the slider and the description.
    public init(configuration: Configuration, value: BigInt?, slider: TradePresetSlider, accessory: UIView? = nil,
                onCommit: @escaping (BigInt) -> Void) {
        self.configuration = configuration
        self.slider = slider
        self.accessory = accessory
        self.onCommit = onCommit
        draft = value
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = CGSize(width: 420, height: sheetHeight)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { nil }

    /// Called after every draft change, once the controls show it.
    open func draftDidChange() {}

    open override func viewDidLoad() {
        super.viewDidLoad()
        title = configuration.title
        view.backgroundColor = .air.sheetBackground
        configureNavigationItemWithTransparentBackground()
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in
            self?.dismiss(animated: true)
        })
        configureContent()
        updateControls(replacingText: true)
        let sheet = navigationController?.sheetPresentationController
        sheet?.detents = [.custom(identifier: .init(configuration.accessibilityPrefix)) { [weak self] in
            min(self?.sheetHeight ?? 364, $0.maximumDetentValue)
        }]
        sheet?.prefersGrabberVisible = false
    }

    open override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard content.bounds.width > 0 else { return }
        contentBottom.constant = -(IOS_26_MODE_ENABLED ? 28 : max(28, view.safeAreaInsets.bottom))
        let height = content.systemLayoutSizeFitting(
            CGSize(width: content.bounds.width, height: 0),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel
        ).height
        // UINavigationController adds its bar to the child's preferred size in a popover.
        if abs(preferredContentSize.height - height) > 1 {
            preferredContentSize.height = height
        }
        // Sheet detents add the bottom safe area themselves; the content already includes its padding.
        let detentHeight = height + (navigationController?.navigationBar.frame.maxY ?? view.safeAreaInsets.top)
            - view.safeAreaInsets.bottom
        if abs(sheetHeight - detentHeight) > 1 {
            sheetHeight = detentHeight
            navigationController?.sheetPresentationController?.invalidateDetents()
        }
    }

    private func configureContent() {
        if #available(iOS 17.0, *) {
            // Content already reserves bottom padding, including with a hardware keyboard.
            view.keyboardLayoutGuide.usesBottomSafeArea = false
        }
        scrollView.bounces = false
        scrollView.delaysContentTouches = false
        scrollView.keyboardDismissMode = .interactive
        scrollView.contentInsetAdjustmentBehavior = .never
        view.addSubview(scrollView)
        scrollView.addSubview(content)
        let row = UIView()
        let minButton = rangeButton("Min", value: configuration.range.lowerBound)
        let maxButton = rangeButton("Max", value: configuration.range.upperBound)
        [row, slider, descriptionLabel, doneButton].forEach { content.addSubview($0) }
        if let accessory { content.addSubview(accessory) }
        [minButton, amountContainer, maxButton].forEach { row.addSubview($0) }

        amountContainer.backgroundColor = .air.background
        amountContainer.layer.cornerRadius = 22
        amountContainer.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(focusAmount)))
        amountInput.font = amountFont
        amountInput.integerFont = amountFont
        amountInput.fractionFont = amountFont
        amountInput.textAlignment = .right
        amountInput.placeholder = "0"
        amountInput.accessibilityLabel = configuration.inputAccessibilityLabel
        amountInput.accessibilityIdentifier = configuration.accessibilityPrefix + ".input"
        amountInput.addTarget(self, action: #selector(amountEditingChanged), for: [.editingDidBegin, .editingDidEnd])
        unitLabel.text = configuration.unit
        unitLabel.font = configuration.unitFont
        unitLabel.textColor = .air.secondaryLabel
        unitLabel.isAccessibilityElement = false
        let amountGroup = UIStackView(arrangedSubviews: [amountInput, unitLabel])
        amountGroup.alignment = .firstBaseline
        amountGroup.semanticContentAttribute = .forceLeftToRight
        amountContainer.addSubview(amountGroup)

        slider.addTarget(self, action: #selector(sliderChanged), for: .valueChanged)
        slider.addTarget(self, action: #selector(sliderStarted), for: .editingDidBegin)
        descriptionLabel.text = configuration.description
        descriptionLabel.font = WTypography.uiFont(.footnote, scaling: .dynamic)
        descriptionLabel.adjustsFontForContentSizeCategory = true
        descriptionLabel.numberOfLines = 0
        descriptionLabel.textColor = .air.secondaryLabel
        descriptionLabel.accessibilityIdentifier = configuration.accessibilityPrefix + ".description"

        doneButton.setTitle(lang("Done"), for: .normal)
        doneButton.customTitleFont = WButton.capsuleFont
        doneButton.customTintColor = slider.tintColor
        doneButton.layer.cornerRadius = 26
        doneButton.accessibilityIdentifier = configuration.accessibilityPrefix + ".done"
        doneButton.addTarget(self, action: #selector(commit), for: .touchUpInside)

        [scrollView, content, row, minButton, maxButton, amountContainer, amountGroup,
         amountInput, unitLabel, slider, descriptionLabel, doneButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
        }
        amountWidth = amountInput.widthAnchor.constraint(equalToConstant: 28)
        containerWidth = amountContainer.widthAnchor.constraint(equalToConstant: 92)
        viewBottom = scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        keyboardBottom = scrollView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)
        contentBottom = doneButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -28)
        let descriptionTop: NSLayoutConstraint
        if let accessory {
            accessory.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                accessory.topAnchor.constraint(equalTo: slider.bottomAnchor, constant: 24),
                accessory.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
                accessory.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            ])
            descriptionTop = descriptionLabel.topAnchor.constraint(equalTo: accessory.bottomAnchor, constant: 16)
        } else {
            descriptionTop = descriptionLabel.topAnchor.constraint(equalTo: slider.bottomAnchor, constant: 32)
        }
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            viewBottom,
            content.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            content.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            content.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            row.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            row.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 32),
            row.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -32),
            row.heightAnchor.constraint(equalToConstant: 60),
            minButton.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            minButton.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            maxButton.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            maxButton.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            amountContainer.centerXAnchor.constraint(equalTo: row.centerXAnchor),
            amountContainer.topAnchor.constraint(equalTo: row.topAnchor),
            amountContainer.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            containerWidth,
            amountGroup.centerXAnchor.constraint(equalTo: amountContainer.centerXAnchor),
            amountGroup.centerYAnchor.constraint(equalTo: amountContainer.centerYAnchor),
            amountWidth,
            amountInput.heightAnchor.constraint(equalToConstant: amountFont.lineHeight),
            slider.topAnchor.constraint(equalTo: row.bottomAnchor, constant: 16),
            slider.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            slider.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            slider.heightAnchor.constraint(equalToConstant: 52),
            descriptionTop,
            descriptionLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            descriptionLabel.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            doneButton.topAnchor.constraint(equalTo: descriptionLabel.bottomAnchor, constant: 18),
            doneButton.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 30),
            doneButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -30),
            doneButton.heightAnchor.constraint(equalToConstant: 52),
            contentBottom,
        ])
    }

    private func rangeButton(_ title: String, value: BigInt) -> UIButton {
        let button = UIButton(type: .system)
        var configuration = UIButton.Configuration.filled()
        configuration.title = lang(title)
        configuration.baseBackgroundColor = .air.secondaryLabel.withAlphaComponent(0.12)
        configuration.baseForegroundColor = .label
        configuration.background.cornerRadius = 13
        configuration.background.backgroundInsets = NSDirectionalEdgeInsets(top: 9, leading: 0, bottom: 9, trailing: 0)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = WTypography.uiFont(.supportingEmphasized)
            return attributes
        }
        button.configuration = configuration
        button.accessibilityValue = format(value) + self.configuration.unit
        button.accessibilityIdentifier = self.configuration.accessibilityPrefix + "." + title.lowercased()
        button.widthAnchor.constraint(equalToConstant: 64).isActive = true
        button.heightAnchor.constraint(equalToConstant: 44).isActive = true
        button.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            view.endEditing(true)
            draft = value
            Haptics.play(.selection)
            updateControls(replacingText: true, animated: animates)
        }, for: .touchUpInside)
        return button
    }

    private func format(_ value: BigInt) -> String {
        formatBigIntText(value, tokenDecimals: configuration.fractionDigits)
    }

    private func updateControls(replacingText: Bool = false, animated: Bool = false, updateSlider: Bool = true) {
        if replacingText {
            amountInput.text = draft.map(format)
        }
        amountInput.error = !isDraftValid
        let selection = amountInput.selectedTextRange
        amountInput.reapplyFormatting()
        if amountInput.isFirstResponder { amountInput.selectedTextRange = selection }
        doneButton.isEnabled = isDraftValid
        let width = ceil(((amountInput.text?.nilIfEmpty ?? "0") as NSString).size(withAttributes: [.font: amountFont]).width)
        amountWidth.constant = min(100, max(24, width + 2))
        containerWidth.constant = max(92, amountWidth.constant + unitLabel.intrinsicContentSize.width + 20)
        if updateSlider, isDraftValid, let draft {
            slider.setValue(draft.doubleAbsRepresentation(decimals: configuration.fractionDigits), animated: animated)
        }
        if animated {
            UIView.animate(withDuration: 0.2, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.amountContainer.superview?.layoutIfNeeded()
            }
        } else {
            UIView.performWithoutAnimation { amountContainer.superview?.layoutIfNeeded() }
        }
        draftDidChange()
    }

    @objc private func focusAmount() { amountInput.becomeFirstResponder() }

    @objc private func amountEditingChanged() {
        // A keyboard belonging to the presenting trade screen must not shrink this sheet.
        NSLayoutConstraint.deactivate([viewBottom, keyboardBottom])
        (amountInput.isFirstResponder ? keyboardBottom : viewBottom).isActive = true
    }

    @objc private func sliderStarted() {
        view.endEditing(true)
        if !isDraftValid { sliderChanged() }
    }

    @objc private func sliderChanged() {
        if amountInput.isFirstResponder { amountInput.resignFirstResponder() }
        let scale = pow(10, Double(configuration.fractionDigits))
        draft = BigInt(Int((slider.selectedValue * scale).rounded()))
        updateControls(replacingText: true, updateSlider: false)
    }

    @objc private func commit() {
        guard isDraftValid, let draft else { return }
        onCommit(draft)
        dismiss(animated: true)
    }
}
