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

public class WalletTokenCell: WHighlightCollectionViewCell {
    nonisolated public static let defaultHeight = 60.0

    private static let pinIconSideLength: CGFloat = 12
    private static let pinIconSpacing: CGFloat = 4
    private static let tokenImageToTextSpacing: CGFloat = 12
    private static let badgeLeadingSpacing: CGFloat = 4
    private static let badgeTrailingSpacing: CGFloat = 8
    private static let badgeFadeWidth: CGFloat = 18
    private static let badgeFadeHiddenInset: CGFloat = 1

    private let medium16Font = UIFont.systemFont(ofSize: 16, weight: .medium)
    private let regular16Font = UIFont.systemFont(ofSize: 16, weight: .regular)
    private let regular14Font = UIFont.systemFont(ofSize: 14, weight: .regular)

    private static let pinningColor: UIColor = .air.altHighlight.withAlphaComponent(0.4)
    
    public var walletToken: MTokenBalance?
    private var tokenImage: String?

    public var isUIAssets: Bool { false }
    
    public override var safeAreaInsets: UIEdgeInsets { isUIAssets ? super.safeAreaInsets : .zero }

    private let mainView: UIView = UIView()
    private let tokenNameClipView: UIView = configured(object: UIView()) {
        $0.translatesAutoresizingMaskIntoConstraints = false
        $0.clipsToBounds = true
    }
    private var tokenLabelLeadingConstraint: NSLayoutConstraint!
    private var tokenNameClipTrailingConstraint: NSLayoutConstraint!
    private var tokenNameWidthConstraint: NSLayoutConstraint!
    // left icon view
    private var iconView: IconView!
    // pin icon view
    private var pinIconView: UIView = configured(object: UIImageView()) {
        $0.translatesAutoresizingMaskIntoConstraints = false
        $0.image = UIImage(systemName: "pin.fill")
        $0.tintColor = .air.secondaryLabel
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
    private let tokenNameFadeMask = CAGradientLayer()
    private var tokenPriceLabel: UILabel!
    private var amountContainer: WSensitiveData<UILabel> = .init(cols: 12, rows: 2, cellSize: 9, cornerRadius: 5, theme: .adaptive, alignment: .trailing)
    private var amountLabel: WAmountLabel!
    private var amount2Container: WSensitiveData<UILabel> = .init(cols: 9, rows: 2, cellSize: 7, cornerRadius: 4, theme: .adaptive, alignment: .trailing)
    private var baseCurrencyAmountLabel: WAmountLabel!
    private let badge = BadgeView()
    private var badgeInlineLeadingConstraint: NSLayoutConstraint!
    private var badgeOverlayTrailingConstraint: NSLayoutConstraint!

    private enum BadgeLayoutMode {
        case inline
        case overlay
    }

    private var badgeLayoutMode: BadgeLayoutMode = .inline

    public override init(frame: CGRect) {
        super.init(frame: frame)
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
        contentView.backgroundColor = .clear
        contentView.heightAnchor.constraint(equalToConstant: Self.defaultHeight).isActive = true
        
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
        iconView.setChainSize(14, borderWidth: 1.333, borderColor: .air.background, horizontalOffset: 3, verticalOffset: 1)

        // tokenName
        mainView.addSubview(tokenNameClipView)
        tokenNameLabel.translatesAutoresizingMaskIntoConstraints = false
        tokenLabelLeadingConstraint = tokenNameClipView.leadingAnchor.constraint(equalTo: iconView.trailingAnchor,
                                                                                 constant: Self.tokenImageToTextSpacing)
        NSLayoutConstraint.activate([
            tokenLabelLeadingConstraint,
            tokenNameClipView.topAnchor.constraint(equalTo: mainView.topAnchor, constant: 1.667),
        ])
        tokenNameClipView.addSubview(tokenNameLabel)
        NSLayoutConstraint.activate([
            tokenNameLabel.leadingAnchor.constraint(equalTo: tokenNameClipView.leadingAnchor),
            tokenNameLabel.topAnchor.constraint(equalTo: tokenNameClipView.topAnchor),
            tokenNameLabel.bottomAnchor.constraint(equalTo: tokenNameClipView.bottomAnchor),
        ])
        tokenNameWidthConstraint = tokenNameLabel.widthAnchor.constraint(equalToConstant: 0)
        tokenNameWidthConstraint.isActive = true
        tokenNameLabel.font = medium16Font
        tokenNameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tokenNameLabel.lineBreakMode = .byTruncatingTail

        // pin icon
        mainView.addSubview(pinIconView)
        NSLayoutConstraint.activate([
            pinIconView.widthAnchor.constraint(equalToConstant: Self.pinIconSideLength),
            pinIconView.heightAnchor.constraint(equalToConstant: Self.pinIconSideLength),
            pinIconView.centerYAnchor.constraint(equalTo: tokenNameLabel.centerYAnchor),
            tokenNameClipView.leadingAnchor.constraint(equalTo: pinIconView.trailingAnchor, constant: Self.pinIconSpacing),
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
            tokenPriceLabel.topAnchor.constraint(equalTo: tokenNameClipView.bottomAnchor, constant: 1),
        ])
        tokenPriceLabel.font = regular14Font

        amountLabel = WAmountLabel(showNegativeSign: false)
        amountLabel.font = regular16Font
        amountLabel.translatesAutoresizingMaskIntoConstraints = false
        amountLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        amountContainer.addContent(amountLabel)
        mainView.addSubview(amountContainer)
        amountContainer.setContentCompressionResistancePriority(.required, for: .horizontal)
        tokenNameClipTrailingConstraint = tokenNameClipView.trailingAnchor.constraint(equalTo: amountLabel.leadingAnchor)
        NSLayoutConstraint.activate([
            amountLabel.trailingAnchor.constraint(equalTo: mainView.trailingAnchor),
            amountLabel.firstBaselineAnchor.constraint(equalTo: tokenNameLabel.firstBaselineAnchor),
            tokenNameClipTrailingConstraint,
        ])

        baseCurrencyAmountLabel = WAmountLabel(showNegativeSign: true)
        baseCurrencyAmountLabel.font = regular14Font
        baseCurrencyAmountLabel.translatesAutoresizingMaskIntoConstraints = false
        baseCurrencyAmountLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        amount2Container.addContent(baseCurrencyAmountLabel)
        mainView.addSubview(amount2Container)
        amount2Container.setContentCompressionResistancePriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            baseCurrencyAmountLabel.trailingAnchor.constraint(equalTo: amountLabel.trailingAnchor),
            baseCurrencyAmountLabel.firstBaselineAnchor.constraint(equalTo: tokenPriceLabel.firstBaselineAnchor),
        ])

        amountContainer.isTapToRevealEnabled = false
        amount2Container.isTapToRevealEnabled = false

        // apy
        badge.translatesAutoresizingMaskIntoConstraints = false
        mainView.addSubview(badge)
        badgeInlineLeadingConstraint = badge.leadingAnchor.constraint(equalTo: tokenNameLabel.trailingAnchor, constant: Self.badgeLeadingSpacing)
        badgeOverlayTrailingConstraint = badge.trailingAnchor.constraint(equalTo: tokenNameClipView.trailingAnchor, constant: -Self.badgeTrailingSpacing)
        NSLayoutConstraint.activate([
            badge.centerYAnchor.constraint(equalTo: tokenNameLabel.centerYAnchor, constant: -0.333),
            badgeInlineLeadingConstraint,
            badge.trailingAnchor.constraint(lessThanOrEqualTo: amountLabel.leadingAnchor, constant: -Self.badgeTrailingSpacing),
        ])
        badge.alpha = 0
        badge.setContentCompressionResistancePriority(.required, for: .horizontal)

        contentView.backgroundColor = .clear

        updateTheme()
    }

    private func updateTheme() {
        highlightBackgroundColor = .air.highlight
        backgroundColor = .clear
        tokenNameLabel.textColor = UIColor.label
        amountLabel.textColor = UIColor.label
        tokenPriceLabel.textColor = .air.secondaryLabel
        baseCurrencyAmountLabel.textColor = .air.secondaryLabel
    }

    // MARK: - Configure using MTokenBalance

    private var prevToken: String?

    public func configure(with walletToken: MTokenBalance,
                          animated: Bool = true,
                          badgeContent: BadgeContent?,
                          isPinned: Bool,
                          highlightBackgroundWhenPinned: Bool) {
        let previousTokenSlug = self.walletToken?.tokenSlug
        let previousBalance = self.walletToken?.balance
        let previousBaseCurrencyAmount = self.walletToken?.toBaseCurrency
        let tokenChanged = previousTokenSlug != walletToken.tokenSlug
        self.walletToken = walletToken
        // token
        let token = TokenStore.getToken(slug: walletToken.tokenSlug)

        // configure icon view
        if tokenChanged || tokenImage != token?.image?.nilIfEmpty {
            tokenImage = token?.image?.nilIfEmpty
            iconView.config(with: token, isStaking: walletToken.isStaking, isWalletView: true, shouldShowChain: true)
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
        tokenNameWidthConstraint.constant = ceil(tokenNameLabel.intrinsicContentSize.width)

        // apy
        configureBadge(badgeContent: badgeContent)

        // price
        if let price = token?.price {
            let baseCurrencyAmount = BaseCurrencyAmount.fromDouble(price, TokenStore.baseCurrency)
            let attr = NSMutableAttributedString(
                string: baseCurrencyAmount.formatted(.baseCurrencyEquivalent, roundHalfUp: true),
                attributes: [
                    .font: regular14Font,
                    .foregroundColor: UIColor.air.secondaryLabel,
                ]
            )
            if let percentChange24h = token?.percentChange24h, let percentChange24hRounded = token?.percentChange24hRounded {
                let color = abs(percentChange24h) < 0.005 ? UIColor.air.secondaryLabel : percentChange24h > 0 ? UIColor.air.positiveAmount : UIColor.air.negativeAmount
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
            amountText = amount.formatted(.defaultAdaptive, roundHalfUp: false)
        } else {
            amountText = nil
        }

        let amount = walletToken.toBaseCurrency
        let baseCurrencyText: String?
        if let amount {
            let baseCurrencyAmount = BaseCurrencyAmount.fromDouble(amount, TokenStore.baseCurrency)
            baseCurrencyText = baseCurrencyAmount.formatted(.baseCurrencyEquivalent, roundHalfUp: true)
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
        mainView.layoutIfNeeded()
        if updateBadgeLayoutModeIfNeeded() {
            mainView.layoutIfNeeded()
        }
        updateTokenNameFadeMask()
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
        applyBadgeLayoutMode(.inline)
        setNeedsLayout()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        if updateBadgeLayoutModeIfNeeded() {
            mainView.layoutIfNeeded()
        }
        updateTokenNameFadeMask()
    }

    @discardableResult
    private func updateBadgeLayoutModeIfNeeded() -> Bool {
        guard badge.alpha > 0, !badge.isHidden else {
            return applyBadgeLayoutMode(.inline)
        }

        badge.layoutIfNeeded()

        let badgeWidth = ceil(badge.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).width)
        let amountLeading = amountLabel.frame.minX > 0
            ? amountLabel.frame.minX
            : mainView.bounds.width - ceil(amountLabel.intrinsicContentSize.width)
        let inlineTitleWidth = amountLeading - tokenNameClipView.frame.minX - badgeWidth - Self.badgeLeadingSpacing - Self.badgeTrailingSpacing
        guard inlineTitleWidth > 0 else { return applyBadgeLayoutMode(.overlay) }

        let titleRequiredWidth = ceil(tokenNameLabel.intrinsicContentSize.width)
        let nextMode: BadgeLayoutMode = titleRequiredWidth > inlineTitleWidth ? .overlay : .inline

        return applyBadgeLayoutMode(nextMode)
    }

    private func updateTokenNameFadeMask() {
        guard badgeLayoutMode == .overlay, badge.alpha > 0, !badge.isHidden else {
            tokenNameClipView.layer.mask = nil
            return
        }

        let overlapStartX = badge.frame.minX - tokenNameClipView.frame.minX
        let clipWidth = tokenNameClipView.bounds.width
        guard clipWidth > 0, overlapStartX < clipWidth else {
            tokenNameClipView.layer.mask = nil
            return
        }

        let fadeEndX = max(0, overlapStartX - Self.badgeFadeHiddenInset)
        let fadeStartX = max(0, fadeEndX - Self.badgeFadeWidth)
        let fadeStartLocation = max(0, min(1, fadeStartX / clipWidth))
        let fadeEndLocation = max(0, min(1, fadeEndX / clipWidth))

        tokenNameFadeMask.frame = tokenNameClipView.bounds
        tokenNameFadeMask.startPoint = CGPoint(x: 0, y: 0.5)
        tokenNameFadeMask.endPoint = CGPoint(x: 1, y: 0.5)
        tokenNameFadeMask.colors = [
            UIColor.black.cgColor,
            UIColor.black.cgColor,
            UIColor.clear.cgColor,
            UIColor.clear.cgColor,
        ]
        tokenNameFadeMask.locations = [
            0,
            NSNumber(value: fadeStartLocation),
            NSNumber(value: fadeEndLocation),
            1,
        ]
        tokenNameClipView.layer.mask = tokenNameFadeMask
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

    @discardableResult
    private func applyBadgeLayoutMode(_ nextMode: BadgeLayoutMode) -> Bool {
        guard nextMode != badgeLayoutMode else {
            tokenNameClipView.layer.mask = nextMode == .overlay ? tokenNameFadeMask : nil
            return false
        }

        badgeLayoutMode = nextMode
        badgeInlineLeadingConstraint.isActive = nextMode == .inline
        badgeOverlayTrailingConstraint.isActive = nextMode == .overlay
        tokenNameClipView.layer.mask = nextMode == .overlay ? tokenNameFadeMask : nil
        return true
    }

}

public class AssetsWalletTokenCell: WalletTokenCell {
    public override var isUIAssets: Bool {
        return true
    }
}
