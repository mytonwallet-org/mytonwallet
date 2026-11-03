import Combine
import UIKit
import SwiftNavigation
import UIComponents
import WalletCore
import WalletContext

/// A retained UIKit tree. Model observation updates content; layout and animation never read the model.
final class TokenTradeView: UIView {
    private let model: TokenTradeModel
    var hasTopNavigationBar = true {
        didSet { if hasTopNavigationBar != oldValue { setNeedsLayout() } }
    }
    let amountField = TokenTradeTextField()
    let scrollView = UIScrollView()
    let methodButton: TokenTradeMethodButton
    private let amountCard = UIView()
    private let controlsBackground = UIView()
    private let editor: TokenTradeEditor
    private let conversion = TokenTradeConversionButton(frame: .zero)
    private let fee = TokenTradeFeeButton(frame: .zero)
    private let impact = TokenTradeNoticeView(frame: .zero)
    private let hint = TokenTradeNoticeView(frame: .zero)
    private lazy var feePresence = TokenTradePresenceView(fee)
    private lazy var impactPresence = TokenTradePresenceView(impact)
    private lazy var hintPresence = TokenTradePresenceView(hint)
    private let inputControls: TokenTradeInputControls
    private let keypad: TokenTradeKeypad
    private var hasFee = false
    private var hasImpact = false
    private var hasHint = false
    private var rendered = false
    private var environmentSubscription: AnyCancellable?
    private var cardMaximumRequest: TokenTradeModel.CardMaximumRequest?
    private var cardMaximumTask: Task<Void, Never>?

    init(model: TokenTradeModel, selectMethod: @escaping () -> Void, continueAction: @escaping () -> Void) {
        self.model = model
        methodButton = TokenTradeMethodButton(isBuying: model.isBuying)
        inputControls = TokenTradeInputControls(model: model, continueAction: continueAction)
        let editor = TokenTradeEditor()
        self.editor = editor
        keypad = TokenTradeKeypad(editor: editor)
        super.init(frame: .zero)
        backgroundColor = .air.headerBackground
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.showsVerticalScrollIndicator = false
        scrollView.delaysContentTouches = false
        scrollView.keyboardDismissMode = .none
        addSubview(scrollView)
        addSubview(controlsBackground)
        scrollView.addSubview(amountCard)
        scrollView.addSubview(methodButton)
        [conversion, amountField, feePresence, impactPresence, hintPresence].forEach { amountCard.addSubview($0) }
        controlsBackground.addSubview(inputControls)
        controlsBackground.addSubview(keypad)
        amountCard.backgroundColor = .air.pickerBackground
        amountCard.layer.cornerRadius = 32
        amountCard.layer.cornerCurve = .continuous
        controlsBackground.backgroundColor = .air.pickerBackground
        controlsBackground.layer.cornerRadius = 32
        controlsBackground.layer.cornerCurve = .continuous
        controlsBackground.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        editor.field = amountField
        amountField.caretColor = AirTintColor
        amountField.onChange = { [weak model] in model?.userEditedInput($0) }
        conversion.addAction(UIAction { [weak model] _ in model?.toggleUnit() }, for: .touchUpInside)
        methodButton.addAction(UIAction { _ in selectMethod() }, for: .touchUpInside)
        fee.onSizeChange = { [weak self] in self?.updateLayout(animated: true) }
        impact.accessibilityIdentifier = "tokenTrade.impactWarning"
        hint.accessibilityIdentifier = "tokenTrade.hint"
        observe { [weak self] in self?.refreshContent() }
        observe { [weak self] in self?.refreshCardMaximum() }
        let environment = CardBackgroundAnimationEnvironment.shared
        environmentSubscription = Publishers.CombineLatest4(environment.$applicationActive, environment.$animationsEnabled,
            environment.$lowPowerMode, environment.$reduceMotion).sink { [weak self] _ in
                // Read policy after @Published completes its write.
                guard let self else { return }
                DispatchQueue.main.async { [weak self] in self?.refreshMotionPolicy() }
            }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { cardMaximumTask?.cancel() }

    func install(in parent: UIView) {
        translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(self)
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: parent.leadingAnchor), trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            topAnchor.constraint(equalTo: parent.topAnchor), bottomAnchor.constraint(equalTo: parent.bottomAnchor)
        ])
    }

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
        methodButton.update(token: model.paymentToken, currency: model.cardCurrency, amountText: model.methodAmountText,
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
        hasHint = hintValue != nil
        if let hintValue {
            let content = SwapHintContent(hint: hintValue, tradeDirection: model.direction)
            hint.update(.init(title: content.title, message: content.message, actionTitle: content.actionTitle), animated: animated)
            hint.onAction = { [weak model] in model?.performHintAction(hintValue) }
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

    private func refreshMotionPolicy() {
        let active = window != nil && CardBackgroundAnimationEnvironment.shared.applicationActive
        amountField.configureAnimation(active: active, animated: active && TokenTradeMotion.enabled)
        // Refresh only the two pending-quote masks; their animation state is independent of layout.
        conversion.refreshMotionPolicy()
        methodButton.refreshMotionPolicy()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        refreshMotionPolicy()
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
        TokenTradeMotion.place(scrollView, in: layout.scroll)
        TokenTradeMotion.place(amountCard, in: layout.card)
        TokenTradeMotion.place(methodButton, in: layout.method)
        scrollView.contentSize = CGSize(width: bounds.width, height: layout.contentHeight)
        scrollView.alwaysBounceVertical = layout.contentHeight > layout.scroll.height
        TokenTradeMotion.place(controlsBackground, in: layout.controls)
        TokenTradeMotion.place(inputControls, in: CGRect(x: 24, y: 24, width: max(0, bounds.width - 48), height: 52))
        TokenTradeMotion.place(keypad, in: CGRect(x: 0, y: 88, width: bounds.width, height: layout.keypadHeight))
        amountField.maximumHeight = layout.maximumAmountHeight
        let amountWidth = max(1, bounds.width - 28)
        let fieldHeight = amountField.fittingHeight(forWidth: amountWidth)
        let top = layout.amountTop + max(0, (layout.maximumAmountHeight - fieldHeight) / 2)
        let conversionWidth = min(max(0, bounds.width - 48), conversion.intrinsicContentSize.width)
        let rtl = effectiveUserInterfaceLayoutDirection == .rightToLeft
        TokenTradeMotion.place(conversion, in: CGRect(x: rtl ? bounds.width - 24 - conversionWidth : 24,
                                                       y: top, width: conversionWidth, height: 26))
        TokenTradeMotion.place(amountField, in: CGRect(x: rtl ? 4 : 24, y: top + 26, width: amountWidth, height: fieldHeight))
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
