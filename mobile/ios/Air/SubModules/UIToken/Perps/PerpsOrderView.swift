import Combine
import SwiftNavigation
import UIKit
import UIComponents
import WalletContext

/// Presentation only: the adapter still owns quotes, amounts and liquidation estimates.
final class PerpsOrderView: UIView {
    private let state: PerpsOrderState
    let amountField = TradeTextField()
    let scrollView = UIScrollView()
    let payment = TradePaymentControl(isBuying: true, shouldShowChain: false)
    private let amountCard = UIView()
    private let controlsBackground = UIView()
    private let editor = TradeEditor()
    private let conversion = TradeConversionControl(frame: .zero)
    private let leverage = TradePressButton(frame: .zero)
    private let leverageLabel = UILabel()
    private let leverageChevron = UIImageView(image: .airBundle("TokenTradeDropdown"))
    private let liquidation = UILabel()
    private let positionSize = UILabel()
    private let unavailableNotice = NativeTradeNoticeView(frame: .zero)
    private lazy var unavailablePresence = TradePresenceView(unavailableNotice)
    private var showsUnavailableNotice = false
    private var showsFundingRequirement = false
    private let reset = TradePressButton(frame: .zero)
    private let current = TradePressButton(frame: .zero)
    private let currentLabel = UILabel()
    private lazy var resetPresence = TradePresenceView(reset)
    private lazy var currentPresence = TradePresenceView(current)
    private lazy var keypad = TradeKeypad(editor: editor, accessibilityPrefix: "perps.order")
    private lazy var controls = NativeTradeInputControls(percentages: state.fractionPresets,
        showsPositiveSign: state.data.editingPosition != nil, accessibilityPrefix: "perps.order",
        onFraction: { [weak state] in state?.request(.fraction($0)) },
        onContinue: { [weak state] in state?.request(.review) })
    private var rendered = false
    private var environmentSubscription: AnyCancellable?

    init(state: PerpsOrderState, selectLeverage: @escaping () -> Void) {
        self.state = state
        super.init(frame: .zero)
        backgroundColor = .air.headerBackground
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.delaysContentTouches = false
        scrollView.keyboardDismissMode = .none
        scrollView.accessibilityIdentifier = "perps.order.content"
        addSubview(scrollView)
        addSubview(controlsBackground)
        [amountCard, payment].forEach { scrollView.addSubview($0) }
        [conversion, amountField, leverage, liquidation, positionSize, resetPresence, currentPresence, unavailablePresence].forEach { amountCard.addSubview($0) }
        controlsBackground.addSubview(controls)
        controlsBackground.addSubview(keypad)
        amountCard.backgroundColor = .air.pickerBackground
        amountCard.layer.cornerRadius = 32
        amountCard.layer.cornerCurve = .continuous
        controlsBackground.backgroundColor = .air.pickerBackground
        controlsBackground.layer.cornerRadius = 32
        controlsBackground.layer.cornerCurve = .continuous
        controlsBackground.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        controlsBackground.accessibilityIdentifier = "perps.order.keyboard"
        editor.field = amountField
        amountField.caretColor = AirTintColor
        amountField.accessibilityIdentifier = "perps.order.amount"
        amountField.clearAccessibilityIdentifier = "perps.order.clear"
        amountField.onChange = { [weak state] in state?.editAmount($0) }
        conversion.accessibilityIdentifier = "perps.order.conversion"
        conversion.isSelectable = false
        payment.accessibilityIdentifier = "perps.order.payment"
        payment.addAction(UIAction { [weak state] _ in state?.request(.selectPayment) }, for: .touchUpInside)
        leverage.content.backgroundColor = AirTintColor.withAlphaComponent(0.1)
        leverage.content.layer.cornerRadius = 16
        leverageLabel.font = WTypography.uiFont(.bodyEmphasized)
        leverageLabel.textColor = AirTintColor
        leverageChevron.image = leverageChevron.image?.withRenderingMode(.alwaysTemplate)
        leverageChevron.tintColor = AirTintColor
        leverage.content.addSubview(leverageLabel)
        leverage.content.addSubview(leverageChevron)
        leverage.accessibilityIdentifier = "perps.order.leverage"
        leverage.addAction(UIAction { _ in selectLeverage() }, for: .touchUpInside)
        for label in [liquidation, positionSize] {
            label.font = WTypography.uiFont(.supportingEmphasized)
            label.textColor = .air.secondaryLabel
        }
        liquidation.accessibilityIdentifier = "perps.order.liquidationPrice"
        positionSize.accessibilityIdentifier = "perps.order.positionSize"
        unavailableNotice.accessibilityIdentifier = "perps.order.unavailable"
        unavailableNotice.onAction = { [weak state] in
            guard let state else { return }
            if let action = state.data.fundingRequirement?.action {
                state.request(action == .buyUsdc ? .buyUsdc : .buyEth)
            } else if state.canRetryFunding {
                state.request(.refreshFunding)
            }
        }
        let resetImage = UIImageView(image: UIImage.airBundle("PerpsEditReset").withRenderingMode(.alwaysTemplate))
        resetImage.tintColor = .air.secondaryLabel.withAlphaComponent(0.45)
        resetImage.contentMode = .center
        resetImage.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        reset.content.addSubview(resetImage)
        currentLabel.font = WTypography.uiFont(.body)
        currentLabel.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        current.content.addSubview(currentLabel)
        for button in [reset, current] {
            button.accessibilityLabel = lang("Reset to Current Amount")
            button.addAction(UIAction { [weak state] _ in state?.request(.resetAmount) }, for: .touchUpInside)
        }
        reset.accessibilityIdentifier = "perps.order.reset"
        current.accessibilityIdentifier = "perps.order.current"
        observe { [weak self] in self?.refreshContent() }
        let environment = CardBackgroundAnimationEnvironment.shared
        environmentSubscription = Publishers.CombineLatest4(environment.$applicationActive, environment.$animationsEnabled,
            environment.$lowPowerMode, environment.$reduceMotion).sink { [weak self] _ in
                DispatchQueue.main.async { [weak self] in self?.refreshMotionPolicy() }
            }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func install(in parent: UIView) {
        translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(self)
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: parent.leadingAnchor), trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            topAnchor.constraint(equalTo: parent.topAnchor), bottomAnchor.constraint(equalTo: parent.bottomAnchor)
        ])
    }

    private func refreshContent() {
        let data = state.data
        let animated = rendered && window != nil && TradeMotion.enabled
        amountField.configure(input: data.input.amount, decimals: data.currencyDecimals,
            prefix: data.currency.sign, suffix: "", hasAmount: data.input.hasAmount)
        amountField.showsClearButton = data.editingPosition == nil
        amountField.accessibilityLabel = lang("Amount") + ", " + data.currency.rawValue
        keypad.updateDelete(isEnabled: !data.input.amount.text.isEmpty)
        let zero = 0.formatted(.number.locale(.forNumberFormatters))
        let conversionText = data.conversion ?? (data.status == .idle && !data.input.hasAmount
            ? zero + " " + data.token.symbol : "—")
        conversion.update(text: conversionText, isTokenAmount: false, isStale: data.status == .loading,
            isEnabled: true, animated: animated)
        let title = data.editingPosition.map { position in
            switch position.change {
            case .increase, .leverage: lang("You Pay")
            case .reduce: lang("You Receive")
            case nil: lang("You Pay or Receive")
            }
        } ?? lang("You Pay")
        payment.setTitle(title, color: data.editingPosition != nil && data.editingPosition?.change == nil ? .air.secondaryLabel : .label,
            selectable: data.canSelectPayment)
        payment.update(token: data.paymentToken, currency: nil, amountText: data.paymentAmount, symbolText: data.paymentToken.symbol,
            isStale: data.status == .loading, animated: animated)
        leverageLabel.text = lang("Leverage") + " " + data.input.leverage.formatted(.number.locale(.forNumberFormatters)) + "x"
        leverage.accessibilityLabel = leverageLabel.text
        leverage.isEnabled = state.canSelectLeverage
        showsFundingRequirement = data.fundingRequirement != nil
        leverage.isHidden = showsFundingRequirement
        leverage.content.alpha = leverage.isEnabled ? 1 : 0.5
        liquidation.isHidden = data.editingPosition == nil || showsFundingRequirement
        liquidation.text = lang("Liquidation") + ": " + (data.editingPosition?.liquidationPrice ?? "—")
        positionSize.text = lang("Position Size") + ": " + (data.positionSize ?? "—")
        positionSize.isHidden = showsFundingRequirement || (data.positionSize == nil && data.editingPosition == nil)
        current.accessibilityValue = data.editingPosition?.currentAmount
        let currentText = NSMutableAttributedString(string: lang("Current:") + " ", attributes: [.foregroundColor: UIColor.air.secondaryLabel])
        currentText.append(NSAttributedString(string: data.editingPosition?.currentAmount ?? "", attributes: [.foregroundColor: AirTintColor]))
        currentLabel.attributedText = currentText
        resetPresence.setContentVisible(state.hasPositionChanges, animated: animated)
        currentPresence.setContentVisible(state.hasPositionChanges, animated: animated)
        let showsFractions = !showsFundingRequirement && data.status == .idle && (data.editingPosition != nil ? !state.hasPositionChanges : !data.input.hasAmount)
        if let requirement = data.fundingRequirement {
            showsUnavailableNotice = true
            unavailableNotice.update(.init(title: requirement.title, message: requirement.message, actionTitle: requirement.actionTitle), animated: animated)
        } else if case .unavailable(let reason) = data.status {
            showsUnavailableNotice = true
            unavailableNotice.update(.init(title: "", message: reason,
                actionTitle: state.canRetryFunding ? lang("Retry") : nil), animated: animated)
        } else {
            showsUnavailableNotice = false
        }
        unavailablePresence.setContentVisible(showsUnavailableNotice, animated: animated)
        controls.update(configuration: .init(title: .text(data.fundingRequirement?.buttonTitle ?? lang("Review")),
            isEnabled: state.canReview, showLoading: data.status == .loading && !showsFundingRequirement),
            tintColor: AirTintColor, showsContinue: !showsFractions, fractionsEnabled: data.canUseFractions, animated: animated)
        rendered = true
        setNeedsLayout()
        guard !bounds.isEmpty else { return }
        TradeMotion.animate(animated) { self.layoutIfNeeded() }
    }

    private func refreshMotionPolicy() {
        let active = window != nil && CardBackgroundAnimationEnvironment.shared.applicationActive
        amountField.configureAnimation(active: active, animated: active && TradeMotion.enabled)
        conversion.refreshMotionPolicy()
        payment.refreshMotionPolicy()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        refreshMotionPolicy()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0 else { return }
        let width = bounds.width
        let leadingWidth = leverage.isHidden ? liquidation.intrinsicContentSize.width : leverageLabel.intrinsicContentSize.width + 30
        let trailingWidth = positionSize.isHidden ? 0 : positionSize.intrinsicContentSize.width
        let stacked = leadingWidth + trailingWidth + 8 > width - 48
        let primaryMetricsHeight: CGFloat = stacked ? 64 : 32
        let metricsHeight: CGFloat = showsFundingRequirement ? 0 : primaryMetricsHeight + (liquidation.isHidden ? 0 : 32)
        let noticeInset: CGFloat = showsFundingRequirement ? 16 : 24
        let noticeWidth = max(1, width - 2 * noticeInset)
        let noticeHeight = showsUnavailableNotice
            ? max(showsFundingRequirement ? 78 : 0, unavailableNotice.sizeThatFits(CGSize(width: noticeWidth, height: .greatestFiniteMagnitude)).height) : 0
        let layout = NativeTradeLayout(size: bounds.size, bottomSafeArea: safeAreaInsets.bottom, navigationBarSpace: 64,
            feeHeight: metricsHeight, impactHeight: 0, hintHeight: noticeHeight,
            amountSupplementHeight: state.hasPositionChanges ? 44 : 0)
        TradeMotion.place(scrollView, in: layout.scroll)
        TradeMotion.place(amountCard, in: layout.card)
        TradeMotion.place(payment, in: layout.method)
        scrollView.contentSize = CGSize(width: width, height: layout.contentHeight)
        scrollView.alwaysBounceVertical = layout.contentHeight > layout.scroll.height
        TradeMotion.place(controlsBackground, in: layout.controls)
        TradeMotion.place(controls, in: CGRect(x: 24, y: 24, width: max(0, width - 48), height: 52))
        TradeMotion.place(keypad, in: CGRect(x: 0, y: 88, width: width, height: layout.keypadHeight))
        amountField.maximumHeight = layout.maximumAmountHeight
        let resetWidth: CGFloat = state.hasPositionChanges ? 44 : 0
        let amountWidth = max(1, width - 28 - resetWidth)
        let fieldHeight = amountField.fittingHeight(forWidth: amountWidth)
        let top = layout.amountTop + max(0, (layout.maximumAmountHeight - fieldHeight) / 2)
        let rtl = effectiveUserInterfaceLayoutDirection == .rightToLeft
        func place(_ view: UIView, _ frame: CGRect) {
            var frame = frame
            if rtl { frame.origin.x = width - frame.maxX }
            TradeMotion.place(view, in: frame)
        }
        place(conversion, CGRect(x: 24, y: top, width: min(width - 48, conversion.intrinsicContentSize.width), height: 26))
        place(amountField, CGRect(x: 24, y: top + 26, width: amountWidth, height: fieldHeight))
        place(resetPresence, CGRect(x: width - 48, y: top + 26 + (fieldHeight - 44) / 2, width: 44, height: 44))
        place(currentPresence, CGRect(x: 24, y: top + 26 + fieldHeight + 12, width: width - 48, height: 32))
        place(leverage, CGRect(x: 16, y: layout.footerTop, width: min(width - 32, leadingWidth), height: 32))
        TradeMotion.place(leverageLabel, in: CGRect(x: 12, y: 0, width: max(0, leverage.bounds.width - 30), height: 32))
        TradeMotion.place(leverageChevron, in: CGRect(x: leverage.bounds.width - 18, y: 5, width: 10, height: 22))
        place(liquidation, CGRect(x: 24, y: layout.footerTop + primaryMetricsHeight, width: width - 48, height: 32))
        place(positionSize, CGRect(x: stacked ? 24 : width - 24 - trailingWidth,
            y: layout.footerTop + (stacked ? 32 : 0), width: min(width - 48, trailingWidth), height: 32))
        if showsUnavailableNotice {
            place(unavailablePresence, CGRect(x: noticeInset, y: layout.footerTop + (metricsHeight > 0 ? metricsHeight + 8 : 0),
                width: noticeWidth, height: noticeHeight))
        }
    }
}
