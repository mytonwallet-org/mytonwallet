//
//  WalletTokenCell.swift
//  UIHome
//
//  Created by Sina on 3/26/24.
//

import ContextMenuKit
import UIComponents
import UIKit
import WalletContext
import WalletCore

public class WalletTokenCell: WHighlightCollectionViewCell {
    nonisolated public static let defaultHeight = 60.0

    private static let pinIconSideLength: CGFloat = 12
    private static let pinIconSpacing: CGFloat = 4
    private static let tokenImageToTextSpacing: CGFloat = 10
    private static let badgeLeadingSpacing: CGFloat = 4
    private static let badgeTrailingSpacing: CGFloat = 8
    private static let badgeFadeWidth: CGFloat = 18
    private static let badgeFadeHiddenInset: CGFloat = 1

    public var walletToken: MTokenBalance?
    
    private var isMultichain = false
    private var contextMenuInteraction: ContextMenuInteraction?

    public var isUIAssets: Bool { false }
    
    public override var safeAreaInsets: UIEdgeInsets { isUIAssets ? super.safeAreaInsets : .zero }

    private let mainView = UIView()
    private let tokenNameClipView: UIView = configured(object: UIView()) {
        $0.translatesAutoresizingMaskIntoConstraints = false
        $0.clipsToBounds = true
    }
    private var tokenLabelLeadingConstraint: NSLayoutConstraint!
    private var tokenNameClipTrailingConstraint: NSLayoutConstraint!
    private var tokenNameWidthConstraint: NSLayoutConstraint!
    private var iconView: IconView!
    private var pinIconView: UIView = configured(object: UIImageView()) {
        $0.translatesAutoresizingMaskIntoConstraints = false
        $0.image = UIImage(systemName: "pin.fill")
        $0.tintColor = .air.secondaryLabel
        $0.contentMode = .scaleAspectFit
    }

    // address label to show short presentation of the address
    private let tokenNameLabel: UILabel = UILabel()
    private let tokenNameFadeMask = CAGradientLayer()
    private var tokenPriceLabel: UILabel!
    private var amountContainer: WSensitiveData<UILabel> = .init(cols: 12, rows: 2, cellSize: 9, cornerRadius: 5, theme: .adaptive, alignment: .trailing)
    private var amountLabel: WAmountLabel!
    private var amountWidthConstraint: NSLayoutConstraint!
    private var amount2Container: WSensitiveData<UILabel> = .init(cols: 9, rows: 2, cellSize: 7, cornerRadius: 4, theme: .adaptive, alignment: .trailing)
    private var baseCurrencyAmountLabel: WAmountLabel!
    private var baseCurrencyAmountWidthConstraint: NSLayoutConstraint!
    private let badge = BadgeView()
    private var badgeInlineLTRConstraint: NSLayoutConstraint!
    private var badgeInlineRTLConstraint: NSLayoutConstraint!
    private var badgeOverlayLTRConstraint: NSLayoutConstraint!
    private var badgeOverlayRTLConstraint: NSLayoutConstraint!
    private var badgeAmountBoundaryLTRConstraint: NSLayoutConstraint!
    private var badgeAmountBoundaryRTLConstraint: NSLayoutConstraint!

    private enum BadgeLayoutMode {
        case inline
        case overlay
    }

    private var badgeLayoutMode: BadgeLayoutMode = .inline
    private var badgeLayoutDirection: UIUserInterfaceLayoutDirection?

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    @available(*, unavailable)
    public required init?(coder _: NSCoder) { nil }
    
    public override func prepareForReuse() {
        super.prepareForReuse()
        setContextMenuInteraction(nil)
        amountContainer.resetReveal()
        amount2Container.resetReveal()
    }

    func setContextMenuInteraction(_ interaction: ContextMenuInteraction?) {
        contextMenuInteraction?.detach()
        contextMenuInteraction = interaction
        interaction?.attach(to: self)
    }
    
    private func setupViews() {
        isExclusiveTouch = true
        contentView.backgroundColor = .clear
        let heightConstraint = contentView.heightAnchor.constraint(equalToConstant: Self.defaultHeight)
        heightConstraint.priority = .defaultHigh
        heightConstraint.isActive = true
        
        mainView.backgroundColor = .clear
        contentView.addStretchedToBounds(subview: mainView, insets: UIEdgeInsets(top: 10, left: 12, bottom: 10, right: 12))
        
        // left icon
        iconView = IconView(size: 40, accessoryGeometry: .forIcon40)
        mainView.addSubview(iconView)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: mainView.leadingAnchor),
            iconView.centerYAnchor.constraint(equalTo: mainView.centerYAnchor),
        ])

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
        tokenNameLabel.applyTextStyle(.calloutEmphasized)
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

        // price
        tokenPriceLabel = UILabel()
        tokenPriceLabel.translatesAutoresizingMaskIntoConstraints = false
        mainView.addSubview(tokenPriceLabel)
        NSLayoutConstraint.activate([
            tokenPriceLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: Self.tokenImageToTextSpacing),
            tokenPriceLabel.topAnchor.constraint(equalTo: tokenNameClipView.bottomAnchor, constant: 1),
        ])
        tokenPriceLabel.applyTextStyle(.supporting, content: .technical)

        amountLabel = WAmountLabel(showNegativeSign: false)
        amountLabel.applyTextStyle(.callout, content: .technical)
        amountLabel.translatesAutoresizingMaskIntoConstraints = false
        amountLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        amountContainer.addContent(amountLabel)
        mainView.addSubview(amountContainer)
        amountContainer.setContentCompressionResistancePriority(.required, for: .horizontal)
        amountWidthConstraint = amountLabel.widthAnchor.constraint(equalToConstant: 0)
        tokenNameClipTrailingConstraint = tokenNameClipView.trailingAnchor.constraint(equalTo: amountLabel.leadingAnchor)
        NSLayoutConstraint.activate([
            amountWidthConstraint,
            amountLabel.trailingAnchor.constraint(equalTo: mainView.trailingAnchor),
            amountLabel.firstBaselineAnchor.constraint(equalTo: tokenNameLabel.firstBaselineAnchor),
            tokenNameClipTrailingConstraint,
        ])

        baseCurrencyAmountLabel = WAmountLabel(showNegativeSign: true)
        baseCurrencyAmountLabel.applyTextStyle(.supporting, content: .technical)
        baseCurrencyAmountLabel.translatesAutoresizingMaskIntoConstraints = false
        baseCurrencyAmountLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        amount2Container.addContent(baseCurrencyAmountLabel)
        mainView.addSubview(amount2Container)
        amount2Container.setContentCompressionResistancePriority(.required, for: .horizontal)
        baseCurrencyAmountWidthConstraint = baseCurrencyAmountLabel.widthAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            baseCurrencyAmountWidthConstraint,
            baseCurrencyAmountLabel.trailingAnchor.constraint(equalTo: amountLabel.trailingAnchor),
            baseCurrencyAmountLabel.firstBaselineAnchor.constraint(equalTo: tokenPriceLabel.firstBaselineAnchor),
        ])

        amountContainer.isTapToRevealEnabled = false
        amount2Container.isTapToRevealEnabled = false

        // apy
        badge.translatesAutoresizingMaskIntoConstraints = false
        mainView.addSubview(badge)
        badgeInlineLTRConstraint = badge.leftAnchor.constraint(equalTo: tokenNameLabel.rightAnchor, constant: Self.badgeLeadingSpacing)
        badgeInlineRTLConstraint = badge.rightAnchor.constraint(equalTo: tokenNameLabel.leftAnchor, constant: -Self.badgeLeadingSpacing)
        badgeOverlayLTRConstraint = badge.rightAnchor.constraint(equalTo: tokenNameClipView.rightAnchor, constant: -Self.badgeTrailingSpacing)
        badgeOverlayRTLConstraint = badge.leftAnchor.constraint(equalTo: tokenNameClipView.leftAnchor, constant: Self.badgeTrailingSpacing)
        badgeAmountBoundaryLTRConstraint = badge.rightAnchor.constraint(lessThanOrEqualTo: amountLabel.leftAnchor, constant: -Self.badgeTrailingSpacing)
        badgeAmountBoundaryRTLConstraint = badge.leftAnchor.constraint(greaterThanOrEqualTo: amountLabel.rightAnchor, constant: Self.badgeTrailingSpacing)
        NSLayoutConstraint.activate([
            badge.centerYAnchor.constraint(equalTo: tokenNameLabel.centerYAnchor, constant: -0.333),
        ])
        applyBadgeLayoutMode(.inline)
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
                          stakingAccessoryContent: StakingAccessoryContent?,
                          isMultichain: Bool,
                          isPinned: Bool) {
        let previousTokenSlug = self.walletToken?.tokenSlug
        let previousBalance = self.walletToken?.balance
        let previousBaseCurrencyAmount = self.walletToken?.toBaseCurrency
        let tokenChanged = previousTokenSlug != walletToken.tokenSlug
        self.walletToken = walletToken
        self.isMultichain = isMultichain
        // token
        let token = TokenStore.getToken(slug: walletToken.tokenSlug)

        // configure icon view
        configureIcon(token: token, accessoryContent: stakingAccessoryContent)
        
        // pin icon
        pinIconView.isHidden = !isPinned
        tokenLabelLeadingConstraint.constant =
            isPinned ? Self.tokenImageToTextSpacing + Self.pinIconSideLength + Self.pinIconSpacing : Self.tokenImageToTextSpacing

        contentView.backgroundColor = .clear
        
        // label
        tokenNameLabel.text = if let token {
            MTokenBalance.displayName(
                apiToken: token,
                isStaking: walletToken.isStaking,
                strippingLabelWhenShown: badgeContent?.isTokenLabel == true
            )
        } else {
            walletToken.tokenSlug
        }
        tokenNameWidthConstraint.constant = ceil(tokenNameLabel.intrinsicContentSize.width)

        // apy
        configureBadge(badgeContent: badgeContent)

        // price
        if let price = token?.price {
            let baseCurrencyAmount = BaseCurrencyAmount.fromDouble(price, TokenStore.baseCurrency)
            let priceText = baseCurrencyAmount.formatted(.baseCurrencyEquivalent, roundHalfUp: true)
            var percentChangeText: String?
            var percentChangeColor: UIColor?
            if let percentChange24h = token?.percentChange24h, let percentChange24hRounded = token?.percentChange24hRounded {
                let color = abs(percentChange24h) < 0.005 ? UIColor.air.secondaryLabel : percentChange24h > 0 ? UIColor.air.positiveAmount : UIColor.air.negativeAmount
                if percentChange24hRounded != 0,
                   WalletTokenPercentChangeThresholdExperiment.shouldShow(
                       percentChange: percentChange24h
                   ) {
                    percentChangeText = formatPercent(percentChange24hRounded / 100)
                    percentChangeColor = color
                }
            }
            tokenPriceLabel.attributedText = makePriceAttributedText(
                priceText: priceText,
                percentChangeText: percentChangeText,
                percentChangeColor: percentChangeColor
            )
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
        updateAmountWidthConstraints()

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

    public func configureStakingPresentation(
        badgeContent: BadgeContent?,
        accessoryContent: StakingAccessoryContent?
    ) {
        configureBadge(badgeContent: badgeContent)
        guard let walletToken else { return }
        configureIcon(
            token: TokenStore.getToken(slug: walletToken.tokenSlug),
            accessoryContent: accessoryContent
        )
    }

    private func configureIcon(token: ApiToken?, accessoryContent: StakingAccessoryContent?) {
        guard let walletToken else { return }
        iconView.config(
            with: token,
            isStaking: walletToken.isStaking,
            isWalletView: true,
            stakingAccessory: accessoryContent,
            shouldShowChain: isMultichain
        )
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
            case .tokenLabel(let text, let style):
                badge.configureTokenLabel(text: text, style: style)
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
        let inlineTitleWidth: CGFloat
        if effectiveUserInterfaceLayoutDirection == .rightToLeft {
            let amountTrailing = amountLabel.frame.maxX > 0
                ? amountLabel.frame.maxX
                : ceil(amountLabel.intrinsicContentSize.width)
            inlineTitleWidth = tokenNameClipView.frame.maxX
                - amountTrailing
                - badgeWidth
                - Self.badgeLeadingSpacing
                - Self.badgeTrailingSpacing
        } else {
            let amountLeading = amountLabel.frame.minX > 0
                ? amountLabel.frame.minX
                : mainView.bounds.width - ceil(amountLabel.intrinsicContentSize.width)
            inlineTitleWidth = amountLeading
                - tokenNameClipView.frame.minX
                - badgeWidth
                - Self.badgeLeadingSpacing
                - Self.badgeTrailingSpacing
        }
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

        let clipWidth = tokenNameClipView.bounds.width
        guard clipWidth > 0 else {
            tokenNameClipView.layer.mask = nil
            return
        }

        let overlapStartX = badge.frame.minX - tokenNameClipView.frame.minX
        let overlapEndX = badge.frame.maxX - tokenNameClipView.frame.minX
        let fadeStartX: CGFloat
        let fadeEndX: CGFloat
        let colors: [CGColor]
        if effectiveUserInterfaceLayoutDirection == .rightToLeft {
            guard overlapEndX > 0 else {
                tokenNameClipView.layer.mask = nil
                return
            }
            fadeStartX = min(clipWidth, overlapEndX + Self.badgeFadeHiddenInset)
            fadeEndX = min(clipWidth, fadeStartX + Self.badgeFadeWidth)
            colors = [
                UIColor.clear.cgColor,
                UIColor.clear.cgColor,
                UIColor.black.cgColor,
                UIColor.black.cgColor,
            ]
        } else {
            guard overlapStartX < clipWidth else {
                tokenNameClipView.layer.mask = nil
                return
            }
            fadeEndX = max(0, overlapStartX - Self.badgeFadeHiddenInset)
            fadeStartX = max(0, fadeEndX - Self.badgeFadeWidth)
            colors = [
                UIColor.black.cgColor,
                UIColor.black.cgColor,
                UIColor.clear.cgColor,
                UIColor.clear.cgColor,
            ]
        }
        let fadeStartLocation = max(0, min(1, fadeStartX / clipWidth))
        let fadeEndLocation = max(0, min(1, fadeEndX / clipWidth))

        tokenNameFadeMask.frame = tokenNameClipView.bounds
        tokenNameFadeMask.startPoint = CGPoint(x: 0, y: 0.5)
        tokenNameFadeMask.endPoint = CGPoint(x: 1, y: 0.5)
        tokenNameFadeMask.colors = colors
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

    private func updateAmountWidthConstraints() {
        amountWidthConstraint.constant = ceil(amountLabel.intrinsicContentSize.width)
        baseCurrencyAmountWidthConstraint.constant = ceil(baseCurrencyAmountLabel.intrinsicContentSize.width)
    }

    private func makePriceAttributedText(
        priceText: String,
        percentChangeText: String?,
        percentChangeColor: UIColor?
    ) -> NSAttributedString {
        let font = WTypography.uiFont(.supporting, content: .technical)
        let priceAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.air.secondaryLabel,
        ]
        guard let percentChangeText, let percentChangeColor else {
            return NSAttributedString(string: priceText, attributes: priceAttributes)
        }

        let changeAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: percentChangeColor,
        ]
        guard effectiveUserInterfaceLayoutDirection == .rightToLeft else {
            let attr = NSMutableAttributedString(string: priceText, attributes: priceAttributes)
            attr.append(NSAttributedString(string: " \(percentChangeText)", attributes: changeAttributes))
            return attr
        }

        let attr = NSMutableAttributedString(string: percentChangeText.leftToRightMarked, attributes: changeAttributes)
        attr.append(NSAttributedString(string: " · ", attributes: priceAttributes))
        attr.append(NSAttributedString(string: priceText.leftToRightMarked, attributes: priceAttributes))
        return attr
    }

    @discardableResult
    private func applyBadgeLayoutMode(_ nextMode: BadgeLayoutMode) -> Bool {
        let direction = effectiveUserInterfaceLayoutDirection
        let didChange = nextMode != badgeLayoutMode || direction != badgeLayoutDirection

        badgeLayoutMode = nextMode
        badgeLayoutDirection = direction
        badgeInlineLTRConstraint.isActive = nextMode == .inline && direction == .leftToRight
        badgeInlineRTLConstraint.isActive = nextMode == .inline && direction == .rightToLeft
        badgeOverlayLTRConstraint.isActive = nextMode == .overlay && direction == .leftToRight
        badgeOverlayRTLConstraint.isActive = nextMode == .overlay && direction == .rightToLeft
        badgeAmountBoundaryLTRConstraint.isActive = direction == .leftToRight
        badgeAmountBoundaryRTLConstraint.isActive = direction == .rightToLeft
        tokenNameClipView.layer.mask = nextMode == .overlay ? tokenNameFadeMask : nil
        return didChange
    }

}

private extension String {
    var leftToRightMarked: String {
        "\u{200E}\(self)\u{200E}"
    }
}

public class AssetsWalletTokenCell: WalletTokenCell {
    public override var isUIAssets: Bool {
        return true
    }
}
