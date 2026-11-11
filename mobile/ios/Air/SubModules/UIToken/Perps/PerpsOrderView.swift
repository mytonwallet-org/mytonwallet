import ContextMenuKit
import SwiftNavigation
import UIKit
import UIComponents
import WalletContext
import WalletCore

/// Presentation only: the adapter owns quotes, amounts and liquidation estimates.
final class PerpsOrderView: NativeTradeEntryView {
    private let state: PerpsOrderState
    private let controls: NativeTradeInputControls
    private let leverage = TradePressButton(frame: .zero)
    private let leverageLabel = UILabel()
    private let leverageChevron = UIImageView(image: .airBundle("TokenTradeDropdown"))
    private let liquidation = UILabel()
    private let positionSize = UILabel()
    private lazy var leveragePresence = TradePresenceView(leverage)
    private lazy var liquidationPresence = TradePresenceView(liquidation)
    private lazy var positionSizePresence = TradePresenceView(positionSize)
    private let unavailableNotice = NativeTradeNoticeView(frame: .zero)
    private lazy var unavailablePresence = TradePresenceView(unavailableNotice)
    private var showsUnavailableNotice = false
    private var showsFundingRequirement = false
    private let reset = TradePressButton(frame: .zero)
    private let current = TradePressButton(frame: .zero)
    private let currentLabel = UILabel()
    private lazy var resetPresence = TradePresenceView(reset)
    private lazy var currentPresence = TradePresenceView(current)
    private var fundingMenu: ContextMenuInteraction?
    private var rendered = false

    init(state: PerpsOrderState, selectLeverage: @escaping () -> Void) {
        self.state = state
        let controls = NativeTradeInputControls(percentages: state.fractionPresets,
            showsPositiveSign: state.data.editingPosition != nil, accessibilityPrefix: "perps.order",
            onFraction: { [weak state] in state?.request(.fraction($0)) },
            onContinue: { [weak state] in state?.request(.review) })
        self.controls = controls
        super.init(method: TradePaymentControl(isBuying: true), controls: controls, keypadAccessibilityPrefix: "perps.order")
        scrollView.accessibilityIdentifier = "perps.order.content"
        [leveragePresence, liquidationPresence, positionSizePresence, resetPresence, currentPresence, unavailablePresence].forEach { amountCard.addSubview($0) }
        amountField.accessibilityIdentifier = "perps.order.amount"
        amountField.clearAccessibilityIdentifier = "perps.order.clear"
        amountField.onChange = { [weak state] in state?.editAmount($0) }
        conversion.accessibilityIdentifier = "perps.order.conversion"
        conversion.isSelectable = false
        method.accessibilityIdentifier = "perps.order.payment"
        let fundingMenu = ContextMenuInteraction(triggers: [.tap]) { [weak state] _ in
            state.flatMap(Self.fundingMenu)
        }
        fundingMenu.attach(to: method)
        self.fundingMenu = fundingMenu
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
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func refreshContent() {
        let animated = rendered && window != nil && TradeMotion.enabled
        layoutIfNeeded()
        TradeMotion.animate(animated) {
            self.updateContent(animated: animated)
            self.setNeedsLayout()
            self.layoutIfNeeded()
        }
        rendered = true
    }

    private func updateContent(animated: Bool) {
        let data = state.data
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
            case .increase: lang("You Pay")
            case .reduce: lang("You Receive")
            case nil: lang("You Pay or Receive")
            }
        } ?? lang("You Pay")
        method.setTitle(title, color: data.editingPosition != nil && data.editingPosition?.change == nil ? .air.secondaryLabel : .label,
            selectable: state.canSelectFunding, animated: animated)
        method.update(token: data.paymentToken, currency: nil, amountText: data.paymentAmount, symbolText: data.paymentToken.symbol,
            isStale: data.status == .loading, animated: animated)
        Self.setText(NSAttributedString(string: lang("Leverage") + " " + data.input.leverage.formatted(.number.locale(.forNumberFormatters)) + "x"),
                     on: leverageLabel, animated: animated)
        leverage.accessibilityLabel = leverageLabel.text
        leverage.isEnabled = state.canSelectLeverage
        showsFundingRequirement = data.fundingRequirement != nil
        leveragePresence.setContentVisible(data.editingPosition == nil && !showsFundingRequirement, animated: animated)
        leverage.content.alpha = leverage.isEnabled ? 1 : 0.5
        liquidationPresence.setContentVisible(data.editingPosition != nil && !showsFundingRequirement, animated: animated)
        Self.setText(NSAttributedString(string: lang("Liquidation") + ": " + (data.editingPosition?.liquidationPrice ?? "—")),
                     on: liquidation, animated: animated)
        Self.setText(NSAttributedString(string: lang("Position Size") + ": " + (data.positionSize ?? "—")),
                     on: positionSize, animated: animated)
        positionSizePresence.setContentVisible(!showsFundingRequirement && (data.positionSize != nil || data.editingPosition != nil), animated: animated)
        current.accessibilityValue = data.editingPosition?.currentAmount
        let currentText = NSMutableAttributedString(string: lang("Current:") + " ", attributes: [.foregroundColor: UIColor.air.secondaryLabel])
        currentText.append(NSAttributedString(string: data.editingPosition?.currentAmount ?? "", attributes: [.foregroundColor: AirTintColor]))
        Self.setText(currentText, on: currentLabel, animated: animated)
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
    }

    private static func setText(_ text: NSAttributedString, on label: UILabel, animated: Bool) {
        guard label.attributedText?.isEqual(to: text) != true else { return }
        if animated, label.attributedText != nil {
            UIView.transition(with: label, duration: TradeMotion.duration,
                              options: [.transitionCrossDissolve, .beginFromCurrentState, .allowUserInteraction]) {
                label.attributedText = text
            }
        } else {
            label.attributedText = text
        }
    }

    /// Wallet USDC on Arbitrum, or USDC already on Hyperliquid.
    private static func fundingMenu(_ state: PerpsOrderState) -> ContextMenuConfiguration? {
        guard state.canSelectFunding else { return nil }
        let data = state.data
        func option(_ funding: ApiPerpsFundingSource, _ chain: ApiChain, _ balance: String?) -> ContextMenuItem {
            .action(ContextMenuAction(id: "perps.order.funding." + funding.rawValue, title: chain.config.title,
                subtitle: balance.flatMap { Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) }.map {
                    $0.formatted(.number.locale(.forNumberFormatters).precision(.fractionLength(0...2)).rounded(rule: .down))
                        + " " + PerpsSDKAdapter.usdc.symbol
                },
                icon: data.input.funding == funding ? .system("checkmark") : .placeholder) { [weak state] in
                    state?.selectFunding(funding)
                })
        }
        return TradeInfoMenu.configuration(items: [
            option(.wallet, .arbitrum, data.walletBalance),
            option(.balance, .hyperliquid, data.hyperliquidBalance),
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0 else { return }
        let width = bounds.width
        let leadingWidth = leveragePresence.showsContent ? leverageLabel.intrinsicContentSize.width + 30 : liquidation.intrinsicContentSize.width
        let trailingWidth = positionSizePresence.showsContent ? positionSize.intrinsicContentSize.width : 0
        let stacked = leadingWidth + trailingWidth + 8 > width - 48
        let metricsHeight: CGFloat = showsFundingRequirement ? 0 : stacked ? 64 : 32
        let noticeInset: CGFloat = showsFundingRequirement ? 16 : 24
        let noticeWidth = max(1, width - 2 * noticeInset)
        let noticeHeight = showsUnavailableNotice
            ? max(showsFundingRequirement ? 78 : 0, unavailableNotice.sizeThatFits(CGSize(width: noticeWidth, height: .greatestFiniteMagnitude)).height) : 0
        let layout = NativeTradeLayout(size: bounds.size, bottomSafeArea: safeAreaInsets.bottom, navigationBarSpace: 64,
            feeHeight: metricsHeight, impactHeight: 0, hintHeight: noticeHeight,
            amountSupplementHeight: currentPresence.showsContent ? 44 : 0)
        let amount = layoutEntry(layout, amountTrailingInset: currentPresence.showsContent ? 44 : 0)
        placeInCard(resetPresence, CGRect(x: width - 48, y: amount.minY + (amount.height - 44) / 2, width: 44, height: 44))
        placeInCard(currentPresence, CGRect(x: 24, y: amount.maxY + 12, width: width - 48, height: 32))
        let leverageWidth = min(width - 32, leadingWidth)
        placeInCard(leveragePresence, CGRect(x: 16, y: layout.footerTop, width: leverageWidth, height: 32))
        TradeMotion.place(leverageLabel, in: CGRect(x: 12, y: 0, width: max(0, leverageWidth - 30), height: 32))
        TradeMotion.place(leverageChevron, in: CGRect(x: leverageWidth - 18, y: 5, width: 10, height: 22))
        placeInCard(liquidationPresence, CGRect(x: 24, y: layout.footerTop, width: min(width - 48, leadingWidth), height: 32))
        placeInCard(positionSizePresence, CGRect(x: stacked ? 24 : width - 24 - trailingWidth,
            y: layout.footerTop + (stacked ? 32 : 0), width: min(width - 48, trailingWidth), height: 32))
        if showsUnavailableNotice {
            placeInCard(unavailablePresence, CGRect(x: noticeInset, y: layout.footerTop + (metricsHeight > 0 ? metricsHeight + 8 : 0),
                width: noticeWidth, height: noticeHeight))
        }
    }
}
