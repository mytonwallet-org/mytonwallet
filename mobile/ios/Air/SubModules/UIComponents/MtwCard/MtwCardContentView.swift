import UIKit
import WalletContext
import WalletCore

public struct MtwCardContentData {
    public var account: MAccount
    public var addressLine: MAccount.AddressLine
    public var balance: BaseCurrencyAmount?
    public var previousBalance: BaseCurrencyAmount?
    public var balanceChange: Double?
    public var nft: ApiNft?
    public var showsWalletName: Bool
    public var seasonalTheme: ApiUpdate.UpdateConfig.SeasonalTheme?
    public var promotion: ApiPromotion?

    public init(account: MAccount, addressLine: MAccount.AddressLine, balance: BaseCurrencyAmount?,
                previousBalance: BaseCurrencyAmount?, balanceChange: Double?, nft: ApiNft?,
                showsWalletName: Bool = false, seasonalTheme: ApiUpdate.UpdateConfig.SeasonalTheme? = nil,
                promotion: ApiPromotion? = nil) {
        self.account = account
        self.addressLine = addressLine
        self.balance = balance
        self.previousBalance = previousBalance
        self.balanceChange = balanceChange
        self.nft = nft
        self.showsWalletName = showsWalletName
        self.seasonalTheme = seasonalTheme
        self.promotion = promotion
    }
}

public final class MtwCardContentView: UIView {
    public enum Mode { case expanded, collapsed }
    public let balance = MtwCardBalanceLabelView()
    public let change = MtwCardChangeView()
    public let accountLine = MtwCardAccountLineView()
    public let promotionButton = MtwCardTapView()
    public let seasonal = MtwCardSeasonalView()
    private static let mintActionSize: CGFloat = 50
    private static let mintImage = UIImage(
        systemName: "wand.and.sparkles.inverse",
        withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .black)
    )
    private let mintIcon = UIImageView()
    private let title = MtwCardCollapsedTitleView()
    private let centerContent = UIView()
    private let mode: Mode
    private var data: MtwCardContentData?
    private var progress: CGFloat = 0
    private var topTabs = false
    private var minimumFontScale: CGFloat = 1

    private var showsMintAction: Bool {
        data?.promotion?.kind == .cardOverlay && data?.promotion?.cardOverlay?.onClickAction == .openMintCardModal
    }

    public init(mode: Mode) {
        self.mode = mode
        super.init(frame: .zero)
        addSubview(centerContent)
        centerContent.addSubview(balance)
        centerContent.addSubview(change)
        addSubview(accountLine)
        addSubview(title)
        addSubview(seasonal)
        addSubview(promotionButton)
        mintIcon.contentMode = .center
        mintIcon.isHidden = true
        mintIcon.accessibilityElementsHidden = true
        promotionButton.addSubview(mintIcon)
        accountLine.isHidden = mode == .collapsed
        seasonal.isHidden = mode == .collapsed
        promotionButton.isHidden = true
        title.isHidden = mode == .expanded
    }

    public override var semanticContentAttribute: UISemanticContentAttribute {
        didSet {
            for view in [balance, change, accountLine, title, seasonal] {
                view.semanticContentAttribute = semanticContentAttribute
                view.setNeedsLayout()
            }
        }
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public func configure(_ data: MtwCardContentData, cardWidth: CGFloat, minimumFontScale: CGFloat = 1,
                          collapseProgress: CGFloat = 0, usesTopTabs: Bool = false,
                          isSensitiveDataHidden: Bool = false, isScrolling: Bool = false,
                          animatesBalance: Bool = true) {
        self.data = data
        progress = collapseProgress
        topTabs = usesTopTabs
        self.minimumFontScale = minimumFontScale
        let style: MtwCardBalanceView.Style = mode == .expanded
            ? .homeCard(cardWidth: cardWidth, minimumScale: minimumFontScale)
            : (usesTopTabs ? .homeNavigationBarCollapsed : .homeCollaped)
        balance.configure(balance: data.balance, style: style, nft: data.nft, usesCardGradient: mode == .expanded,
                          isHidden: isSensitiveDataHidden, isScrolling: isScrolling, animates: animatesBalance)
        change.configure(balance: data.balance, previous: data.previousBalance, percent: data.balanceChange, nft: data.nft,
                         style: mode == .expanded ? .card : .plainBackground, isHidden: isSensitiveDataHidden,
                         animates: animatesBalance && !isScrolling)
        change.isHidden = mode == .collapsed && !usesTopTabs
        if mode == .expanded {
            accountLine.configure(address: data.addressLine, name: data.account.displayName, showsName: data.showsWalletName,
                                  isTemporary: data.account.isTemporary == true, nft: data.nft)
            seasonal.configure(theme: data.seasonalTheme)
            promotionButton.isHidden = data.promotion?.kind != .cardOverlay
            promotionButton.accessibilityLabel = promotionAccessibilityLabel(data.promotion)
            promotionButton.accessibilityIdentifier = showsMintAction ? "MintCardsButton" : nil
            promotionButton.tintColor = UIColor(getSecondaryForegroundColor(nft: data.nft))
            mintIcon.isHidden = !showsMintAction
            if showsMintAction { mintIcon.image = Self.mintImage }
            mintIcon.alpha = data.nft?.metadata?.mtwCardType?.isPremium == true ? 1 : 0.75
        } else {
            title.configure(name: data.account.displayName, isView: data.account.isView)
            title.isHidden = usesTopTabs
        }
        setNeedsLayout()
    }

    public func prepareForReuse() {
        balance.prepareForReuse()
        change.prepareForReuse()
        accountLine.prepareForReuse()
        seasonal.prepareForReuse()
        promotionButton.isHidden = true
        promotionButton.accessibilityLabel = nil
        promotionButton.accessibilityIdentifier = nil
        mintIcon.isHidden = true
        data = nil
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        guard let data else { return }
        let displayScale = max(traitCollection.displayScale, 1)
        let height = (balance.lineHeight * displayScale).rounded() / displayScale
        let layoutHeight = ceil(balance.lineHeight * displayScale) / displayScale
        if mode == .expanded {
            // SwiftUI's reveal mask imposed a 224 pt minimum balance width, plus
            // the 65 pt balance insets. Preserve that layout in narrow sidebars.
            let contentWidth = max(bounds.width, data.balance == nil ? 0 : 289)
            let contentX = (bounds.width - contentWidth) / 2
            let scale = interpolate(from: 1, to: 17.0 / 40, progress: progress)
            let bottom = interpolate(from: 0, to: -16 + (IOS_26_MODE_ENABLED ? -3 : -14), progress: progress)
            centerContent.bounds = CGRect(x: 0, y: 0, width: contentWidth, height: layoutHeight + 5 + 26)
            centerContent.center = CGPoint(x: bounds.midX, y: bounds.midY - bottom - 5 * scale)
            centerContent.transform = CGAffineTransform(scaleX: scale, y: scale)
            let balanceWidth = max(0, contentWidth - 65)
            let leading: CGFloat = effectiveUserInterfaceLayoutDirection == .rightToLeft ? -0.5 : 0.5
            let balanceX = ceil((bounds.midX + leading - balanceWidth / 2) * displayScale) / displayScale
            balance.frame = CGRect(x: balanceX - contentX, y: 0, width: balanceWidth, height: height)
            change.frame = CGRect(x: 0, y: height + 5, width: contentWidth, height: 26)
            let rawLineHeight = data.showsWalletName ? WTypography.uiFont(.bodyStrong).lineHeight : UIFont(name: "SFCompactDisplay-Medium", size: 17)!.lineHeight
            let lineHeight = (rawLineHeight * displayScale).rounded() / displayScale
            let padding: CGFloat = data.showsWalletName ? 20 : 16
            let bottomPadding: CGFloat = data.showsWalletName ? 6 : 9
            let accountLineWidth = max(0, showsMintAction ? bounds.width - 2 * Self.mintActionSize : contentWidth - 80)
            accountLine.frame = CGRect(x: (bounds.width - accountLineWidth) / 2, y: bounds.height - bottomPadding - lineHeight - padding,
                                       width: accountLineWidth, height: lineHeight + padding)
            seasonal.frame = CGRect(x: contentX, y: 0, width: contentWidth, height: contentWidth * 72 / 378)
            if showsMintAction {
                let size = Self.mintActionSize
                promotionButton.frame = CGRect(x: bounds.width - size, y: bounds.height - size, width: size, height: size)
                mintIcon.frame = promotionButton.bounds
            } else {
                let mascot = data.promotion?.cardOverlay?.mascotIcon
                let size = mascot.map { CGSize(width: $0.width * 1.072, height: $0.height * 1.075) } ?? CGSize(width: 64, height: 64)
                promotionButton.frame = CGRect(x: bounds.width - size.width + (mascot?.right ?? 0), y: -(mascot?.top ?? 0), width: size.width, height: size.height)
            }
        } else {
            centerContent.frame = bounds
            let subtitleHeight: CGFloat = topTabs ? 26 : WTypography.uiFont(.body).lineHeight
            let spacing = topTabs ? 6 : interpolate(from: 5, to: -2, progress: progress)
            let padding = topTabs ? 24 : interpolate(from: 12, to: 16 + (IOS_26_MODE_ENABLED ? -3 : -14), progress: progress)
            let subtitleY = bounds.height - padding - subtitleHeight
            let scale = topTabs ? 1 : interpolate(from: 1, to: 17.0 / 40, progress: progress)
            let minimumWidth: CGFloat = (topTabs ? 15 : 14) * 14
            balance.bounds = CGRect(x: 0, y: 0, width: max(minimumWidth, bounds.width - 160), height: height)
            balance.center = CGPoint(x: bounds.midX, y: subtitleY - spacing - height / 2 + (1 - scale) * height / 2)
            balance.transform = CGAffineTransform(scaleX: scale, y: scale)
            change.frame = CGRect(x: 80, y: subtitleY, width: max(0, bounds.width - 160), height: 26)
            let subtitleScale = interpolate(from: 1, to: 13.0 / 17, progress: progress)
            title.bounds = CGRect(x: 0, y: 0, width: max(0, bounds.width - 160), height: subtitleHeight)
            title.center = CGPoint(x: bounds.midX, y: subtitleY + subtitleHeight * subtitleScale / 2)
            title.transform = CGAffineTransform(scaleX: subtitleScale, y: subtitleScale)
        }
    }

    private func promotionAccessibilityLabel(_ promotion: ApiPromotion?) -> String {
        guard let promotion, let overlay = promotion.cardOverlay else { return lang("More") }
        switch overlay.onClickAction {
        case .openPromotionModal: return promotion.modal?.title.nilIfEmpty ?? promotion.modal?.actionButton?.title.nilIfEmpty ?? lang("More")
        case .openMintCardModal: return lang("Mint Cards")
        }
    }
}
