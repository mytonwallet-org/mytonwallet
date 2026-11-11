import UIKit
import ContextMenuKit
import UIComponents
import UIHome
import WalletCore
import WalletContext
import SwiftUI

private let tabsToAccountsSpacing: CGFloat = 10
private let actionIconContainerWidth: CGFloat = 62
private let actionIconSize: CGFloat = 30
private let actionRowVerticalPadding: CGFloat = IOS_26_MODE_ENABLED ? 11 : 7
private let sidebarEdgeGradientWidth: CGFloat = 16
private let sidebarTopContentInset: CGFloat = 16
private let sidebarTopGradientSolidInset = S.homeInsetSectionCornerRadius


@MainActor
final class SplitRootSidebarViewController: WViewController, WalletCoreData.EventsObserver, UICollectionViewDelegate, UIGestureRecognizerDelegate, Sendable {
    private enum Section: Hashable {
        case multisigWarning
        case banners
        case tabs
        case accounts
    }
    
    private enum Item: Hashable {
        case multisigWarning(String)
        case banners(String)
        case tab(AppTabId)
        case account(String)
        case walletSettings
        case addAccount
    }
    
    var hiddenTabIds: Set<AppTabId> = [] {
        didSet {
            guard oldValue != hiddenTabIds, isViewLoaded else { return }
            applySnapshot(animated: false)
        }
    }

    private let viewModel: SplitRootViewModel
    
    private let accountSelector = HomeAccountSelector(accountSource: .current, mode: .sidebar)
    private let accountSelectorGradientLeading = EdgeGradientView()
    private let accountSelectorGradientTrailing = EdgeGradientView()
    private let collectionTopGradient = EdgeGradientView()
    private var accountSelectorHeightConstraint: NSLayoutConstraint?
    private var contentMargins: NSDirectionalEdgeInsets = .zero
    private let updateStatusAccountContext = AccountContext(source: .current)
    private lazy var updateStatusView = UpdateStatusView(accountContext: updateStatusAccountContext)
    private var titleMenuInteraction: ContextMenuInteraction?
    
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!
    private var bannersAccountId: String?
    private var multisigWarningAccountId: String?

    private var activateAccountTask: Task<Void, Never>?
    private var setUpdatingAfterDelayTask: Task<Void, Never>?
    
    init(viewModel: SplitRootViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.largeTitleDisplayMode = .never
        setupViews()
        WalletCoreData.add(eventObserver: self)
        applySnapshot(animated: false)
        observe { [weak self] in
            guard let self else { return }
            let accountId = updateStatusAccountContext.accountId
            let bannersAccountId = updateStatusAccountContext.config.banners.home.isEmpty ? nil : accountId
            let multisigWarningAccountId = updateStatusAccountContext.account.byChain.values.contains { $0.isMultisig == true } ? accountId : nil
            guard self.bannersAccountId != bannersAccountId || self.multisigWarningAccountId != multisigWarningAccountId else { return }
            self.bannersAccountId = bannersAccountId
            self.multisigWarningAccountId = multisigWarningAccountId
            applySnapshot(animated: true)
        }
        updateStatusViewState(animated: false)
        updateTheme()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateContentLayout()
    }

    override func viewLayoutMarginsDidChange() {
        super.viewLayoutMarginsDidChange()
        updateContentLayout()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        accountSelector.setCardEffectsActive(true)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        accountSelector.setCardEffectsActive(false)
    }
    
    private func updateTheme() {
        view.backgroundColor = .air.sidebarBackground
        updateStatusViewState(animated: false)
    }
    
    func applyTabConfiguration(_ orderedIds: [AppTabId]) {
        guard isViewLoaded else { return }
        applySnapshot(animated: true)
    }
    
    func focusAccount(_ accountId: String?, animated: Bool) {
        accountSelector.setSelectionOverride(accountId: accountId, animated: animated)
        updateStatusAccountContext.accountId = accountId ?? AccountStore.accountId ?? DUMMY_ACCOUNT.id
        updateStatusViewState(animated: animated)
    }
    
    private func setupViews() {
        navigationItem.titleView = updateStatusView
        let titleMenuInteraction = ContextMenuInteraction(
            triggers: [.longPress],
            pressAnimation: .default(transformMode: .sublayerTransform)
        ) { [weak self] _ in
            self?.makeTitleMenuConfiguration()
        }
        titleMenuInteraction.attach(to: updateStatusView)
        self.titleMenuInteraction = titleMenuInteraction

        accountSelector.minimumHomeCardFontScale = 0
        
        accountSelector.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(accountSelector)
        let selectorHeight = HomeCardLayoutMetrics.screen.itemHeight
        accountSelectorHeightConstraint = accountSelector.heightAnchor.constraint(equalToConstant: selectorHeight)
        
        accountSelectorGradientLeading.translatesAutoresizingMaskIntoConstraints = false
        accountSelectorGradientLeading.color = .air.sidebarBackground.withAlphaComponent(0.6)
        accountSelectorGradientLeading.direction = .leading
        view.addSubview(accountSelectorGradientLeading)
        
        accountSelectorGradientTrailing.translatesAutoresizingMaskIntoConstraints = false
        accountSelectorGradientTrailing.color = .air.sidebarBackground.withAlphaComponent(0.6)
        accountSelectorGradientTrailing.direction = .trailing
        view.addSubview(accountSelectorGradientTrailing)
        
        setupCollectionView()
        view.insertSubview(collectionView, at: 0)
        
        collectionTopGradient.translatesAutoresizingMaskIntoConstraints = false
        collectionTopGradient.color = .air.sidebarBackground
        collectionTopGradient.direction = .top
        collectionTopGradient.solidEdgeLength = sidebarTopGradientSolidInset
        view.insertSubview(collectionTopGradient, belowSubview: accountSelector)
        
        NSLayoutConstraint.activate([
            accountSelector.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 0),
            accountSelector.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            accountSelector.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            accountSelectorHeightConstraint!,
            
            accountSelectorGradientLeading.leadingAnchor.constraint(equalTo: accountSelector.leadingAnchor),
            accountSelectorGradientLeading.topAnchor.constraint(equalTo: accountSelector.topAnchor),
            accountSelectorGradientLeading.bottomAnchor.constraint(equalTo: accountSelector.bottomAnchor),
            accountSelectorGradientLeading.widthAnchor.constraint(equalToConstant: sidebarEdgeGradientWidth),
            
            accountSelectorGradientTrailing.trailingAnchor.constraint(equalTo: accountSelector.trailingAnchor),
            accountSelectorGradientTrailing.topAnchor.constraint(equalTo: accountSelector.topAnchor),
            accountSelectorGradientTrailing.bottomAnchor.constraint(equalTo: accountSelector.bottomAnchor),
            accountSelectorGradientTrailing.widthAnchor.constraint(equalToConstant: sidebarEdgeGradientWidth),
            
            collectionView.topAnchor.constraint(equalTo: accountSelector.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            collectionTopGradient.topAnchor.constraint(equalTo: collectionView.topAnchor, constant: -sidebarTopGradientSolidInset),
            collectionTopGradient.leadingAnchor.constraint(equalTo: collectionView.leadingAnchor),
            collectionTopGradient.trailingAnchor.constraint(equalTo: collectionView.trailingAnchor),
            collectionTopGradient.heightAnchor.constraint(equalToConstant: sidebarTopContentInset + sidebarTopGradientSolidInset),
        ])
        
        accountSelectorGradientLeading.color = .air.sidebarBackground.withAlphaComponent(0.6)
        accountSelectorGradientTrailing.color = .air.sidebarBackground.withAlphaComponent(0.6)
        collectionTopGradient.color = .air.sidebarBackground
        collectionView?.backgroundColor = .clear
        
        accountSelector.setEdgeGradients(leading: accountSelectorGradientLeading,
                                         trailing: accountSelectorGradientTrailing)
        accountSelector.onSelect = { [weak self] accountId in
            self?.selectAccount(accountId)
        }
    }
    
    private func setupCollectionView() {
        var tabsConfiguration = UICollectionLayoutListConfiguration(appearance: .sidebar)
        tabsConfiguration.headerMode = .none
        tabsConfiguration.backgroundColor = .clear
        
        var accountsConfiguration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        accountsConfiguration.headerMode = .none
        accountsConfiguration.backgroundColor = .clear
        accountsConfiguration.separatorConfiguration.color = .air.separator
        accountsConfiguration.separatorConfiguration.bottomSeparatorInsets.leading = 62
        
        let configuration = UICollectionViewCompositionalLayoutConfiguration()
        configuration.contentInsetsReference = .none
        let layout = UICollectionViewCompositionalLayout(sectionProvider: { [weak self] sectionIndex, layoutEnvironment in
            guard let self, let sectionType = dataSource.sectionIdentifier(for: sectionIndex) else { return nil }
            if sectionType == .banners || sectionType == .multisigWarning {
                let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(120))
                let item = NSCollectionLayoutItem(layoutSize: size)
                let group = NSCollectionLayoutGroup.vertical(layoutSize: size, subitems: [item])
                let section = NSCollectionLayoutSection(group: group)
                section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: contentMargins.leading,
                                                               bottom: sectionType == .multisigWarning ? 16 : 8, trailing: contentMargins.trailing)
                return section
            }
            let listConfiguration = sectionType == .tabs ? tabsConfiguration : accountsConfiguration
            let section = NSCollectionLayoutSection.list(using: listConfiguration, layoutEnvironment: layoutEnvironment)
            section.contentInsetsReference = .none
            section.contentInsets.leading = contentMargins.leading
            section.contentInsets.trailing = contentMargins.trailing
            if sectionType == .accounts {
                section.contentInsets.top = tabsToAccountsSpacing
                section.contentInsets.bottom = 24
            } else {
                section.contentInsets.bottom = 0
            }
            return section
        }, configuration: configuration)
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.delaysContentTouches = false
        collectionView.clipsToBounds = false
        collectionView.showsVerticalScrollIndicator = false
        collectionView.contentInset.top = sidebarTopContentInset
        collectionView.contentInsetAdjustmentBehavior = .scrollableAxes
        collectionView.verticalScrollIndicatorInsets.top = sidebarTopContentInset
        collectionView.delegate = self

        let bannersRegistration = UICollectionView.CellRegistration<UICollectionViewCell, String> { cell, _, accountId in
            cell.contentConfiguration = UIHostingConfiguration {
                HomeAccountBannersView(accountContext: AccountContext(accountId: accountId))
            }
            .background { Color.clear }
            .margins(.all, 0)
        }

        let multisigWarningRegistration = UICollectionView.CellRegistration<UICollectionViewCell, String> { cell, _, _ in
            cell.contentConfiguration = UIHostingConfiguration {
                MultisigWalletWarning()
            }
            .background { Color.clear }
            .margins(.all, 0)
        }
        
        let registry = AppTabManager.shared
        let tabRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, AppTabId> { cell, _, tab in
            cell.configurationUpdateHandler = { [weak self] cell, _ in
                guard let self else { return }
                let isSelected = tab == self.viewModel.selectedTab
                let registration = registry.registration(for: tab)
                let icon = registration?.sidebarIcon ?? UIImage()
                let title = registration?.titleProvider() ?? tab.rawValue
                cell.contentConfiguration = UIHostingConfiguration {
                    HStack {
                        Image(uiImage: icon)
                            .renderingMode(.template)
                            .frame(width: 34, height: 34)
                        Text(title)
                            .textStyle(isSelected ? .bodyStrong : .body)
                    }
                    .frame(maxWidth: .infinity, minHeight: 52, maxHeight: 52, alignment: .leading)
                    .padding(.horizontal, 10)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                    .background {
                        Capsule()
                            .fill(isSelected ? Color.air.highlight : .clear)
                    }
                }
                .margins(.all, 0)
            }
        }
        
        let accountRegistration = AccountListCell.makeRegistration(
            showBalance: true,
            normalBackground: .clear,
            showCurrentAccountHighlight: true,
            contextMenuConfigurationProvider: { accountId in
                WalletNameContextMenu.makeConfiguration(accountId: { accountId })
            }
        )
        
        let actionRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, Item> { cell, _, item in
            cell.accessories = []
            cell.configurationUpdateHandler = { cell, state in
                let row: SplitRootSidebarActionRow
                switch item {
                case .walletSettings:
                    row = SplitRootSidebarActionRow(title: lang("Show All Wallets"), icon: Image(systemName: "ellipsis"))
                case .addAccount:
                    row = SplitRootSidebarActionRow(title: lang("Add Wallet"), icon: Image.airBundle("AddAccountIcon"))
                default:
                    return
                }
                guard let listCell = cell as? UICollectionViewListCell else { return }
                listCell.contentConfiguration = UIHostingConfiguration {
                    row
                }
                .margins(.leading, 0)
                .margins(.trailing, 12)
                .margins(.vertical, 0)
                
                var background = UIBackgroundConfiguration.listGroupedCell()
                background.backgroundColor = state.isHighlighted ? .air.highlight : .clear
                listCell.backgroundConfiguration = background
            }
        }
        
        dataSource = UICollectionViewDiffableDataSource<Section, Item>(collectionView: collectionView) { collectionView, indexPath, item in
            switch item {
            case .multisigWarning(let accountId):
                return collectionView.dequeueConfiguredReusableCell(using: multisigWarningRegistration, for: indexPath, item: accountId)
            case .banners(let accountId):
                return collectionView.dequeueConfiguredReusableCell(using: bannersRegistration, for: indexPath, item: accountId)
            case .tab(let tab):
                return collectionView.dequeueConfiguredReusableCell(using: tabRegistration, for: indexPath, item: tab)
            case .account(let accountId):
                return collectionView.dequeueConfiguredReusableCell(using: accountRegistration, for: indexPath, item: accountId)
            case .walletSettings, .addAccount:
                return collectionView.dequeueConfiguredReusableCell(using: actionRegistration, for: indexPath, item: item)
            }
        }
        setupTabReordering()
    }

    /// Holding a tab lifts it, and dragging it reorders the tabs
    private func setupTabReordering() {
        dataSource.reorderingHandlers.canReorderItem = { item in
            if case .tab = item { return true }
            return false
        }
        dataSource.reorderingHandlers.didReorder = { transaction in
            let ids = transaction.finalSnapshot.itemIdentifiers(inSection: .tabs).compactMap { item -> AppTabId? in
                if case .tab(let id) = item { return id }
                return nil
            }
            // The collection view calls this in the middle of ending the move. The new order reaches the root
            // containers, which apply a snapshot to this list, once the move has ended: a snapshot applied during it
            // breaks the collection view's update
            DispatchQueue.main.async {
                AppTabManager.shared.reorderTabs(ids)
            }
        }
        // UIKit's standard hold, 0.5 s within 10 pt, as in the tab menu
        let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleTabReorderPress(_:)))
        recognizer.delegate = self
        collectionView.addGestureRecognizer(recognizer)
    }

    private func tabIndexPath(at point: CGPoint) -> IndexPath? {
        guard let indexPath = collectionView.indexPathForItem(at: point),
              case .tab = dataSource.itemIdentifier(for: indexPath) else {
            return nil
        }
        return indexPath
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer is UILongPressGestureRecognizer, gestureRecognizer.view === collectionView else { return true }
        return tabIndexPath(at: gestureRecognizer.location(in: collectionView)) != nil
    }

    @objc private func handleTabReorderPress(_ recognizer: UILongPressGestureRecognizer) {
        let point = recognizer.location(in: collectionView)
        switch recognizer.state {
        case .began:
            guard let indexPath = tabIndexPath(at: point),
                  collectionView.beginInteractiveMovementForItem(at: indexPath) else {
                return
            }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .changed:
            collectionView.updateInteractiveMovementTargetPosition(CGPoint(x: collectionView.bounds.midX, y: point.y))
        case .ended:
            collectionView.endInteractiveMovement()
        default:
            collectionView.cancelInteractiveMovement()
        }
    }

    func collectionView(
        _ collectionView: UICollectionView,
        targetIndexPathForMoveOfItemFromOriginalIndexPath originalIndexPath: IndexPath,
        atCurrentIndexPath currentIndexPath: IndexPath,
        toProposedIndexPath proposedIndexPath: IndexPath
    ) -> IndexPath {
        // Tabs move only among tabs
        guard proposedIndexPath.section != originalIndexPath.section else { return proposedIndexPath }
        if proposedIndexPath.section < originalIndexPath.section {
            return IndexPath(item: 0, section: originalIndexPath.section)
        }
        let lastItem = collectionView.numberOfItems(inSection: originalIndexPath.section) - 1
        return IndexPath(item: lastItem, section: originalIndexPath.section)
    }
    
    private func makeSnapshot() -> NSDiffableDataSourceSnapshot<Section, Item> {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        if let multisigWarningAccountId {
            snapshot.appendSections([.multisigWarning])
            snapshot.appendItems([.multisigWarning(multisigWarningAccountId)], toSection: .multisigWarning)
        }
        if let bannersAccountId {
            snapshot.appendSections([.banners])
            snapshot.appendItems([.banners(bannersAccountId)], toSection: .banners)
        }
        snapshot.appendSections([.tabs])
        snapshot.appendItems(AppTabManager.shared.orderedTabIds.filter { !hiddenTabIds.contains($0) }.map(Item.tab), toSection: .tabs)
        
        snapshot.appendSections([.accounts])
        let accounts = AccountStore.orderedAccountIds
        
        if accounts.count <= 7 {
            snapshot.appendItems(accounts.map(Item.account), toSection: .accounts)
        } else {
            snapshot.appendItems(Array(accounts.prefix(6)).map(Item.account), toSection: .accounts)
            snapshot.appendItems([.walletSettings], toSection: .accounts)
        }
        snapshot.appendItems([.addAccount], toSection: .accounts)
        return snapshot
    }
    
    private func applySnapshot(animated: Bool) {
        dataSource.apply(makeSnapshot(), animatingDifferences: animated)
    }
    
    private func switchAccount(to accountId: String) {
        guard AccountStore.accountId != accountId else { return }
        activateAccountTask?.cancel()
        activateAccountTask = Task {
            do {
                _ = try await AccountStore.activateAccount(accountId: accountId)
            } catch is CancellationError {
            } catch {
                AppActions.showError(error: error)
            }
        }
    }
    
    private func selectAccount(_ accountId: String) {
        if AccountStore.accountsById[accountId]?.isTemporaryView == true {
            focusAccount(accountId, animated: true)
            (splitViewController as? SplitRootViewController)?.showTemporaryViewAccount(accountId: accountId)
            return
        }
        focusAccount(nil, animated: true)
        (splitViewController as? SplitRootViewController)?.dismissTemporaryViewAccountIfNeeded(animated: true)
        switchAccount(to: accountId)
    }
    
    private func updateStatusViewState(animated: Bool) {
        let isUpdating = AccountStore.updatingActivities || AccountStore.updatingBalance
        if isUpdating {
            if setUpdatingAfterDelayTask == nil || setUpdatingAfterDelayTask?.isCancelled == true {
                setUpdatingAfterDelayTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(2))
                    guard let self else { return }
                    if AccountStore.updatingActivities || AccountStore.updatingBalance {
                        self.updateStatusView.setState(newState: .updating, animatedWithDuration: animated ? 0.2 : nil)
                    }
                    self.setUpdatingAfterDelayTask = nil
                }
            }
        } else {
            setUpdatingAfterDelayTask?.cancel()
            setUpdatingAfterDelayTask = nil
            updateStatusView.setState(newState: .updated, animatedWithDuration: animated ? 0.2 : nil)
        }
    }
    
    private func makeTitleMenuConfiguration() -> ContextMenuConfiguration {
        WalletNameContextMenu.makeConfiguration(
            accountId: { [updateStatusAccountContext] in
                updateStatusAccountContext.account.id
            },
            sourceSpacing: 0
        )
    }

    private func updateContentLayout() {
        guard let accountSelectorHeightConstraint else { return }
        let margins = view.directionalLayoutMargins
        accountSelector.contentMargins = margins
        if contentMargins != margins {
            contentMargins = margins
            collectionView?.collectionViewLayout.invalidateLayout()
        }
        let width = view.bounds.width
        guard width > 0 else { return }
        let targetHeight = HomeCardLayoutMetrics.forContainerWidth(width, contentMargins: margins).itemHeight
        if abs(accountSelectorHeightConstraint.constant - targetHeight) > 0.5 {
            accountSelectorHeightConstraint.constant = targetHeight
        }
    }
    
    func walletCore(event: WalletCoreData.Event) {
        switch event {
        case .accountChanged(_, _):
            setUpdatingAfterDelayTask?.cancel()
            setUpdatingAfterDelayTask = nil
            updateStatusView.setState(newState: .updated, animatedWithDuration: nil)
            applySnapshot(animated: true)
        case .accountNameChanged:
            applySnapshot(animated: true)
        case .accountDeleted(_), .accountsReset:
            applySnapshot(animated: true)
        case .updatingStatusChanged:
            updateStatusViewState(animated: true)
        default:
            break
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return false }
        switch item {
        case .multisigWarning, .banners:
            break
        case .tab(let tabId):
            viewModel.onTabTap(tabId)
        case .account(let accountId):
            selectAccount(accountId)
        case .walletSettings:
            AppActions.showWalletSettings()
        case .addAccount:
            AppActions.showAddWallet(network: .mainnet, sourceView: collectionView.cellForItem(at: indexPath))
        }
        return false
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
    }
    
    func collectionView(_ collectionView: UICollectionView, shouldDeselectItemAt indexPath: IndexPath) -> Bool {
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return true }
        return switch item {
        case .tab: false
        case .multisigWarning, .banners, .account, .addAccount, .walletSettings: true
        }
    }
}

private struct SplitRootSidebarActionRow: View {
    let title: String
    let icon: Image
    
    var body: some View {
        HStack(spacing: 0) {
            icon
                .renderingMode(.template)
                .frame(width: actionIconSize, height: actionIconSize)
                .textStyle(.symbol, content: .technical)
                .frame(width: actionIconContainerWidth)
            
            Text(title)
                .textStyle(.body)
                .lineLimit(1)
                .allowsTightening(true)
        }
        .foregroundStyle(Color.accentColor)
        .padding(.vertical, actionRowVerticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
