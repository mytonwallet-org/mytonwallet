import ContextMenuKit
import Dependencies
import UIKit
import UIKitNavigation
import UIComponents
import WalletContext
import WalletCore

final class HomeCardContentView: UIView {
    private let mode: MtwCardContentView.Mode
    private let content: MtwCardContentView
    private var headerViewModel: HomeHeaderViewModel?
    private var accountContext: AccountContext?
    private var layout: HomeCardLayoutMetrics = .screen
    private var minimumFontScale: CGFloat = 1
    private var observation: ObserveToken?
    private var addressMenu: ContextMenuInteraction!
    private var balanceMenu: ContextMenuInteraction!
    private var renderState: RenderState?
    private var wasVisible = false

    private struct RenderState {
        var data: MtwCardContentData
        var collapseProgress: CGFloat
        var usesTopTabs: Bool
        var isSensitiveDataHidden: Bool
        var isScrolling: Bool
        var animatesBalance: Bool
        var opacity: Double
    }

    init(mode: MtwCardContentView.Mode) {
        self.mode = mode
        content = MtwCardContentView(mode: mode)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        addressMenu = ContextMenuInteraction(triggers: []) { [weak self] _ in
            guard let accountContext = self?.accountContext else { return nil }
            return makeAddressesMenuConfig(accountContext: accountContext)()
        }
        addressMenu.attach(to: content.accountLine.addressesButton)
        content.accountLine.addressesButton.onTap = { [weak self] in self?.openAddresses() }
        content.accountLine.saveButton.onTap = { [weak self] in self?.saveAccount() }
        balanceMenu = ContextMenuInteraction(triggers: .longPress) { [weak self] _ in
            @Dependency(\.sensitiveData.isHidden) var isHidden
            guard !isHidden, let accountId = self?.accountContext?.accountId else { return nil }
            return makeBaseCurrencyMenuConfig(accountId: accountId)()
        }
        balanceMenu.attach(to: content.balance)
        content.balance.onTap = { [weak self] in self?.toggleBalancePrivacy() }
        content.promotionButton.onTap = { [weak self] in self?.openPromotion() }
        content.seasonal.onDisable = {
            AppStorageHelper.isSeasonalThemingDisabled = true
            AppActions.showToast(message: lang("You can always enable seasonal theming again in the appearance settings."))
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(headerViewModel: HomeHeaderViewModel, accountContext: AccountContext) {
        prepareForReuse()
        self.headerViewModel = headerViewModel
        self.accountContext = accountContext
        content.change.onOpenPortfolio = { [weak accountContext] in
            guard let accountContext else { return }
            AppActions.showPortfolio(accountContext: accountContext)
        }
        observation = observe { [weak self] in self?.updateState() }
    }

    func updateLayout(_ layout: HomeCardLayoutMetrics, minimumFontScale: CGFloat) {
        self.layout = layout
        self.minimumFontScale = minimumFontScale
        render()
    }

    private func updateState() {
        guard let headerViewModel, let accountContext else { return }
        if mode == .expanded, accountContext.isCurrent, accountContext.config.cardsInfo != nil {
            AppActions.preloadUpgradeCard()
        }
        let visibleBalance = (mode == .collapsed) == headerViewModel.isCollapsed
        let animatesChanges = wasVisible && visibleBalance
        wasVisible = visibleBalance
        // Retain the outgoing face for expansion/collapse, but only prepare the face being shown.
        guard visibleBalance else { return }
        @Dependency(\.sensitiveData.isHidden) var isSensitiveDataHidden
        let data = MtwCardContentData(
            account: accountContext.account, addressLine: accountContext.addressLine,
            balance: accountContext.balance, previousBalance: accountContext.balance24h,
            balanceChange: accountContext.balanceChange, nft: accountContext.nft,
            showsWalletName: headerViewModel.rootNavigationStyle.usesNavigationBarTopTabs && headerViewModel.walletCardTopLine == .walletName,
            seasonalTheme: headerViewModel.seasonalTheme, promotion: accountContext.activePromotion
        )
        renderState = RenderState(
            data: data,
            collapseProgress: headerViewModel.collapseProgress,
            usesTopTabs: headerViewModel.rootNavigationStyle.usesNavigationBarTopTabs,
            isSensitiveDataHidden: isSensitiveDataHidden,
            isScrolling: headerViewModel.isAccountScrolling,
            animatesBalance: accountContext.isCurrent && animatesChanges && AppStorageHelper.animations && !UIAccessibility.isReduceMotionEnabled,
            opacity: mode == .expanded ? headerViewModel.cardOpacity : 1
        )
        render()
    }

    private func render() {
        guard let state = renderState else { return }
        content.configure(state.data, cardWidth: layout.itemWidth, minimumFontScale: minimumFontScale,
                          collapseProgress: state.collapseProgress, usesTopTabs: state.usesTopTabs,
                          isSensitiveDataHidden: state.isSensitiveDataHidden, isScrolling: state.isScrolling,
                          animatesBalance: state.animatesBalance)
        alpha = state.opacity
    }

    func prepareForReuse() {
        observation?.cancel()
        observation = nil
        accountContext = nil
        headerViewModel = nil
        renderState = nil
        wasVisible = false
        content.prepareForReuse()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        content.frame = bounds
    }

    @objc private func openAddresses() { addressMenu.present() }

    @objc private func saveAccount() {
        guard let accountContext else { return }
        AppActions.saveTemporaryViewAccount(accountId: accountContext.accountId)
    }

    @objc private func toggleBalancePrivacy() {
        @Dependency(\.sensitiveData.isHidden) var isHidden
        AppActions.setSensitiveDataIsHidden(!isHidden)
    }

    @objc private func openPromotion() {
        guard let promotion = accountContext?.activePromotion, let overlay = promotion.cardOverlay else { return }
        switch overlay.onClickAction {
        case .openPromotionModal: AppActions.showPromotion(promotion)
        case .openMintCardModal: AppActions.showUpgradeCard()
        }
    }
}
