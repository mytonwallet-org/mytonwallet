import UIKit
import UIComponents
import WalletContext

final class PerpsLeverageVC: WViewController {
    var loadEstimate: ((Int) async throws -> [PerpsOrderDisplayData.LeverageOption])?
    var onDismiss: (() -> Void)?
    private var estimateTask: Task<Void, Never>?
    private var requestedLeverage: Int?
    private var data: PerpsOrderDisplayData
    private let onCommit: (Int) -> Void
    private var draft: Int?
    private let scrollView = UIScrollView()
    private let content = UIView()
    private let amountContainer = UIView()
    private let suffix = UILabel()
    private let metrics = UIStackView()
    private let liquidationValue = UILabel()
    private let paymentValue = UILabel()
    private let descriptionLabel = UILabel()
    private let doneButton = WButton(style: .primary)
    private var amountWidth: NSLayoutConstraint!
    private var containerWidth: NSLayoutConstraint!
    private var viewBottom: NSLayoutConstraint!
    private var keyboardBottom: NSLayoutConstraint!
    private var contentBottom: NSLayoutConstraint!
    private var sheetHeight: CGFloat = 502
    private var rendered = false
    private let amountFont = UIFont.compactRounded(ofSize: 40, weight: .bold)
    private lazy var amountInput = WAmountInput(maximumFractionDigits: 0, onChange: { [weak self] value in
        guard let self else { return }
        draft = value.flatMap { Int(exactly: $0) }
        updateControls()
    })
    private lazy var slider: TradePresetSlider = {
        let values = data.leverageOptions.map { Double($0.value) }
        let scale = TradeSliderScale(minimum: values.first ?? 0, maximum: values.last ?? 1,
            presets: data.leverageOptions.filter(\.isPreset).map { Double($0.value) },
            roundValue: { value in values.min { abs($0 - value) < abs($1 - value) } ?? 0 },
            stepValue: { value, increasing in
                if increasing { return values.first { $0 > value } ?? values.last ?? 0 }
                return values.last { $0 < value } ?? values.first ?? 0
            })
        return TradePresetSlider(scale: scale, value: Double(draft ?? 0)) {
            Int($0).formatted(.number.locale(.forNumberFormatters)) + "x"
        }
    }()

    private var option: PerpsOrderDisplayData.LeverageOption? { data.leverageOptions.first { $0.value == draft } }
    private var animates: Bool { rendered && view.window != nil && TradeMotion.enabled }

    func updateEstimates(_ options: [PerpsOrderDisplayData.LeverageOption]) {
        for option in options {
            if let index = data.leverageOptions.firstIndex(where: { $0.value == option.value }) {
                data.leverageOptions[index] = option
            }
        }
        if isViewLoaded { updateControls() }
    }

    init(data: PerpsOrderDisplayData, onCommit: @escaping (Int) -> Void) {
        self.data = data
        self.onCommit = onCommit
        draft = data.leverageOptions.first { $0.value == data.input.leverage }?.value ?? data.leverageOptions.first?.value
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = CGSize(width: 420, height: sheetHeight)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = lang("Leverage")
        view.backgroundColor = .air.sheetBackground
        configureNavigationItemWithTransparentBackground()
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
        configureContent()
        updateControls(replacingText: true)
        let sheet = navigationController?.sheetPresentationController
        sheet?.detents = [.custom(identifier: .init("leverage")) { [weak self] in min(self?.sheetHeight ?? 502, $0.maximumDetentValue) }]
        sheet?.prefersGrabberVisible = false
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Resolve the scroll content's width on the first pass, before fitting the sheet.
        scrollView.layoutIfNeeded()
        content.layoutIfNeeded()
        guard content.bounds.width > 0 else { return }
        contentBottom.constant = -(IOS_26_MODE_ENABLED ? 28 : max(28, view.safeAreaInsets.bottom))
        let height = content.systemLayoutSizeFitting(CGSize(width: content.bounds.width, height: 0),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
        if abs(preferredContentSize.height - height) > 1 { preferredContentSize.height = height }
        let detentHeight = height + (navigationController?.navigationBar.frame.maxY ?? view.safeAreaInsets.top) - view.safeAreaInsets.bottom
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
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.keyboardDismissMode = .interactive
        scrollView.contentInsetAdjustmentBehavior = .never
        view.addSubview(scrollView)
        scrollView.addSubview(content)
        let row = UIView()
        let minButton = rangeButton("Min", value: data.leverageOptions.first?.value)
        let maxButton = rangeButton("Max", value: data.leverageOptions.last?.value)
        [row, slider, metrics, descriptionLabel, doneButton].forEach { content.addSubview($0) }
        [minButton, amountContainer, maxButton].forEach { row.addSubview($0) }
        amountContainer.backgroundColor = .air.background
        amountContainer.layer.cornerRadius = 22
        amountContainer.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(focusAmount)))
        amountInput.font = amountFont
        amountInput.integerFont = amountFont
        amountInput.fractionFont = amountFont
        amountInput.textAlignment = .right
        amountInput.placeholder = "0"
        amountInput.accessibilityLabel = lang("Leverage")
        amountInput.accessibilityIdentifier = "perps.leverage.value"
        amountInput.addTarget(self, action: #selector(amountEditingChanged), for: [.editingDidBegin, .editingDidEnd])
        suffix.text = "x"
        suffix.font = amountFont
        suffix.textColor = .air.secondaryLabel
        suffix.isAccessibilityElement = false
        let amountGroup = UIStackView(arrangedSubviews: [amountInput, suffix])
        amountGroup.alignment = .firstBaseline
        amountGroup.semanticContentAttribute = .forceLeftToRight
        amountContainer.addSubview(amountGroup)
        slider.tintColor = AirTintColor
        slider.isEnabled = data.leverageOptions.count > 1
        slider.accessibilityLabel = lang("Leverage")
        slider.accessibilityIdentifier = "perps.leverage.slider"
        slider.addTarget(self, action: #selector(sliderChanged), for: .valueChanged)
        slider.addTarget(self, action: #selector(sliderStarted), for: .editingDidBegin)
        metrics.axis = .vertical
        metrics.backgroundColor = .air.background
        metrics.layer.cornerRadius = 26
        metrics.layer.cornerCurve = .continuous
        let price = UILabel()
        price.text = data.price
        metrics.addArrangedSubview(metricRow(title: L10n.perpsAssetPrice(asset: data.token.name), value: price))
        metrics.addArrangedSubview(metricDivider())
        metrics.addArrangedSubview(metricRow(title: lang("Liquidation Price"), value: liquidationValue, help: lang("$perps_liquidation_price_hint")))
        liquidationValue.accessibilityIdentifier = "perps.leverage.liquidationPrice"
        if data.editingPosition != nil {
            metrics.addArrangedSubview(metricDivider())
            metrics.addArrangedSubview(metricRow(title: lang("You Pay"), value: paymentValue))
            paymentValue.accessibilityIdentifier = "perps.leverage.payment"
        }
        descriptionLabel.font = WTypography.uiFont(.footnote, scaling: .dynamic)
        descriptionLabel.adjustsFontForContentSizeCategory = true
        descriptionLabel.numberOfLines = 0
        descriptionLabel.textColor = .air.secondaryLabel
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = UIFontMetrics(forTextStyle: .footnote).scaledValue(for: 18)
        descriptionLabel.attributedText = NSAttributedString(string: lang("$perps_leverage_disclaimer"), attributes: [.paragraphStyle: paragraph])
        descriptionLabel.accessibilityIdentifier = "perps.leverage.disclaimer"
        doneButton.setTitle(lang("Done"), for: .normal)
        doneButton.customTitleFont = WButton.capsuleFont
        doneButton.customTintColor = AirTintColor
        doneButton.layer.cornerRadius = 26
        doneButton.accessibilityIdentifier = "perps.leverage.done"
        doneButton.addTarget(self, action: #selector(commit), for: .touchUpInside)
        [scrollView, content, row, minButton, maxButton, amountContainer, amountGroup, amountInput, suffix,
         slider, metrics, descriptionLabel, doneButton].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        amountWidth = amountInput.widthAnchor.constraint(equalToConstant: 28)
        containerWidth = amountContainer.widthAnchor.constraint(equalToConstant: 92)
        viewBottom = scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        keyboardBottom = scrollView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)
        contentBottom = doneButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -28)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor), viewBottom,
            content.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            content.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            content.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            row.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            row.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 32),
            row.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -32), row.heightAnchor.constraint(equalToConstant: 60),
            minButton.leadingAnchor.constraint(equalTo: row.leadingAnchor), minButton.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            maxButton.trailingAnchor.constraint(equalTo: row.trailingAnchor), maxButton.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            amountContainer.centerXAnchor.constraint(equalTo: row.centerXAnchor),
            amountContainer.topAnchor.constraint(equalTo: row.topAnchor), amountContainer.bottomAnchor.constraint(equalTo: row.bottomAnchor), containerWidth,
            amountGroup.centerXAnchor.constraint(equalTo: amountContainer.centerXAnchor), amountGroup.centerYAnchor.constraint(equalTo: amountContainer.centerYAnchor),
            amountWidth, amountInput.heightAnchor.constraint(equalToConstant: amountFont.lineHeight),
            slider.topAnchor.constraint(equalTo: row.bottomAnchor, constant: 16),
            slider.leadingAnchor.constraint(equalTo: row.leadingAnchor), slider.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            slider.heightAnchor.constraint(equalToConstant: 52),
            metrics.topAnchor.constraint(equalTo: slider.bottomAnchor, constant: 24),
            metrics.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16), metrics.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            descriptionLabel.topAnchor.constraint(equalTo: metrics.bottomAnchor, constant: 16),
            descriptionLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            descriptionLabel.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            doneButton.topAnchor.constraint(equalTo: descriptionLabel.bottomAnchor, constant: 22),
            doneButton.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 30),
            doneButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -30), doneButton.heightAnchor.constraint(equalToConstant: 52), contentBottom
        ])
    }

    private func metricDivider() -> UIView {
        let dividerContainer = UIView()
        let divider = UIView()
        divider.backgroundColor = .air.separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        dividerContainer.addSubview(divider)
        NSLayoutConstraint.activate([
            dividerContainer.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
            divider.leadingAnchor.constraint(equalTo: dividerContainer.leadingAnchor, constant: 16),
            divider.trailingAnchor.constraint(equalTo: dividerContainer.trailingAnchor, constant: -16),
            divider.topAnchor.constraint(equalTo: dividerContainer.topAnchor), divider.bottomAnchor.constraint(equalTo: dividerContainer.bottomAnchor)
        ])
        return dividerContainer
    }

    private func metricRow(title: String, value: UILabel, help: String? = nil) -> UIView {
        let label = UILabel()
        label.text = title
        label.font = WTypography.uiFont(.body)
        label.textColor = .air.secondaryLabel
        label.numberOfLines = 0
        value.font = WTypography.uiFont(.body, content: .technical)
        value.textColor = .label
        value.textAlignment = .right
        value.adjustsFontSizeToFitWidth = true
        value.minimumScaleFactor = 0.7
        value.setContentCompressionResistancePriority(.required, for: .horizontal)
        let titleGroup = UIStackView(arrangedSubviews: [label])
        titleGroup.spacing = 4
        titleGroup.alignment = .center
        let stack = UIStackView(arrangedSubviews: [titleGroup, UIView(), value])
        stack.spacing = 8
        stack.alignment = .center
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = .init(top: 12, leading: 16, bottom: 12, trailing: 16)
        stack.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        if let help {
            let symbol = UIImageView(image: UIImage(systemName: "questionmark.circle.fill",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .regular))?.withAlignmentRectInsets(.zero))
            symbol.tintColor = .air.secondaryLabel.withAlphaComponent(0.6)
            symbol.contentMode = .scaleAspectFit
            symbol.accessibilityIdentifier = "perps.leverage.liquidationInfoIcon"
            symbol.isAccessibilityElement = false
            titleGroup.addArrangedSubview(symbol)
            symbol.widthAnchor.constraint(equalToConstant: 14).isActive = true
            symbol.heightAnchor.constraint(equalToConstant: 14).isActive = true
            let button = UIButton(type: .system)
            button.accessibilityLabel = title + ", " + lang("Info")
            button.accessibilityIdentifier = "perps.leverage.liquidationInfo"
            button.addAction(UIAction { [weak self] _ in self?.showTip(title: title, message: help) }, for: .touchUpInside)
            label.isAccessibilityElement = false
            button.translatesAutoresizingMaskIntoConstraints = false
            stack.addSubview(button)
            NSLayoutConstraint.activate([
                button.leadingAnchor.constraint(equalTo: titleGroup.leadingAnchor),
                button.trailingAnchor.constraint(equalTo: titleGroup.trailingAnchor),
                button.topAnchor.constraint(equalTo: stack.topAnchor),
                button.bottomAnchor.constraint(equalTo: stack.bottomAnchor)
            ])
        }
        return stack
    }

    private func rangeButton(_ title: String, value: Int?) -> UIButton {
        let button = UIButton(type: .system)
        var configuration = UIButton.Configuration.filled()
        configuration.title = lang(title)
        configuration.baseBackgroundColor = .air.secondaryLabel.withAlphaComponent(0.12)
        configuration.baseForegroundColor = .label
        configuration.background.cornerRadius = 13
        configuration.background.backgroundInsets = .init(top: 9, leading: 0, bottom: 9, trailing: 0)
        configuration.titleTextAttributesTransformer = .init { attributes in
            var attributes = attributes
            attributes.font = WTypography.uiFont(.supportingEmphasized)
            return attributes
        }
        button.configuration = configuration
        button.isEnabled = value != nil
        button.accessibilityValue = value.map { $0.formatted(.number.locale(.forNumberFormatters)) + "x" }
        button.accessibilityIdentifier = "perps.leverage." + title.lowercased()
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
        if replacingText { amountInput.text = draft.map { $0.formatted(.number.locale(.forNumberFormatters).grouping(.never)) } }
        amountInput.error = option == nil
        let selection = amountInput.selectedTextRange
        amountInput.reapplyFormatting()
        if amountInput.isFirstResponder { amountInput.selectedTextRange = selection }
        let width = ceil(((amountInput.text?.nilIfEmpty ?? "0") as NSString).size(withAttributes: [.font: amountFont]).width)
        amountWidth.constant = min(100, max(24, width + 2))
        containerWidth.constant = max(92, amountWidth.constant + suffix.intrinsicContentSize.width + 20)
        doneButton.isEnabled = option != nil
        if updateSlider, let option { slider.setValue(Double(option.value), animated: animated) }
        let price = option?.liquidationPrice ?? "—"
        paymentValue.text = option?.paymentAmount ?? "—"
        if liquidationValue.text != price, animates {
            UIView.transition(with: liquidationValue, duration: 0.2, options: [.transitionCrossDissolve, .beginFromCurrentState, .allowUserInteraction]) {
                self.liquidationValue.text = price
            }
        } else {
            liquidationValue.text = price
        }
        requestEstimate()
        rendered = true
        let changes = { self.view.setNeedsLayout(); self.view.layoutIfNeeded() }
        TradeMotion.animate(animated, changes: changes)
    }

    private func requestEstimate() {
        guard let option else {
            estimateTask?.cancel()
            requestedLeverage = nil
            return
        }
        guard requestedLeverage != option.value else { return }
        estimateTask?.cancel()
        requestedLeverage = nil
        guard option.liquidationPrice == nil || (data.editingPosition != nil && option.paymentAmount == nil),
              let loadEstimate else { return }
        let value = option.value
        requestedLeverage = value
        estimateTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(250))
                let options = try await loadEstimate(value)
                guard !Task.isCancelled, self?.draft == value else { return }
                self?.updateEstimates(options)
            } catch {
                guard !Task.isCancelled, self?.draft == value else { return }
                self?.requestedLeverage = nil
            }
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        estimateTask?.cancel()
        onDismiss?()
    }

    @objc private func focusAmount() { amountInput.becomeFirstResponder() }
    @objc private func amountEditingChanged() {
        NSLayoutConstraint.deactivate([viewBottom, keyboardBottom])
        (amountInput.isFirstResponder ? keyboardBottom : viewBottom).isActive = true
    }
    @objc private func sliderStarted() {
        view.endEditing(true)
        if option == nil { sliderChanged() }
    }
    @objc private func sliderChanged() {
        view.endEditing(true)
        draft = Int(slider.selectedValue)
        updateControls(replacingText: true, updateSlider: false)
    }
    @objc private func commit() {
        guard let option else { return }
        onCommit(option.value)
        dismiss(animated: true)
    }
}
