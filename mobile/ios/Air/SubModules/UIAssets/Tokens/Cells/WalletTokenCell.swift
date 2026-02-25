//
//  WalletTokenCell.swift
//  UIHome
//
//  Created by Sina on 3/26/24.
//

import UIComponents
import UIKit
import WalletContext
import WalletCore

public class WalletTokenCell: WHighlightCell {
    public static let defaultHeight = 60.0

    private static let pinIconSideLength: CGFloat = 12
    private static let pinIconSpacing: CGFloat = 4
    private static let tokenImageToTextSpacing: CGFloat = 12

    private let medium16Font = UIFont.systemFont(ofSize: 16, weight: .medium)
    private let regular16Font = UIFont.systemFont(ofSize: 16, weight: .regular)
    private let regular14Font = UIFont.systemFont(ofSize: 14, weight: .regular)

    private static let pinningColor: UIColor = UIColor.air.altHighlight.withAlphaComponent(0.4)
    
    public var walletToken: MTokenBalance?
    private var tokenImage: String?

    public var isUIAssets: Bool { false }
    
    public override var safeAreaInsets: UIEdgeInsets { isUIAssets ? super.safeAreaInsets : .zero }

    private let mainView: UIView = UIView()
    private var tokenLabelLeadingConstraint: NSLayoutConstraint!
    // left icon view
    private var iconView: IconView!
    // pin icon view
    private var pinIconView: UIView = configured(object: UIImageView()) {
        $0.translatesAutoresizingMaskIntoConstraints = false
        $0.image = UIImage(systemName: "pin.fill")
        $0.tintColor = .air.headerSecondaryLabel
        $0.contentMode = .scaleAspectFit
    }

    // shown out of bounds of first pinned cell. This way color under navBar moves smoothly with first cell when scrolled
    public let underNavigationBarColorView: UIView = configured(object: UIView()) {
        $0.translatesAutoresizingMaskIntoConstraints = false
        $0.backgroundColor = WalletTokenCell.pinningColor
        $0.isHidden = true
    }
    
    // address label to show short presentation of the address
    private let tokenNameLabel: UILabel = UILabel()
    private var tokenPriceLabel: UILabel!
    private var amountContainer: WSensitiveData<UILabel> = .init(cols: 12, rows: 2, cellSize: 9, cornerRadius: 5, theme: .adaptive, alignment: .trailing)
    private var amountLabel: WAmountLabel!
    private var amount2Container: WSensitiveData<UILabel> = .init(cols: 9, rows: 2, cellSize: 7, cornerRadius: 4, theme: .adaptive, alignment: .trailing)
    private var baseCurrencyAmountLabel: WAmountLabel!
    private var separatorView: UIView!
    private let badge = BadgeView()
    private var onSelect: (() -> Void)?

    public override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }

    @available(*, unavailable)
    public required init?(coder _: NSCoder) { nil }
    
    public override func prepareForReuse() {
        super.prepareForReuse()
        underNavigationBarColorView.isHidden = true
    }
    
    private func setupViews() {
        isExclusiveTouch = true
        selectionStyle = .none
        contentView.isUserInteractionEnabled = true
        contentView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(itemSelected)))
        
        mainView.backgroundColor = .clear
        contentView.addStretchedToBounds(subview: mainView, insets: UIEdgeInsets(top: 10, left: 12, bottom: 10, right: 12))
        
        // left icon
        iconView = IconView(size: 40)
        mainView.addSubview(iconView)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: mainView.leadingAnchor),
            iconView.centerYAnchor.constraint(equalTo: mainView.centerYAnchor),
        ])
        iconView.layer.cornerRadius = 20
        iconView.setChainSize(14, borderWidth: 1.333, borderColor: WTheme.background, horizontalOffset: 3, verticalOffset: 1)

        // tokenName
        mainView.addSubview(tokenNameLabel)
        tokenNameLabel.translatesAutoresizingMaskIntoConstraints = false
        tokenLabelLeadingConstraint = tokenNameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor,
                                                                              constant: Self.tokenImageToTextSpacing)
        NSLayoutConstraint.activate([
            tokenLabelLeadingConstraint,
            tokenNameLabel.topAnchor.constraint(equalTo: mainView.topAnchor, constant: 1.667),
        ])
        tokenNameLabel.font = medium16Font
        tokenNameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tokenNameLabel.lineBreakMode = .byTruncatingTail

        // pin icon
        mainView.addSubview(pinIconView)
        NSLayoutConstraint.activate([
            pinIconView.widthAnchor.constraint(equalToConstant: Self.pinIconSideLength),
            pinIconView.heightAnchor.constraint(equalToConstant: Self.pinIconSideLength),
            pinIconView.centerYAnchor.constraint(equalTo: tokenNameLabel.centerYAnchor),
            tokenNameLabel.leadingAnchor.constraint(equalTo: pinIconView.trailingAnchor, constant: Self.pinIconSpacing),
        ])
        pinIconView.isHidden = true

        self.addSubview(underNavigationBarColorView)
        NSLayoutConstraint.activate([
            underNavigationBarColorView.heightAnchor.constraint(equalToConstant: 100),
            underNavigationBarColorView.bottomAnchor.constraint(equalTo: self.topAnchor),
            underNavigationBarColorView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            self.trailingAnchor.constraint(equalTo: underNavigationBarColorView.trailingAnchor),
        ])
        
        // price
        tokenPriceLabel = UILabel()
        tokenPriceLabel.translatesAutoresizingMaskIntoConstraints = false
        mainView.addSubview(tokenPriceLabel)
        NSLayoutConstraint.activate([
            tokenPriceLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: Self.tokenImageToTextSpacing),
            tokenPriceLabel.topAnchor.constraint(equalTo: tokenNameLabel.bottomAnchor, constant: 1),
        ])
        tokenPriceLabel.font = regular14Font

        amountLabel = WAmountLabel(showNegativeSign: false)
        amountLabel.font = regular16Font
        amountLabel.translatesAutoresizingMaskIntoConstraints = false
        amountContainer.addContent(amountLabel)
        mainView.addSubview(amountContainer)
        NSLayoutConstraint.activate([
            amountLabel.trailingAnchor.constraint(equalTo: mainView.trailingAnchor),
            amountLabel.firstBaselineAnchor.constraint(equalTo: tokenNameLabel.firstBaselineAnchor),
            amountLabel.leadingAnchor.constraint(greaterThanOrEqualTo: tokenNameLabel.trailingAnchor, constant: 6).withPriority(.defaultHigh),
        ])

        baseCurrencyAmountLabel = WAmountLabel(showNegativeSign: true)
        baseCurrencyAmountLabel.font = regular14Font
        baseCurrencyAmountLabel.translatesAutoresizingMaskIntoConstraints = false
        amount2Container.addContent(baseCurrencyAmountLabel)
        mainView.addSubview(amount2Container)
        NSLayoutConstraint.activate([
            baseCurrencyAmountLabel.trailingAnchor.constraint(equalTo: amountLabel.trailingAnchor),
            baseCurrencyAmountLabel.firstBaselineAnchor.constraint(equalTo: tokenPriceLabel.firstBaselineAnchor),
        ])

        amountContainer.isTapToRevealEnabled = false
        amount2Container.isTapToRevealEnabled = false

        // apy
        badge.translatesAutoresizingMaskIntoConstraints = false
        mainView.addSubview(badge)
        NSLayoutConstraint.activate([
            badge.centerYAnchor.constraint(equalTo: tokenNameLabel.centerYAnchor, constant: -0.333),
            badge.leadingAnchor.constraint(equalTo: tokenNameLabel.trailingAnchor, constant: 4),
            badge.trailingAnchor.constraint(lessThanOrEqualTo: amountLabel.leadingAnchor, constant: -4),
        ])
        badge.alpha = 0

        // separator
        separatorView = UIView()
        separatorView.translatesAutoresizingMaskIntoConstraints = false
        separatorView.backgroundColor = IOS_26_MODE_ENABLED ? UIColor.separator : isUIAssets ? WTheme.separatorDarkBackground : WTheme.separator
        addSubview(separatorView)
        NSLayoutConstraint.activate([
            separatorView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: 0),
            separatorView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: IOS_26_MODE_ENABLED ? -12 : 0),
            separatorView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 62),
            separatorView.heightAnchor.constraint(equalToConstant: IOS_26_MODE_ENABLED ? 1 : 0.33),
        ])

        contentView.backgroundColor = .clear

        updateTheme()
    }

    func updateTheme() {
        baseBackgroundColor = .clear
        highlightBackgroundColor = WTheme.highlight
        tokenNameLabel.textColor = WTheme.primaryLabel
        amountLabel.textColor = WTheme.primaryLabel
        tokenPriceLabel.textColor = WTheme.balanceHeaderView.secondary
        baseCurrencyAmountLabel.textColor = WTheme.balanceHeaderView.secondary
    }

    // MARK: - Configure using MTokenBalance

    private var prevToken: String?

    public func configure(with walletToken: MTokenBalance,
                          isLast: Bool,
                          animated: Bool = true,
                          badgeContent: BadgeContent?,
                          isMultichain: Bool,
                          isPinned: Bool,
                          highlightBackgroundWhenPinned: Bool,
                          onSelect: @escaping () -> Void) {
        let previousTokenSlug = self.walletToken?.tokenSlug
        let previousBalance = self.walletToken?.balance
        let previousBaseCurrencyAmount = self.walletToken?.toBaseCurrency
        let tokenChanged = previousTokenSlug != walletToken.tokenSlug
        self.walletToken = walletToken
        self.onSelect = onSelect
        // token
        let token = TokenStore.getToken(slug: walletToken.tokenSlug)

        // configure icon view
        if tokenChanged || tokenImage != token?.image?.nilIfEmpty {
            tokenImage = token?.image?.nilIfEmpty
            iconView.config(with: token, isStaking: walletToken.isStaking, isWalletView: true, shouldShowChain: isMultichain)
        }
        
        // pin icon
        pinIconView.isHidden = !isPinned
        tokenLabelLeadingConstraint.constant =
            isPinned ? Self.tokenImageToTextSpacing + Self.pinIconSideLength + Self.pinIconSpacing : Self.tokenImageToTextSpacing

        contentView.backgroundColor = isPinned && highlightBackgroundWhenPinned ? Self.pinningColor : .clear
        
        // label
        tokenNameLabel.text = if let token {
            MTokenBalance.displayName(apiToken: token, isStaking: walletToken.isStaking)
        } else {
            walletToken.tokenSlug
        }

        // apy
        configureBadge(badgeContent: badgeContent)

        // price
        if let price = token?.price {
            let baseCurrencyAmount = BaseCurrencyAmount.fromDouble(price, TokenStore.baseCurrency)
            let attr = NSMutableAttributedString(
                string: baseCurrencyAmount.formatted(.baseCurrencyEquivalent, roundUp: true),
                attributes: [
                    .font: regular14Font,
                    .foregroundColor: WTheme.secondaryLabel,
                ]
            )
            if let percentChange24h = token?.percentChange24h, let percentChange24hRounded = token?.percentChange24hRounded {
                let color = abs(percentChange24h) < 0.005 ? WTheme.secondaryLabel : percentChange24h > 0 ? WTheme.positiveAmount : WTheme.negativeAmount
                if percentChange24hRounded != 0 {
                    attr.append(NSAttributedString(string: " \(formatPercent(percentChange24hRounded / 100))",
                                                   attributes: [.font: regular14Font, .foregroundColor: color]))
                }
            }
            tokenPriceLabel.attributedText = attr
        } else {
            tokenPriceLabel.text = " "
        }
        let amountText: String?
        if let token {
            let amount = TokenAmount(walletToken.balance, token)
            amountText = amount.formatted(.defaultAdaptive, roundUp: false)
        } else {
            amountText = nil
        }

        let amount = walletToken.toBaseCurrency
        let baseCurrencyText: String?
        if let amount {
            let baseCurrencyAmount = BaseCurrencyAmount.fromDouble(amount, TokenStore.baseCurrency)
            baseCurrencyText = baseCurrencyAmount.formatted(.baseCurrencyEquivalent, roundUp: true)
        } else {
            baseCurrencyText = " "
        }
        let shouldAnimateAmounts = animated && !tokenChanged
        let amountChanged = previousBalance != walletToken.balance
        let baseAmountChanged = previousBaseCurrencyAmount != walletToken.toBaseCurrency
        setAmountText(amountText, animated: shouldAnimateAmounts && amountChanged, label: amountLabel)
        setAmountText(baseCurrencyText, animated: shouldAnimateAmounts && baseAmountChanged, label: baseCurrencyAmountLabel)

        let amountCols = 4 + abs((token?.name).hashValue % 8)
        let fiatAmountCols = 5 + (amountCols % 6)
        amountContainer.setCols(amountCols)
        amount2Container.setCols(fiatAmountCols)

        separatorView.isHidden = isLast
        prevToken = token?.slug
    }

    public func configureBadge(badgeContent: BadgeContent?) {
        if let badgeContent {
            switch badgeContent {
            case .staking(let stakingBadge):
                if stakingBadge.isActive {
                    badge.configureStakingActive(yieldType: stakingBadge.yieldType, apy: stakingBadge.yieldValue)
                } else {
                    badge.configureStakingInactive(yieldType: stakingBadge.yieldType, apy: stakingBadge.yieldValue)
                }
            case .chain(let chain):
                badge.configureChain(chain: chain)
            }
            badge.alpha = 1
        } else {
            badge.configureHidden()
            badge.alpha = 0
        }
    }

    private func setAmountText(_ text: String?, animated: Bool, label: UILabel) {
        guard animated else {
            label.text = text
            return
        }
        UIView.transition(
            with: label,
            duration: 0.2,
            options: [.transitionCrossDissolve, .allowUserInteraction, .beginFromCurrentState]
        ) {
            label.text = text
        }
    }

    @objc private func itemSelected(_: UIGestureRecognizer) {
        onSelect?()
    }
}

public class AssetsWalletTokenCell: WalletTokenCell {
    public override var isUIAssets: Bool {
        return true
    }
}
