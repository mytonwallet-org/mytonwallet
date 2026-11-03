import UIKit
import WalletCore
import WalletContext

public final class TradeConversionControl: TradePressButton {
    public var isSelectable = true {
        didSet {
            isUserInteractionEnabled = isSelectable
            converter.isHidden = !isSelectable
            accessibilityTraits = isSelectable ? .button : .staticText
            accessibilityLabel = isSelectable ? lang("Switch Amount Currency") : nil
            invalidateIntrinsicContentSize()
            setNeedsLayout()
        }
    }
    private let replacement = BlurReplaceView()
    private var value = TradeValueLabel(font: WTypography.uiFont(.supportingEmphasized, content: .technical), color: .air.secondaryLabel)
    private lazy var shine = TradeShineView(content: replacement)
    private let converter = UIImageView(image: UIImage(named: "TokenTradeConverter", in: AirBundle, compatibleWith: nil)?.withRenderingMode(.alwaysTemplate))
    private var isTokenAmount: Bool?

    public override init(frame: CGRect) {
        super.init(frame: frame)
        content.backgroundColor = UIColor.air.secondaryLabel.withAlphaComponent(0.12)
        content.layer.cornerRadius = 13
        replacement.maximumBlurRadius = 4
        replacement.animationDuration = TradeMotion.duration
        replacement.replaceContent(with: value, animated: false)
        converter.tintColor = .air.secondaryLabel
        content.addSubview(shine)
        content.addSubview(converter)
        accessibilityIdentifier = "tokenTrade.unit"
        accessibilityLabel = lang("Switch Amount Currency")
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public func update(text: String, isTokenAmount: Bool, isStale: Bool, isEnabled: Bool, animated: Bool) {
        if let previous = self.isTokenAmount, previous != isTokenAmount {
            value = TradeValueLabel(font: WTypography.uiFont(.supportingEmphasized, content: .technical), color: .air.secondaryLabel)
            value.setText(text, animated: false)
            replacement.replaceContent(with: value, animated: animated && TradeMotion.enabled)
        } else { value.setText(text, animated: animated) }
        self.isTokenAmount = isTokenAmount
        self.isEnabled = isEnabled
        shine.setActive(isStale, animated: animated)
        accessibilityValue = text
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    public func refreshMotionPolicy() { shine.refreshMotionPolicy() }

    public override var intrinsicContentSize: CGSize { CGSize(width: value.intrinsicContentSize.width + horizontalPadding, height: 26) }

    private var horizontalPadding: CGFloat { isSelectable ? 32 : 16 }

    public override func layoutSubviews() {
        super.layoutSubviews()
        TradeMotion.place(shine, in: CGRect(x: 8, y: 0, width: max(0, bounds.width - horizontalPadding), height: 26))
        TradeMotion.place(converter, in: CGRect(x: bounds.width - 20, y: 5, width: 12, height: 16))
    }
}

public final class TradePaymentControl: TradePressButton {
    private let icon = BlurReplaceView()
    private let methodTitleLabel = UILabel()
    private let amount = TradeValueLabel(font: WTypography.uiFont(.body, content: .technical), color: .label)
    private lazy var shine = TradeShineView(content: amount)
    private lazy var amountPresence = TradePresenceView(shine)
    private let symbol = BlurReplaceView()
    private var symbolLabel = UILabel()
    private let badgeLabel = UILabel()
    private lazy var badge = TradePresenceView(badgeLabel)
    private let chevron = UIImageView(image: UIImage(named: "TokenTradeDropdown", in: AirBundle, compatibleWith: nil)?.withRenderingMode(.alwaysTemplate))
    private var iconIdentity: String?
    private var showsAmount = false
    private var showsBadge = false
    private var selectable = true
    private let shouldShowChain: Bool

    public init(isBuying: Bool, shouldShowChain: Bool = true) {
        self.shouldShowChain = shouldShowChain
        super.init(frame: .zero)
        content.backgroundColor = .air.pickerBackground
        content.layer.cornerRadius = 26
        content.layer.cornerCurve = .continuous
        [icon, methodTitleLabel, amountPresence, symbol, badge, chevron].forEach { content.addSubview($0) }
        methodTitleLabel.text = lang(isBuying ? "You Pay" : "You Receive")
        methodTitleLabel.font = WTypography.uiFont(.bodyEmphasized)
        methodTitleLabel.textColor = .label
        methodTitleLabel.adjustsFontSizeToFitWidth = true
        methodTitleLabel.minimumScaleFactor = 0.7
        badgeLabel.font = WTypography.uiFont(.badge)
        badgeLabel.textAlignment = .center
        badgeLabel.textColor = .air.secondaryLabel
        badgeLabel.backgroundColor = .air.thumbBackground
        badgeLabel.layer.cornerRadius = 4
        badgeLabel.clipsToBounds = true
        chevron.tintColor = .air.secondaryLabel
        for replacement in [icon, symbol] {
            replacement.maximumBlurRadius = 4
            replacement.animationDuration = TradeMotion.duration
        }
        accessibilityIdentifier = "tokenTrade.method"
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public func setTitle(_ title: String, color: UIColor = .label, selectable: Bool) {
        methodTitleLabel.text = title
        methodTitleLabel.textColor = color
        self.selectable = selectable
        isUserInteractionEnabled = selectable
        chevron.isHidden = !selectable
        accessibilityTraits = selectable ? .button : .staticText
        setNeedsLayout()
    }

    public func update(token: ApiToken?, currency: MBaseCurrency?, amountText: String?, symbolText: String,
                isStale: Bool, animated: Bool) {
        let identity = currency?.rawValue ?? token?.slug ?? ""
        if iconIdentity != identity {
            iconIdentity = identity
            let image: UIView
            if let currency { image = TradeCurrencyIcon(currency: currency) }
            else {
                let tokenIcon = IconView(size: 28)
                tokenIcon.setChainSize(12, borderWidth: 1.2, horizontalOffset: 3.2, verticalOffset: 1.2)
                tokenIcon.config(with: token, isStaking: false, isWalletView: false, shouldShowChain: shouldShowChain)
                image = tokenIcon
            }
            icon.replaceContent(with: image, animated: animated && TradeMotion.enabled)
        }
        if symbolLabel.text != symbolText {
            let label = UILabel()
            label.text = symbolText
            label.font = WTypography.uiFont(.body, content: .technical)
            label.textColor = .air.secondaryLabel
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.7
            symbolLabel = label
            symbol.replaceContent(with: label, animated: animated && TradeMotion.enabled)
        }
        showsAmount = amountText != nil
        if let amountText { amount.setText(amountText, animated: animated) }
        amountPresence.setContentVisible(showsAmount, animated: animated)
        shine.setActive(isStale && showsAmount, animated: animated)
        showsBadge = currency == nil && token.map { $0.chain.usdtSlug.values.contains($0.slug) } == true
        badgeLabel.text = token?.chain.usdtBadgeText
        badge.setContentVisible(showsBadge, animated: animated)
        accessibilityLabel = [methodTitleLabel.text, amountText, symbolText, showsBadge ? badgeLabel.text : nil].compactMap { $0 }.joined(separator: ", ")
        setNeedsLayout()
    }

    public func refreshMotionPolicy() { shine.refreshMotionPolicy() }

    public override func layoutSubviews() {
        super.layoutSubviews()
        let rtl = effectiveUserInterfaceLayoutDirection == .rightToLeft
        func place(_ view: UIView, _ frame: CGRect) {
            var frame = frame
            if rtl { frame.origin.x = bounds.width - frame.maxX }
            TradeMotion.place(view, in: frame)
        }
        place(icon, CGRect(x: 12, y: 12, width: 28, height: 28))
        var right = bounds.width - 14
        place(chevron, CGRect(x: right - 10, y: 15, width: 10, height: 22))
        if selectable { right -= 14 }
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

private final class TradeCurrencyIcon: UIView {
    private let gradient = CAGradientLayer()
    private let label = UILabel()

    public init(currency: MBaseCurrency) {
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

    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    public override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = bounds
        label.frame = bounds
    }
}
