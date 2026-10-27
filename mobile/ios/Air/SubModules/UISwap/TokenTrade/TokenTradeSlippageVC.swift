import UIKit
import UIComponents
import WalletContext
import WalletCore

final class TokenTradeSlippageVC: WViewController {
    private var draft: BigInt?
    private let onCommit: (BigInt) -> Void
    private let scrollView = UIScrollView()
    private let content = UIView()
    private let amountContainer = UIView()
    private let percentLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let slider = TokenTradeSlippageSlider()
    private let doneButton = WButton(style: .primary)
    private var amountWidth: NSLayoutConstraint!
    private var containerWidth: NSLayoutConstraint!
    private var viewBottom: NSLayoutConstraint!
    private var keyboardBottom: NSLayoutConstraint!
    private var contentBottom: NSLayoutConstraint!
    private var sheetHeight: CGFloat = 364
    private let amountFont = UIFont.compactRounded(ofSize: 40, weight: .bold)
    private lazy var amountInput = WAmountInput(maximumFractionDigits: SLIPPAGE_DECIMALS, onChange: { [weak self] value in
        guard let self else { return }
        draft = value
        updateControls()
    })

    private var isValid: Bool { draft.map { $0 > 0 && $0 <= MAX_SLIPPAGE_VALUE } ?? false }
    private var animates: Bool { AppStorageHelper.animations && !UIAccessibility.isReduceMotionEnabled }

    init(slippage: BigInt, onCommit: @escaping (BigInt) -> Void) {
        draft = slippage
        self.onCommit = onCommit
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = CGSize(width: 420, height: 364)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = lang("Slippage")
        view.backgroundColor = .air.sheetBackground
        configureNavigationItemWithTransparentBackground()
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in
            self?.dismiss(animated: true)
        })
        configureContent()
        updateControls(replacingText: true)
        let sheet = navigationController?.sheetPresentationController
        sheet?.detents = [.custom(identifier: .init("slippage")) { [weak self] in
            min(self?.sheetHeight ?? 364, $0.maximumDetentValue)
        }]
        sheet?.prefersGrabberVisible = false
    }

    override func viewDidLayoutSubviews() {
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
        scrollView.bounces = false
        scrollView.delaysContentTouches = false
        scrollView.keyboardDismissMode = .interactive
        scrollView.contentInsetAdjustmentBehavior = .never
        view.addSubview(scrollView)
        scrollView.addSubview(content)
        let row = UIView()
        let minButton = rangeButton("Min", value: 1)
        let maxButton = rangeButton("Max", value: MAX_SLIPPAGE_VALUE)
        [row, slider, descriptionLabel, doneButton].forEach { content.addSubview($0) }
        [minButton, amountContainer, maxButton].forEach { row.addSubview($0) }

        amountContainer.backgroundColor = .air.background
        amountContainer.layer.cornerRadius = 22
        amountContainer.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(focusAmount)))
        amountInput.font = amountFont
        amountInput.integerFont = amountFont
        amountInput.fractionFont = amountFont
        amountInput.textAlignment = .right
        amountInput.placeholder = "0"
        amountInput.accessibilityLabel = lang("Slippage") + ", %"
        amountInput.accessibilityIdentifier = "tokenTrade.slippage.input"
        amountInput.addTarget(self, action: #selector(amountEditingChanged), for: [.editingDidBegin, .editingDidEnd])
        percentLabel.text = "%"
        percentLabel.font = .roundedNative(ofSize: 32, weight: .heavy)
        percentLabel.textColor = .air.secondaryLabel
        percentLabel.isAccessibilityElement = false
        let amountGroup = UIStackView(arrangedSubviews: [amountInput, percentLabel])
        amountGroup.alignment = .firstBaseline
        amountGroup.semanticContentAttribute = .forceLeftToRight
        amountContainer.addSubview(amountGroup)

        slider.addTarget(self, action: #selector(sliderChanged), for: .valueChanged)
        slider.addTarget(self, action: #selector(sliderStarted), for: .editingDidBegin)
        descriptionLabel.text = lang("Slippage is the difference between the expected and actual trade price caused by price changes during execution.")
        descriptionLabel.font = UIFontMetrics(forTextStyle: .footnote).scaledFont(for: .systemFont(ofSize: 13))
        descriptionLabel.adjustsFontForContentSizeCategory = true
        descriptionLabel.numberOfLines = 0
        descriptionLabel.textColor = .air.secondaryLabel

        doneButton.setTitle(lang("Done"), for: .normal)
        doneButton.customTitleFont = WButton.capsuleFont
        doneButton.customTintColor = slider.tintColor
        doneButton.layer.cornerRadius = 26
        doneButton.accessibilityIdentifier = "tokenTrade.slippage.done"
        doneButton.addTarget(self, action: #selector(commit), for: .touchUpInside)

        [scrollView, content, row, minButton, maxButton, amountContainer, amountGroup,
         amountInput, percentLabel, slider, descriptionLabel, doneButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
        }
        amountWidth = amountInput.widthAnchor.constraint(equalToConstant: 28)
        containerWidth = amountContainer.widthAnchor.constraint(equalToConstant: 92)
        viewBottom = scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        keyboardBottom = scrollView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)
        contentBottom = doneButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -28)
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
            descriptionLabel.topAnchor.constraint(equalTo: slider.bottomAnchor, constant: 32),
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
            attributes.font = .systemFont(ofSize: 14, weight: .medium)
            return attributes
        }
        button.configuration = configuration
        button.accessibilityValue = formatBigIntText(value, tokenDecimals: SLIPPAGE_DECIMALS) + "%"
        button.accessibilityIdentifier = "tokenTrade.slippage." + title.lowercased()
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

    private func updateControls(replacingText: Bool = false, animated: Bool = false, updateSlider: Bool = true) {
        if replacingText {
            amountInput.text = draft.map { formatBigIntText($0, tokenDecimals: SLIPPAGE_DECIMALS) }
        }
        amountInput.error = !isValid
        let selection = amountInput.selectedTextRange
        amountInput.reapplyFormatting()
        if amountInput.isFirstResponder { amountInput.selectedTextRange = selection }
        doneButton.isEnabled = isValid
        let width = ceil(((amountInput.text?.nilIfEmpty ?? "0") as NSString).size(withAttributes: [.font: amountFont]).width)
        amountWidth.constant = min(100, max(24, width + 2))
        containerWidth.constant = max(92, amountWidth.constant + percentLabel.intrinsicContentSize.width + 20)
        if updateSlider, isValid, let draft {
            slider.setValue(draft.doubleAbsRepresentation(decimals: SLIPPAGE_DECIMALS), animated: animated)
        }
        if animated {
            UIView.animate(withDuration: 0.2, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.amountContainer.superview?.layoutIfNeeded()
            }
        } else {
            UIView.performWithoutAnimation { amountContainer.superview?.layoutIfNeeded() }
        }
    }

    @objc private func focusAmount() { amountInput.becomeFirstResponder() }

    @objc private func amountEditingChanged() {
        // A keyboard belonging to the presenting trade screen must not shrink this sheet.
        NSLayoutConstraint.deactivate([viewBottom, keyboardBottom])
        (amountInput.isFirstResponder ? keyboardBottom : viewBottom).isActive = true
    }

    @objc private func sliderStarted() {
        view.endEditing(true)
        if !isValid { sliderChanged() }
    }

    @objc private func sliderChanged() {
        if amountInput.isFirstResponder { amountInput.resignFirstResponder() }
        draft = BigInt(Int((slider.selectedValue * 10).rounded()))
        updateControls(replacingText: true, updateSlider: false)
    }

    @objc private func commit() {
        guard isValid, let draft else { return }
        onCommit(draft)
        dismiss(animated: true)
    }
}
