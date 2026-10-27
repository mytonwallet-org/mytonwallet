import ContextMenuKit
import Dependencies
import UIKit
import UIKitNavigation
import UIComponents
import WalletContext
import WalletCore

final class HomeCardContentView: UIView {
    @Dependency(\.sensitiveData) private var sensitiveData
    private let mode: MtwCardContentView.Mode
    private let content: MtwCardContentView
    private var headerViewModel: HomeHeaderViewModel?
    private var accountContext: AccountContext?
    private var layout: HomeCardLayoutMetrics = .screen
    private var minimumFontScale: CGFloat = 1
    private var observation: ObserveToken?
    private var collapseProgress: CGFloat = 0
    private(set) var contentConfigurationCount = 0
    private var addressObservation: ObserveToken?
    private var addressLine: MAccount.AddressLine?
    private var addressMenu: ContextMenuInteraction!
    private var balanceMenu: ContextMenuInteraction!
    private var renderState: RenderState?
    private var wasVisible = false
    private var motionLight = CardSurfaceLight()
    private var motionPreset: CardMotionPreset?

    private struct RenderState {
        var data: MtwCardContentData
        var usesTopTabs: Bool
        var isSensitiveDataHidden: Bool
        var isScrolling: Bool
        var animatesBalance: Bool
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
        content.balance.onTap = { [weak self] in self?.toggleBalancePrivacy() }
        content.promotionButton.onTap = { [weak self] in self?.openPromotion() }
        content.mintButton.onTap = { [weak self] in
            guard let accountContext = self?.accountContext else { return }
            AppActions.showMintCard(accountContext: accountContext)
        }
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
        addressObservation = observe { [weak self] in
            guard let self, let accountContext = self.accountContext else { return }
            let address = accountContext.topAddressLine
            guard addressLine != address else { return }
            addressLine = address
            if renderState != nil {
                renderState?.data.addressLine = address
                render()
            }
        }
        observation = observe { [weak self] in self?.updateState() }
    }

    func updateLayout(_ layout: HomeCardLayoutMetrics, minimumFontScale: CGFloat) {
        self.layout = layout
        self.minimumFontScale = minimumFontScale
        content.updateLayout(cardWidth: layout.itemWidth, minimumFontScale: minimumFontScale,
                             usesTopTabs: headerViewModel?.rootNavigationStyle.usesNavigationBarTopTabs == true)
        render()
    }

    var balanceAlignmentFrame: CGRect {
        layoutIfNeeded()
        // Cells can be configured before the collection view assigns their bounds.
        content.frame = CGRect(x: 0, y: 0, width: layout.itemWidth, height: layout.itemHeight)
        let frame = content.balanceAlignmentFrame(for: accountContext?.balance ?? content.balance.displayedBalance,
                                                   isSensitiveDataHidden: sensitiveData.isHidden)
        return content.convert(frame, to: self)
    }

    private func updateState() {
        guard let headerViewModel, let accountContext else { return }
        let visibleBalance = (mode == .collapsed) == headerViewModel.isCollapsed
        let animatesChanges = wasVisible && visibleBalance
        wasVisible = visibleBalance
        content.balance.setPrivacyAnimationActive(visibleBalance && accountContext.isCurrent && headerViewModel.isVisible)
        content.change.setPrivacyAnimationActive(visibleBalance && accountContext.isCurrent && headerViewModel.isVisible)
        // Retain the outgoing face for expansion/collapse, but only prepare the face being shown.
        guard visibleBalance else { return }
        let isSensitiveDataHidden = sensitiveData.isHidden
        updateBalanceMenu(isHidden: isSensitiveDataHidden)
        let data = MtwCardContentData(
            account: accountContext.account, addressLine: addressLine ?? accountContext.topAddressLine,
            balance: accountContext.balance, previousBalance: accountContext.balance24h,
            balanceChange: accountContext.balanceChange, nft: accountContext.nft,
            showsWalletName: headerViewModel.rootNavigationStyle.usesNavigationBarTopTabs && headerViewModel.walletCardTopLine == .walletName,
            seasonalTheme: headerViewModel.seasonalTheme, promotion: accountContext.activePromotion,
            hasCardsInfo: accountContext.config.cardsInfo != nil,
            isCardMinting: ActivityStore.isCardMinting(accountId: accountContext.accountId),
            isNftBuyingDisabled: headerViewModel.isNftBuyingDisabled
        )
        if mode == .expanded, accountContext.isCurrent, data.showsMintAction {
            AppActions.preloadUpgradeCard()
        }
        renderState = RenderState(
            data: data,
            usesTopTabs: headerViewModel.rootNavigationStyle.usesNavigationBarTopTabs,
            isSensitiveDataHidden: isSensitiveDataHidden,
            isScrolling: headerViewModel.isAccountScrolling,
            animatesBalance: accountContext.isCurrent && animatesChanges && AppStorageHelper.animations && !UIAccessibility.isReduceMotionEnabled
        )
        render()
    }

    func updateCollapseProgress(_ progress: CGFloat) {
        collapseProgress = progress
        content.updateCollapseProgress(collapseProgress)
    }

    func updateBalanceMenu(isHidden: Bool) {
        // A hidden amount has no currency menu: its hold belongs to card play.
        if isHidden { balanceMenu.detach() }
        else { balanceMenu.attach(to: content.balance) }
    }

    private func render() {
        guard let state = renderState else { return }
        contentConfigurationCount += 1
        content.configure(state.data, cardWidth: layout.itemWidth, minimumFontScale: minimumFontScale,
                          collapseProgress: collapseProgress, usesTopTabs: state.usesTopTabs,
                          isSensitiveDataHidden: state.isSensitiveDataHidden, isScrolling: state.isScrolling,
                          animatesBalance: state.animatesBalance)
        applyMotionLight()
    }

    func setMotionPreset(_ preset: CardMotionPreset?) {
        guard motionPreset != preset else { return }
        motionPreset = preset
        applyMotionLight()
    }

    func setParticleInteractionPoint(_ point: CGPoint?, from view: UIView) {
        guard mode == .expanded else { return }
        content.balance.setParticleInteractionPoint(point, from: view)
        content.change.setParticleInteractionPoint(point, from: view)
    }

    func setMotionLight(_ light: CardSurfaceLight, preset: CardMotionPreset?) {
        motionLight = light
        motionPreset = preset
        applyMotionLight()
    }

    private func applyMotionLight() {
        // The collapsed face owns its balance scale; material planes only exist
        // on the expanded card.
        guard mode == .expanded else { return }
        if let motionPreset {
            motionPreset.applyContentLight(motionLight, balance: content.balance, change: content.change, accountLine: content.accountLine, decoration: content.seasonal)
        } else {
            content.change.setMaterialLight(tilt: .zero, emboss: nil)
            content.accountLine.setMaterialLight(tilt: .zero, emboss: nil)
            for view in [content.balance, content.change, content.accountLine, content.seasonal] as [UIView] {
                view.transform = .identity
                view.layer.shadowOpacity = 0
            }
        }
    }

    func prepareForReuse() {
        setMotionLight(CardSurfaceLight(), preset: nil)
        observation?.cancel()
        observation = nil
        collapseProgress = 0
        addressObservation?.cancel()
        addressObservation = nil
        addressLine = nil
        accountContext = nil
        headerViewModel = nil
        renderState = nil
        wasVisible = false
        content.prepareForReuse()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        content.frame = bounds
        applyMotionLight()
    }

    @objc private func openAddresses() { addressMenu.present() }

    @objc private func saveAccount() {
        guard let accountContext else { return }
        AppActions.saveTemporaryViewAccount(accountId: accountContext.accountId)
    }

    @objc private func toggleBalancePrivacy() {
        let point = content.balance.lastTapLocation ?? CGPoint(x: content.balance.bounds.midX, y: content.balance.bounds.midY)
        content.balance.preparePrivacyTransition(at: point)
        content.change.preparePrivacyTransition(at: content.change.convert(point, from: content.balance))
        AppActions.setSensitiveDataIsHidden(!sensitiveData.isHidden)
    }

    @objc private func openPromotion() {
        guard let promotion = accountContext?.activePromotion, let overlay = promotion.cardOverlay else { return }
        switch overlay.onClickAction {
        case .openPromotionModal: AppActions.showPromotion(promotion)
        case .openMintCardModal:
            guard let accountContext else { return }
            AppActions.showMintCard(accountContext: accountContext)
        }
    }
}
