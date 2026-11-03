import UIKit
import UIComponents
import WalletCore
import WalletContext

typealias TokenTradeConversionButton = TradeConversionControl
typealias TokenTradeMethodButton = TradePaymentControl

final class TokenTradeFeeButton: TokenTradePressButton {
    private let replacement = BlurReplaceView()
    private var label = UILabel()
    private var fee: MFee?
    private var sellingToken: ApiToken?
    private var nativeToken: ApiToken?
    private var currency: MBaseCurrency = .USD
    private var isError = false
    private var showInBaseCurrency = false
    private var currentText: NSAttributedString?
    var onSizeChange: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        content.addSubview(replacement)
        replacement.maximumBlurRadius = 4
        replacement.animationDuration = TokenTradeMotion.duration
        accessibilityIdentifier = "tokenTrade.fee"
        addAction(UIAction { [weak self] _ in
            guard let self, baseCurrencyAmount != nil else { return }
            showInBaseCurrency.toggle()
            updateText(animated: true)
            onSizeChange?()
        }, for: .touchUpInside)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(fee: MFee?, sellingToken: ApiToken?, nativeToken: ApiToken?, currency: MBaseCurrency,
                isError: Bool, animated: Bool) {
        self.fee = fee
        self.sellingToken = sellingToken
        self.nativeToken = nativeToken
        self.currency = currency
        self.isError = isError
        if fee == nil { showInBaseCurrency = false; return }
        updateText(animated: animated)
    }

    private var baseCurrencyAmount: BaseCurrencyAmount? {
        guard let fee, fee.isNativeOnly, let amount = fee.nativeSumOrTerms, amount > 0,
              let nativeToken, let price = nativeToken.price, price > 0 else { return nil }
        return BaseCurrencyAmount(convertAmount(amount, price: price, tokenDecimals: nativeToken.decimals,
                                               baseCurrencyDecimals: currency.decimalsCount), currency)
    }

    private func updateText(animated: Bool) {
        guard var fee, let sellingToken, let nativeToken else { return }
        if fee.precision == .approximate { fee.precision = .exact }
        let separator = isError || fee.precision == .lessThan ? " " : " ~ "
        let color: UIColor = isError ? .air.error : .air.secondaryLabel
        let prefix = NSAttributedString(string: lang("Fee") + separator,
            attributes: [.font: WTypography.uiFont(.supporting), .foregroundColor: color])
        let value: String
        if showInBaseCurrency, let amount = baseCurrencyAmount {
            value = amount.formatted(.baseCurrencyEquivalent, precision: fee.precision)
        } else { value = fee.toString(token: sellingToken, nativeToken: nativeToken) }
        let text = NSMutableAttributedString(attributedString: prefix)
        text.append(NSAttributedString(string: value,
            attributes: [.font: WTypography.uiFont(.supporting, content: .technical), .foregroundColor: color]))
        isUserInteractionEnabled = baseCurrencyAmount != nil
        accessibilityTraits = isUserInteractionEnabled ? .button : .staticText
        accessibilityLabel = text.string
        guard currentText != text else { return }
        currentText = text
        label = UILabel()
        label.attributedText = text
        label.numberOfLines = 2
        label.textAlignment = .right
        replacement.replaceContent(with: label, animated: animated && TokenTradeMotion.enabled)
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        label.sizeThatFits(CGSize(width: size.width, height: .greatestFiniteMagnitude))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        TokenTradeMotion.place(replacement, in: bounds)
    }
}
