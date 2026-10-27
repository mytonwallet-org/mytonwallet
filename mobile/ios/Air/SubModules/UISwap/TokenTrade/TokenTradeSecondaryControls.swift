import UIKit
import UIComponents
import WalletCore
import WalletContext

final class TokenTradeConversionButton: TokenTradePressButton {
    private let replacement = BlurReplaceView()
    private var value = TokenTradeValueLabel(font: .systemFont(ofSize: 14, weight: .medium), color: .air.secondaryLabel)
    private lazy var shine = TokenTradeShineView(content: replacement)
    private let converter = UIImageView(image: UIImage(named: "TokenTradeConverter", in: AirBundle, compatibleWith: nil)?.withRenderingMode(.alwaysTemplate))
    private var isTokenAmount: Bool?

    override init(frame: CGRect) {
        super.init(frame: frame)
        content.backgroundColor = UIColor.air.secondaryLabel.withAlphaComponent(0.12)
        content.layer.cornerRadius = 13
        replacement.maximumBlurRadius = 4
        replacement.animationDuration = TokenTradeMotion.duration
        replacement.replaceContent(with: value, animated: false)
        converter.tintColor = .air.secondaryLabel
        content.addSubview(shine)
        content.addSubview(converter)
        accessibilityIdentifier = "tokenTrade.unit"
        accessibilityLabel = lang("Switch Amount Currency")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(text: String, isTokenAmount: Bool, isStale: Bool, isEnabled: Bool, animated: Bool) {
        if let previous = self.isTokenAmount, previous != isTokenAmount {
            value = TokenTradeValueLabel(font: .systemFont(ofSize: 14, weight: .medium), color: .air.secondaryLabel)
            value.setText(text, animated: false)
            replacement.replaceContent(with: value, animated: animated && TokenTradeMotion.enabled)
        } else { value.setText(text, animated: animated) }
        self.isTokenAmount = isTokenAmount
        self.isEnabled = isEnabled
        shine.setActive(isStale, animated: animated)
        accessibilityValue = text
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    func refreshMotionPolicy() { shine.refreshMotionPolicy() }

    override var intrinsicContentSize: CGSize { CGSize(width: value.intrinsicContentSize.width + 32, height: 26) }

    override func layoutSubviews() {
        super.layoutSubviews()
        TokenTradeMotion.place(shine, in: CGRect(x: 8, y: 0, width: max(0, bounds.width - 32), height: 26))
        TokenTradeMotion.place(converter, in: CGRect(x: bounds.width - 20, y: 5, width: 12, height: 16))
    }
}

final class TokenTradeMethodButton: TokenTradePressButton {
    private let icon = BlurReplaceView()
    private let methodTitleLabel = UILabel()
    private let amount = TokenTradeValueLabel(font: .systemFont(ofSize: 17), color: .label)
    private lazy var shine = TokenTradeShineView(content: amount)
    private lazy var amountPresence = TokenTradePresenceView(shine)
    private let symbol = BlurReplaceView()
    private var symbolLabel = UILabel()
    private let badgeLabel = UILabel()
    private lazy var badge = TokenTradePresenceView(badgeLabel)
    private let chevron = UIImageView(image: UIImage(named: "TokenTradeDropdown", in: AirBundle, compatibleWith: nil)?.withRenderingMode(.alwaysTemplate))
    private var iconIdentity: String?
    private var showsAmount = false
    private var showsBadge = false

    init(isBuying: Bool) {
        super.init(frame: .zero)
        content.backgroundColor = .air.pickerBackground
        content.layer.cornerRadius = 26
        content.layer.cornerCurve = .continuous
        [icon, methodTitleLabel, amountPresence, symbol, badge, chevron].forEach { content.addSubview($0) }
        methodTitleLabel.text = lang(isBuying ? "You Pay" : "You Receive")
        methodTitleLabel.font = .systemFont(ofSize: 17, weight: .medium)
        methodTitleLabel.textColor = .label
        methodTitleLabel.adjustsFontSizeToFitWidth = true
        methodTitleLabel.minimumScaleFactor = 0.7
        badgeLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        badgeLabel.textAlignment = .center
        badgeLabel.textColor = .air.secondaryLabel
        badgeLabel.backgroundColor = .air.thumbBackground
        badgeLabel.layer.cornerRadius = 4
        badgeLabel.clipsToBounds = true
        chevron.tintColor = .air.secondaryLabel
        for replacement in [icon, symbol] {
            replacement.maximumBlurRadius = 4
            replacement.animationDuration = TokenTradeMotion.duration
        }
        accessibilityIdentifier = "tokenTrade.method"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(token: ApiToken?, currency: MBaseCurrency?, amountText: String?, symbolText: String,
                isStale: Bool, animated: Bool) {
        let identity = currency?.rawValue ?? token?.slug ?? ""
        if iconIdentity != identity {
            iconIdentity = identity
            let image: UIView
            if let currency { image = TokenTradeCurrencyIcon(currency: currency) }
            else {
                let tokenIcon = IconView(size: 28)
                tokenIcon.setChainSize(12, borderWidth: 1.2, horizontalOffset: 3.2, verticalOffset: 1.2)
                tokenIcon.config(with: token, isStaking: false, isWalletView: false, shouldShowChain: true)
                image = tokenIcon
            }
            icon.replaceContent(with: image, animated: animated && TokenTradeMotion.enabled)
        }
        if symbolLabel.text != symbolText {
            let label = UILabel()
            label.text = symbolText
            label.font = .systemFont(ofSize: 17)
            label.textColor = .air.secondaryLabel
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.7
            symbolLabel = label
            symbol.replaceContent(with: label, animated: animated && TokenTradeMotion.enabled)
        }
        showsAmount = amountText != nil
        if let amountText { amount.setText(amountText, animated: animated) }
        amountPresence.setVisible(showsAmount, animated: animated)
        shine.setActive(isStale && showsAmount, animated: animated)
        showsBadge = currency == nil && token.map { $0.chain.usdtSlug.values.contains($0.slug) } == true
        badgeLabel.text = token?.chain.usdtBadgeText
        badge.setVisible(showsBadge, animated: animated)
        accessibilityLabel = [methodTitleLabel.text, amountText, symbolText, showsBadge ? badgeLabel.text : nil].compactMap { $0 }.joined(separator: ", ")
        setNeedsLayout()
    }

    func refreshMotionPolicy() { shine.refreshMotionPolicy() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let rtl = effectiveUserInterfaceLayoutDirection == .rightToLeft
        func place(_ view: UIView, _ frame: CGRect) {
            var frame = frame
            if rtl { frame.origin.x = bounds.width - frame.maxX }
            TokenTradeMotion.place(view, in: frame)
        }
        place(icon, CGRect(x: 12, y: 12, width: 28, height: 28))
        var right = bounds.width - 14
        place(chevron, CGRect(x: right - 10, y: 15, width: 10, height: 22))
        right -= 14
        if showsBadge {
            let width = ceil(badgeLabel.intrinsicContentSize.width) + 6
            place(badge, CGRect(x: right - width, y: 19, width: width, height: 14))
            right -= width + 4
        }
        let symbolWidth = min(ceil(symbolLabel.intrinsicContentSize.width), max(0, right - 126))
        place(symbol, CGRect(x: right - symbolWidth, y: 0, width: symbolWidth, height: 52))
        right -= symbolWidth + 4
        let titleWidth = min(ceil(methodTitleLabel.intrinsicContentSize.width), max(0, right - 50))
        place(methodTitleLabel, CGRect(x: 50, y: 0, width: titleWidth, height: 52))
        let amountWidth = min(amount.intrinsicContentSize.width, max(0, right - 54 - titleWidth))
        if showsAmount { place(amountPresence, CGRect(x: right - amountWidth, y: 0, width: amountWidth, height: 52)) }
    }
}

private final class TokenTradeCurrencyIcon: UIView {
    private let gradient = CAGradientLayer()
    private let label = UILabel()

    init(currency: MBaseCurrency) {
        super.init(frame: .zero)
        gradient.colors = [UIColor(red: 160/255, green: 222/255, blue: 126/255, alpha: 1).cgColor,
                           UIColor(red: 84/255, green: 203/255, blue: 104/255, alpha: 1).cgColor]
        layer.addSublayer(gradient)
        layer.cornerRadius = 14
        clipsToBounds = true
        label.text = currency.sign
        label.textColor = .white
        label.font = .roundedNative(ofSize: 20, weight: .bold)
        label.textAlignment = .center
        addSubview(label)
        accessibilityElementsHidden = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = bounds
        label.frame = bounds
    }
}

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
