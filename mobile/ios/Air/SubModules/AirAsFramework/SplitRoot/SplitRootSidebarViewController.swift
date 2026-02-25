import UIKit
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
private let sidebarTopContentInset: CGFloat = 20
private let sidebarTopGradientSolidInset = S.homeInsetSectionCornerRadius

@MainActor
protocol SplitRootSidebarViewControllerDelegate: AnyObject {
    func splitRootSidebarDidSelectTab(_ tab: SplitRootTab)
}

@MainActor
final class SplitRootSidebarViewController: WViewController, WalletCoreData.EventsObserver, UICollectionViewDelegate {
    private enum Section: Hashable {
        case tabs
        case accounts
    }
    
    private enum Item: Hashable {
        case tab(SplitRootTab)
        case account(String)
        case walletSettings
        case addAccount
    }
    
    private let viewModel: SplitRootViewModel
    
    private let accountSelector = HomeAccountSelector(accountSource: .current, mode: .sidebar)
    private let accountSelectorGradientLeading = EdgeGradientView()
    private let accountSelectorGradientTrailing = EdgeGradientView()
    private let collectionTopGradient = EdgeGradientView()
    private var accountSelectorHeightConstraint: NSLayoutConstraint?
    private let updateStatusView = UpdateStatusView(accountSource: .current)
    
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!
    
    private var selectedTab: SplitRootTab { viewModel.selectedTab }
        
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
        updateStatusViewState(animated: false)
        updateTheme()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateAccountSelectorHeightIfNeeded()
    }
    
    override func updateTheme() {
        view.backgroundColor = WTheme.sidebarBackground
        updateStatusViewState(animated: false)
    }
    
    func setSelectedTab(_ tab: SplitRootTab) {
        viewModel.onTabTap(tab)
    }
    
    func focusTemporaryAccount(_ accountId: String) {
        accountSelector.setSelectionOverride(accountId: accountId, animated: true)
    }
    
    private func setupViews() {
        navigationItem.titleView = updateStatusView
        accountSelector.minimumHomeCardFontScale = 0
        
        accountSelector.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(accountSelector)
        let selectorHeight = HomeCardLayoutMetrics.screen.itemHeight
        accountSelectorHeightConstraint = accountSelector.heightAnchor.constraint(equalToConstant: selectorHeight)
        
        accountSelectorGradientLeading.translatesAutoresizingMaskIntoConstraints = false
        accountSelectorGradientLeading.color = WTheme.sidebarBackground.withAlphaComponent(0.6)
        accountSelectorGradientLeading.direction = .leading
        view.addSubview(accountSelectorGradientLeading)
        
        accountSelectorGradientTrailing.translatesAutoresizingMaskIntoConstraints = false
        accountSelectorGradientTrailing.color = WTheme.sidebarBackground.withAlphaComponent(0.6)
        accountSelectorGradientTrailing.direction = .trailing
        view.addSubview(accountSelectorGradientTrailing)
        
        setupCollectionView()
        view.insertSubview(collectionView, at: 0)
        
        collectionTopGradient.translatesAutoresizingMaskIntoConstraints = false
        collectionTopGradient.color = WTheme.sidebarBackground
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
        
        accountSelectorGradientLeading.color = WTheme.sidebarBackground.withAlphaComponent(0.6)
        accountSelectorGradientTrailing.color = WTheme.sidebarBackground.withAlphaComponent(0.6)
        collectionTopGradient.color = WTheme.sidebarBackground
        collectionView?.backgroundColor = .clear
        
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
        accountsConfiguration.separatorConfiguration.color = WTheme.separator
        accountsConfiguration.separatorConfiguration.bottomSeparatorInsets.leading = 62
        
        let layout = UICollectionViewCompositionalLayout { sectionIndex, layoutEnvironment in
            let sectionType: Section = sectionIndex == 0 ? .tabs : .accounts
            let listConfiguration = sectionType == .tabs ? tabsConfiguration : accountsConfiguration
            let section = NSCollectionLayoutSection.list(using: listConfiguration, layoutEnvironment: layoutEnvironment)
            if sectionType == .accounts {
                section.contentInsets.top = tabsToAccountsSpacing
                section.contentInsets.bottom = 24
            } else {
                section.contentInsets.bottom = 0
            }
            return section
        }
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.delaysContentTouches = false
        collectionView.clipsToBounds = false
        collectionView.showsVerticalScrollIndicator = false
        collectionView.contentInset.top = sidebarTopContentInset
        collectionView.verticalScrollIndicatorInsets.top = sidebarTopContentInset
        collectionView.delegate = self
        
        let tabRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, SplitRootTab> { cell, _, tab in
            cell.configurationUpdateHandler = { [weak self] cell, _ in
                guard let self else { return }
                let isSelected = tab == self.viewModel.selectedTab
                cell.contentConfiguration = UIHostingConfiguration {
                    HStack {
                        Image(uiImage: tab.icon)
                            .renderingMode(.template)
                            .frame(width: 34, height: 34)
                        Text(tab.title)
                            .font(.system(size: 17, weight: isSelected ? .semibold : .regular))
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
        
        let accountRegistration = AccountListCell.makeRegistration(showBalance: true, normalBackground: .clear, showCurrentAccountHighlight: false)
        
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
                background.backgroundColor = state.isHighlighted ? WTheme.highlight : .clear
                listCell.backgroundConfiguration = background
            }
        }
        
        dataSource = UICollectionViewDiffableDataSource<Section, Item>(collectionView: collectionView) { collectionView, indexPath, item in
            switch item {
            case .tab(let tab):
                return collectionView.dequeueConfiguredReusableCell(using: tabRegistration, for: indexPath, item: tab)
            case .account(let accountId):
                return collectionView.dequeueConfiguredReusableCell(using: accountRegistration, for: indexPath, item: accountId)
            case .walletSettings, .addAccount:
                return collectionView.dequeueConfiguredReusableCell(using: actionRegistration, for: indexPath, item: item)
            }
        }
    }
    
    private func makeSnapshot() -> NSDiffableDataSourceSnapshot<Section, Item> {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.tabs])
        snapshot.appendItems(SplitRootTab.allCases.map(Item.tab), toSection: .tabs)
        
        snapshot.appendSections([.accounts])
        let currentAccountId = AccountStore.accountId
        let otherAccounts = AccountStore.orderedAccountIds.filter { $0 != currentAccountId }
        
        if otherAccounts.count <= 6 {
            snapshot.appendItems(otherAccounts.map(Item.account), toSection: .accounts)
        } else {
            snapshot.appendItems(Array(otherAccounts.prefix(5)).map(Item.account), toSection: .accounts)
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
            accountSelector.setSelectionOverride(accountId: accountId, animated: true)
            (splitViewController as? SplitRootViewController)?.showTemporaryViewAccount(accountId: accountId)
            return
        }
        accountSelector.setSelectionOverride(accountId: nil, animated: true)
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
    
    private func updateAccountSelectorHeightIfNeeded() {
        guard let accountSelectorHeightConstraint else { return }
        let width = view.bounds.width
        guard width > 0 else { return }
        let targetHeight = HomeCardLayoutMetrics.forContainerWidth(width).itemHeight
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
            updateStatusView.setState(newState: .updated, animatedWithDuration: 0.2)
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
        case .tab(let tab):
            viewModel.onTabTap(tab)
        case .account(let accountId):
            selectAccount(accountId)
        case .walletSettings:
            AppActions.showWalletSettings()
        case .addAccount:
            AppActions.showAddWallet(network: .mainnet, showCreateWallet: true, showSwitchToOtherVersion: true)
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
        case .account, .addAccount, .walletSettings: true
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
                .font(.system(size: 18, weight: .regular))
                .frame(width: actionIconContainerWidth)
            
            Text(title)
                .font(.system(size: 17, weight: .regular))
                .lineLimit(1)
                .allowsTightening(true)
        }
        .foregroundStyle(Color.accentColor)
        .padding(.vertical, actionRowVerticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
