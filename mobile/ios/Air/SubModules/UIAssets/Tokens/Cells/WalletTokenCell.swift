//
//  WalletTokenCell.swift
//  UIHome
//
//  Created by Sina on 3/26/24.
//

import UIKit
import WalletCore
import WalletContext
import UIComponents

private let medium16Font = UIFont.systemFont(ofSize: 16, weight: .medium)
private let regular16Font = UIFont.systemFont(ofSize: 16, weight: .regular)
private let regular14Font = UIFont.systemFont(ofSize: 14, weight: .regular)

public class WalletTokenCell: WHighlightCell {

    public static let defaultHeight = 60.0

    public var walletToken: MTokenBalance? = nil
    private var tokenImage: String? = nil
    
    public var isUIAssets: Bool { false }

    public override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var mainView: UIView!
    // left icon view
    private var iconView: IconView!
    // address label to show short presentation of the address
    private var tokenLabel: UILabel!
    private var tokenPriceLabel: UILabel!
    private var amountContainer: WSensitiveData<UILabel> = .init(cols: 12, rows: 2, cellSize: 9, cornerRadius: 5, theme: .adaptive, alignment: .trailing)
    private var amountLabel: WAmountLabel!
    private var amount2Container: WSensitiveData<UILabel> = .init(cols: 9, rows: 2, cellSize: 7, cornerRadius: 4, theme: .adaptive, alignment: .trailing)
    private var baseCurrencyAmountLabel: WAmountLabel!
    private var separatorView: UIView!
    private let badge = BadgeView()
    private var onSelect: (() -> Void)? = nil

    private func setupViews() {
        isExclusiveTouch = true
        selectionStyle = .none
        contentView.isUserInteractionEnabled = true
        contentView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(itemSelected)))
        
        mainView = UIView()
        mainView.translatesAutoresizingMaskIntoConstraints = false
        mainView.backgroundColor = .clear
        contentView.addSubview(mainView)
        NSLayoutConstraint.activate([
            mainView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            mainView.leftAnchor.constraint(equalTo: contentView.leftAnchor, constant: 12),
            mainView.rightAnchor.constraint(equalTo: contentView.rightAnchor, constant: -12),
            mainView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10)
        ])

        // MARK: left icon
        iconView = IconView(size: 40)
        mainView.addSubview(iconView)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: mainView.leadingAnchor),
            iconView.centerYAnchor.constraint(equalTo: mainView.centerYAnchor)
        ])
        iconView.layer.cornerRadius = 20
        iconView.setChainSize(14, borderWidth: 1.333, borderColor: WTheme.background, horizontalOffset: 3, verticalOffset: 1)
        
        tokenLabel = UILabel()
        tokenLabel.translatesAutoresizingMaskIntoConstraints = false
        mainView.addSubview(tokenLabel)
        NSLayoutConstraint.activate([
            tokenLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 11),
            tokenLabel.topAnchor.constraint(equalTo: mainView.topAnchor, constant: 1.667)
        ])
        tokenLabel.font = medium16Font
        tokenLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tokenLabel.lineBreakMode = .byTruncatingTail

        // price
        tokenPriceLabel = UILabel()
        tokenPriceLabel.translatesAutoresizingMaskIntoConstraints = false
        mainView.addSubview(tokenPriceLabel)
        NSLayoutConstraint.activate([
            tokenPriceLabel.leadingAnchor.constraint(equalTo: tokenLabel.leadingAnchor),
            tokenPriceLabel.topAnchor.constraint(equalTo: tokenLabel.bottomAnchor, constant: 1)
        ])
        tokenPriceLabel.font = regular14Font
        
        amountLabel = WAmountLabel(showNegativeSign: false)
        amountLabel.font = regular16Font
        amountLabel.translatesAutoresizingMaskIntoConstraints = false
        amountContainer.addContent(amountLabel)
        mainView.addSubview(amountContainer)
        NSLayoutConstraint.activate([
            amountLabel.trailingAnchor.constraint(equalTo: mainView.trailingAnchor),
            amountLabel.firstBaselineAnchor.constraint(equalTo: tokenLabel.firstBaselineAnchor),
            amountLabel.leadingAnchor.constraint(greaterThanOrEqualTo: tokenLabel.trailingAnchor, constant: 6).withPriority(.defaultHigh),
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
            badge.centerYAnchor.constraint(equalTo: tokenLabel.centerYAnchor, constant: -0.333),
            badge.leadingAnchor.constraint(equalTo: tokenLabel.trailingAnchor, constant: 4),
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
            separatorView.heightAnchor.constraint(equalToConstant: IOS_26_MODE_ENABLED ? 1 : 0.33)
        ])

        contentView.backgroundColor = .clear

        updateTheme()
    }

    func updateTheme() {
        baseBackgroundColor = .clear
        highlightBackgroundColor = WTheme.highlight
        tokenLabel.textColor = WTheme.primaryLabel
        amountLabel.textColor = WTheme.primaryLabel
        tokenPriceLabel.textColor = WTheme.balanceHeaderView.secondary
        baseCurrencyAmountLabel.textColor = WTheme.balanceHeaderView.secondary
    }

    // MARK: - Configure using MTokenBalance
    private var prevToken: String? = nil

    public func configure(with walletToken: MTokenBalance,
                          isLast: Bool,
                          animated: Bool = true,
                          badgeContent: BadgeContent?,
                          onSelect: @escaping () -> Void
    ) {
        let tokenChanged = self.walletToken?.tokenSlug != walletToken.tokenSlug
        self.walletToken = walletToken
        self.onSelect = onSelect

        // token
        let token = TokenStore.getToken(slug: walletToken.tokenSlug)

        // configure icon view
        if tokenChanged || self.tokenImage != token?.image?.nilIfEmpty {
            self.tokenImage = token?.image?.nilIfEmpty
            iconView.config(with: token, isStaking: walletToken.isStaking, isWalletView: true, shouldShowChain: AccountStore.account?.isMultichain == true)
        }

        // label
        tokenLabel.text = (token?.name ?? " ") + (walletToken.isStaking ? " Staking" : "")

        // apy
        configureBadge(badgeContent: badgeContent)

        // price
        if let price = token?.price {
            let attr = NSMutableAttributedString(string: formatAmountText(
                amount: price,
                currency: TokenStore.baseCurrency.sign,
                decimalsCount: tokenDecimals(for: price, tokenDecimals: 9)
            ), attributes: [
                .font: regular14Font,
                .foregroundColor: WTheme.secondaryLabel
            ])
            if let percentChange24h = token?.percentChange24h, let percentChange24hRounded = token?.percentChange24hRounded {
                let color = abs(percentChange24h) < 0.005 ? WTheme.secondaryLabel : percentChange24h > 0 ? WTheme.positiveAmount : WTheme.negativeAmount
                if percentChange24hRounded != 0 {
                    attr.append(NSAttributedString(string: " \(percentChange24hRounded < 0 ? "-\(signSpace)" : "+\(signSpace)")\(abs(percentChange24hRounded))%",
                                                   attributes: [
                                                    .font: regular14Font,
                                                    .foregroundColor: color
                                                   ]))
                }
            }
            tokenPriceLabel.attributedText = attr
        } else {
            tokenPriceLabel.text = " "
        }
        // amount (we set this from staking state if it is STAKE_SLUG!)
        amountLabel.text = formatBigIntText(walletToken.balance,
                                           currency: token?.symbol ?? "",
                                           tokenDecimals: token?.decimals ?? 9,
                                           decimalsCount: 2,
                                           forceCurrencyToRight: true,
                                           roundUp: false)

        let amount = walletToken.toBaseCurrency
        if let amount {
            baseCurrencyAmountLabel.text = formatAmountText(amount: amount, currency: TokenStore.baseCurrency.sign, decimalsCount: TokenStore.baseCurrency.decimalsCount)
        } else {
            baseCurrencyAmountLabel.text = " "
        }
        
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
            case .activeStaking(let type, let apy):
                badge.configureStakingActive(yieldType: type, apy: apy)
            case .inactiveStaking(let type, let apy):
                badge.configureStakingInactive(yieldType: type, apy: apy)
            case .chain(let chain):
                badge.configureChain(chain: chain)
            }
            badge.alpha = 1
        } else {
            badge.configureHidden()
            badge.alpha = 0
        }
    }

    @objc private func itemSelected(_ gestureRecognizer: UIGestureRecognizer) {
        onSelect?()
    }
}


public class AssetsWalletTokenCell: WalletTokenCell {
    public override var isUIAssets: Bool {
        return true
    }
}
