import UIKit
import SwiftNavigation
import UIComponents
import WalletCore
import WalletContext

/// A retained UIKit tree. Model observation updates content; layout and animation never read the model.
final class TokenTradeView: NativeTradeEntryView {
    private let model: TokenTradeModel
    var hasTopNavigationBar = true {
        didSet { if hasTopNavigationBar != oldValue { setNeedsLayout() } }
    }
    var methodButton: TokenTradeMethodButton { method }
    private let fee = TokenTradeFeeButton(frame: .zero)
    private let impact = TokenTradeNoticeView(frame: .zero)
    private let hint = TokenTradeNoticeView(frame: .zero)
    private lazy var feePresence = TokenTradePresenceView(fee)
    private lazy var impactPresence = TokenTradePresenceView(impact)
    private lazy var hintPresence = TokenTradePresenceView(hint)
    private var hasFee = false
    private var hasImpact = false
    private var hasHint = false
    private var rendered = false
    private var cardMaximumRequest: TokenTradeModel.CardMaximumRequest?
    private var cardMaximumTask: Task<Void, Never>?

    init(model: TokenTradeModel, selectMethod: @escaping () -> Void, continueAction: @escaping () -> Void) {
        self.model = model
        super.init(method: TokenTradeMethodButton(isBuying: model.isBuying),
                   controls: TokenTradeInputControls(model: model, continueAction: continueAction),
                   keypadAccessibilityPrefix: "tokenTrade")
        [feePresence, impactPresence, hintPresence].forEach { amountCard.addSubview($0) }
        amountField.onChange = { [weak model] in model?.userEditedInput($0) }
        conversion.addAction(UIAction { [weak model] _ in model?.toggleUnit() }, for: .touchUpInside)
        method.addAction(UIAction { _ in selectMethod() }, for: .touchUpInside)
        fee.onSizeChange = { [weak self] in self?.updateLayout(animated: true) }
        impact.accessibilityIdentifier = "tokenTrade.impactWarning"
        hint.accessibilityIdentifier = "tokenTrade.hint"
        observe { [weak self] in self?.refreshContent() }
        observe { [weak self] in self?.refreshCardMaximum() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { cardMaximumTask?.cancel() }

    private func refreshContent() {
        let animated = rendered && window != nil && TokenTradeMotion.enabled
        let isTokenAmount = model.isTokenAmount
        let currency = model.currency
        let hasAmount = model.hasAmount
        amountField.configure(input: model.input, decimals: model.inputDecimals,
                              prefix: isTokenAmount ? "" : currency.sign,
                              suffix: isTokenAmount ? model.token.symbol : "", hasAmount: hasAmount)
        amountField.isError = model.hasAmountError
        amountField.accessibilityLabel = lang("Amount") + ", " + (isTokenAmount ? model.token.symbol : currency.rawValue)
        keypad.updateDelete(isEnabled: !model.input.text.isEmpty)
        let conversionText = isTokenAmount
            ? model.typedTokenAmount.convertTo(currency, exchangeRate: model.price).formatted(.baseCurrencyEquivalent)
            : model.displayedTokenAmount.formatted(.defaultAdaptive)
        conversion.update(text: conversionText, isTokenAmount: isTokenAmount, isStale: model.isConversionAmountStale,
                          isEnabled: model.price > 0, animated: animated)
        method.update(token: model.paymentToken, currency: model.cardCurrency, amountText: model.methodAmountText,
                      symbolText: model.methodSymbol, isStale: model.isMethodAmountStale, animated: animated)
        let sellingToken = model.swap.input.sellingToken
        let nativeToken = sellingToken.flatMap { TokenStore.getToken(slug: $0.nativeTokenSlug) }
        let displayedFee = model.fee
        hasFee = displayedFee != nil && sellingToken != nil && nativeToken != nil
        fee.update(fee: displayedFee, sellingToken: sellingToken, nativeToken: nativeToken,
                   currency: TokenStore.baseCurrency, isError: model.hasInsufficientFee, animated: animated)
        feePresence.setContentVisible(hasFee, animated: animated)
        let impactValue = model.displayImpactWarning
        hasImpact = impactValue != nil
        if let impactValue {
            impact.update(.init(title: SwapWarning.title(impact: impactValue), message: SwapWarning.message, isWarning: true), animated: animated)
        }
        impactPresence.setContentVisible(hasImpact, animated: animated)
        let hintValue = model.hint
        let quoteHintText = model.quoteHintText
        hasHint = hintValue != nil || quoteHintText != nil
        if let hintValue {
            let content = SwapHintContent(hint: hintValue, tradeDirection: model.direction)
            hint.update(.init(title: content.title, message: content.message, actionTitle: content.actionTitle), animated: animated)
            hint.onAction = { [weak model] in model?.performHintAction(hintValue) }
        } else if let quoteHintText {
            hint.update(.init(title: "", message: quoteHintText), animated: animated)
            hint.onAction = nil
        }
        hintPresence.setContentVisible(hasHint, animated: animated)
        rendered = true
        updateLayout(animated: animated)
    }

    private func refreshCardMaximum() {
        let request = model.cardMaximumRequest
        guard window != nil, request != cardMaximumRequest else { return }
        cardMaximumRequest = request
        cardMaximumTask?.cancel()
        cardMaximumTask = Task { [weak model] in
            guard let model else { return }
            await model.refreshCardMaximum()
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            cardMaximumTask?.cancel()
            cardMaximumTask = nil
            cardMaximumRequest = nil
        } else { refreshCardMaximum() }
    }

    private func updateLayout(animated: Bool) {
        setNeedsLayout()
        guard !bounds.isEmpty else { return }
        TokenTradeMotion.animate(animated) { self.layoutIfNeeded() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0 else { return }
        let feeHeight = hasFee ? ceil(fee.sizeThatFits(CGSize(width: max(1, bounds.width - 48), height: .greatestFiniteMagnitude)).height) : 0
        let noticeWidth = max(1, bounds.width - 32)
        let impactHeight = hasImpact ? impact.sizeThatFits(CGSize(width: noticeWidth, height: .greatestFiniteMagnitude)).height : 0
        let hintHeight = hasHint ? hint.sizeThatFits(CGSize(width: noticeWidth, height: .greatestFiniteMagnitude)).height : 0
        let layout = TokenTradeLayout(size: bounds.size, bottomSafeArea: safeAreaInsets.bottom,
                                     navigationBarSpace: hasTopNavigationBar ? 64 : 0,
                                     feeHeight: feeHeight, impactHeight: impactHeight, hintHeight: hintHeight)
        layoutEntry(layout)
        var y = layout.footerTop
        if hasFee {
            TokenTradeMotion.place(feePresence, in: CGRect(x: 24, y: y, width: max(0, bounds.width - 48), height: feeHeight))
            y += feeHeight + 8
        }
        if hasImpact {
            TokenTradeMotion.place(impactPresence, in: CGRect(x: 16, y: y, width: noticeWidth, height: impactHeight))
            y += impactHeight + 8
        }
        if hasHint { TokenTradeMotion.place(hintPresence, in: CGRect(x: 16, y: y, width: noticeWidth, height: hintHeight)) }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        setNeedsLayout()
    }
}

typealias TokenTradeLayout = NativeTradeLayout

final class TokenTradeInputControls: UIView {
    private let model: TokenTradeModel
    private let controls: NativeTradeInputControls
    private var rendered = false

    init(model: TokenTradeModel, continueAction: @escaping () -> Void) {
        self.model = model
        controls = NativeTradeInputControls(percentages: [25, 50, 100], accessibilityPrefix: "tokenTrade",
            onFraction: { [weak model] in model?.useFraction($0) }, onContinue: continueAction)
        super.init(frame: .zero)
        controls.continueButton.button.accessibilityIdentifier = "tokenTrade.continue"
        addSubview(controls)
        observe { [weak self] in self?.update() }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func update() {
        let animated = rendered && window != nil && TradeMotion.enabled
        controls.update(configuration: model.buttonConfiguration,
            tintColor: UIColor(hex: model.isBuying ? "#34C759" : "#FF383C"),
            showsContinue: model.hasAmount || (model.cardCurrency != nil && model.isBuying),
            fractionsEnabled: (model.maximumTokenAmount?.amount ?? 0) > 0, animated: animated,
            onRender: { [weak model] in model?.swap.quoteDiagnostics.rendered($0, button: $1, renderedTitle: $2) })
        rendered = true
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        TradeMotion.place(controls, in: bounds)
    }
}
