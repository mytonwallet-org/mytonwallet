//
//  EarnVC.swift
//  UIEarn
//
//  Created by Sina on 5/13/24.
//

import SwiftUI
import UIKit
import UIComponents
import WalletCore
import WalletContext
import OrderedCollections

@MainActor
public class EarnVC: WViewController, WSegmentedControllerContent, WSensitiveDataProtocol {
    
    private let earnVM: EarnVM
    private var accountContext: AccountContext { earnVM.accountContext }
    private var stakingData: MStakingData? { accountContext.stakingData }
    
    private var config: StakingConfig { earnVM.config }
    private var tokenSlug: String { config.baseTokenSlug }
    private var stakedTokenSlug: String { config.stakedTokenSlug }
    private var token: ApiToken { config.baseToken }
    private var stakedToken: ApiToken { config.stakedToken }
    private var stakingState: ApiStakingState? { config.stakingState(stakingData: stakingData) }

    private var areProfitsCollapsed = true
    
    public init(earnVM: EarnVM) {
        self.earnVM = earnVM
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()

        setupViews()
        earnVM.delegate = self
        earnVM.loadInitialHistory()
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        earnVM.setScreenVisible(true)
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        earnVM.setScreenVisible(false)
    }

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Row>?
    private var emptyView: EmptyEarnView!
    private var indicatorView: WActivityIndicator!
    private var belowSafeAreaView: UIView!
    private lazy var claimRewardsViewModel = ClaimRewardsModel(accountContext: accountContext)
    private var claimRewardsView: HostingView!
    
    private enum Section: Hashable {
        case header
        case history
    }
    private enum Row: Hashable, Sendable {
        case header
        case historyHeader
        case historyItem(MStakingHistoryItem)
        case stackedProfits(aggregated: MStakingHistoryItem, startTimestamp: Int64, count: Int)
    }

    private func setupViews() {
        let tokenSlug = self.tokenSlug
        title = config.displayTitle

        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeCollectionViewLayout())
        self.collectionView = collectionView
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.delegate = self
        collectionView.alwaysBounceVertical = true
        collectionView.allowsSelection = true
        collectionView.delaysContentTouches = false
        collectionView.backgroundColor = .air.groupedItem
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        let headerCellRegistration = UICollectionView.CellRegistration<EarnHeaderCell, Row> { [unowned self] cell, _, _ in
            cell.configure(config: config, stakingData: stakingData, supportsEarn: accountContext.account.supportsEarn, delegate: self)
        }
        let historyHeaderCellRegistration = UICollectionView.CellRegistration<EarnHistoryHeaderCell, Row> { [unowned self] cell, _, _ in
            let earnedAmount: TokenAmount?
            if tokenSlug == TONCOIN_SLUG, let totalProfit = stakingData?.totalProfit {
                earnedAmount = TokenAmount(totalProfit, ApiToken.TONCOIN)
            } else if case .jetton(let jetton) = self.stakingState {
                earnedAmount = TokenAmount(jetton.unclaimedRewards, self.token)
            } else {
                earnedAmount = nil
            }
            cell.configure(earnedAmount: earnedAmount)
        }
        let historyCellRegistration = UICollectionView.CellRegistration<EarnHistoryCell, Row> { [unowned self] cell, indexPath, itemIdentifier in
            switch itemIdentifier {
            case .historyItem(let historyItem):
                cell.configure(earnHistoryItem: historyItem, token: token)
                let isLastInSection = indexPath.item == collectionView.numberOfItems(inSection: indexPath.section) - 1
                cell.setSeparatorHidden(isLastInSection)

            case .stackedProfits(let profits, let startTimestamp, let count):
                cell.configure(stackedProfits: profits, startTimestamp: startTimestamp, count: count, token: token)
                let isLastInSection = indexPath.item == collectionView.numberOfItems(inSection: indexPath.section) - 1
                cell.setSeparatorHidden(isLastInSection)

            case .header, .historyHeader:
                break
            }
        }

        dataSource = UICollectionViewDiffableDataSource<Section, Row>(collectionView: collectionView) { collectionView, indexPath, itemIdentifier in
            switch itemIdentifier {
            case .header:
                return collectionView.dequeueConfiguredReusableCell(using: headerCellRegistration, for: indexPath, item: itemIdentifier)

            case .historyHeader:
                return collectionView.dequeueConfiguredReusableCell(using: historyHeaderCellRegistration, for: indexPath, item: itemIdentifier)

            case .historyItem, .stackedProfits:
                return collectionView.dequeueConfiguredReusableCell(using: historyCellRegistration, for: indexPath, item: itemIdentifier)
            }
        }
        dataSource?.apply(makeSnapshot(), animatingDifferences: false)

        belowSafeAreaView = UIView()
        belowSafeAreaView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.addSubview(belowSafeAreaView)
        NSLayoutConstraint.activate([
            belowSafeAreaView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            belowSafeAreaView.widthAnchor.constraint(equalTo: view.widthAnchor),
            belowSafeAreaView.bottomAnchor.constraint(equalTo: collectionView.contentLayoutGuide.topAnchor),
            belowSafeAreaView.heightAnchor.constraint(equalToConstant: 500),
        ])

        emptyView = EmptyEarnView(config: config)
        emptyView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyView)
        let emptyViewTopConstraint = emptyView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 370)
        emptyViewTopConstraint.priority = .defaultLow
        NSLayoutConstraint.activate([
            emptyViewTopConstraint,
            emptyView.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -64),
            emptyView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyView.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -64),
        ])
        emptyView.alpha = 0
        
        indicatorView = WActivityIndicator()
        indicatorView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(indicatorView)
        NSLayoutConstraint.activate([
            indicatorView.centerXAnchor.constraint(equalTo: emptyView.centerXAnchor),
            indicatorView.centerYAnchor.constraint(equalTo: emptyView.centerYAnchor)
        ])
        
        claimRewardsViewModel.viewController = self
        claimRewardsViewModel.onClaim = { [weak self] in
            guard let self else { return }
            Task {
                do {
                    try await self.claimRewardsViewModel.confirmAction(account: self.accountContext.account)
                    withAnimation(.default.delay(0.3)) {
                        self.claimRewardsViewModel.isConfirming = false
                    }
                } catch {
                    AppActions.showError(error: error)
                }
            }
        }
        claimRewardsView = HostingView(ignoreSafeArea: false) { [claimRewardsViewModel] in
            ClaimRewardsView(viewModel: claimRewardsViewModel)
        }
        claimRewardsView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(claimRewardsView)
        NSLayoutConstraint.activate([
            claimRewardsView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            claimRewardsView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            claimRewardsView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        updateClaimRewardsButton()
        
        updateLoadingState()
        
        updateTheme()
    }

    private func makeCollectionViewLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { sectionIndex, _ in
            let estimatedHeight: CGFloat = sectionIndex == 0 ? 360 : 56
            let size = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .estimated(estimatedHeight)
            )
            let item = NSCollectionLayoutItem(layoutSize: size)
            let group = NSCollectionLayoutGroup.vertical(layoutSize: size, subitems: [item])
            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = 0
            return section
        }
    }
    
    private func updateTheme() {
        belowSafeAreaView.backgroundColor = .air.sheetBackground
        collectionView.backgroundColor = .air.groupedItem
    }
    
    func updateClaimRewardsButton() {
        claimRewardsViewModel.token = token
        claimRewardsViewModel.stakingState = stakingState
        if case let .jetton(jetton) = stakingState {
            claimRewardsView.alpha = jetton.unclaimedRewards > 0 ? 1 : 0
            collectionView.contentInset.bottom = 56
        } else {
            claimRewardsView.alpha = 0
            collectionView.contentInset.bottom = 0
        }
    }
    
    @discardableResult
    func openUnstakeFlow(animated: Bool) -> Bool {
        guard let stakingState = earnVM.stakingState else {
            return false
        }
        let vc = UnstakeVC(config: config, stakingState: stakingState, accountContext: accountContext)
        navigationController?.pushViewController(vc, animated: animated)
        return true
    }

    func stakeUnstakePressed(isStake: Bool) {
        if let stakingState = earnVM.stakingState {
            if isStake {
                let vc = AddStakeVC(config: config, stakingState: stakingState, accountContext: accountContext)
                navigationController?.pushViewController(vc, animated: true)

            } else {
                if config.readyToUnstakeAmount(stakingData: stakingData) != nil {
                    claimRewardsViewModel.onClaim()
                } else {
                    openUnstakeFlow(animated: true)
                }
            }
        }
    }
    
    private func updateLoadingState(animated: Bool = true) {
        let hasHistoryItems = earnVM.historyItems?.isEmpty == false
        let isLoadingInitialHistory = earnVM.historyItems == nil || (!hasHistoryItems && !earnVM.allLoadedOnce)
        let shouldShowEmptyState = earnVM.allLoadedOnce && earnVM.historyItems?.isEmpty == true
        
        if let apy = stakingState?.apy {
            let apyString = formatPercent(apy / 100)
            emptyView.estimatedAPYLabel.text = "\(lang("Est. %annual_yield%", arg1: apyString))"
            emptyView.estimatedAPYLabel.isHidden = false
        } else {
            emptyView.estimatedAPYLabel.text = nil
            emptyView.estimatedAPYLabel.isHidden = true
        }
        
        if isLoadingInitialHistory {
            indicatorView.startAnimating(animated: animated)
        } else {
            indicatorView.stopAnimating(animated: animated)
        }
        
        setEmptyStateVisible(shouldShowEmptyState, animated: animated)
    }
    
    private func setEmptyStateVisible(_ isVisible: Bool, animated: Bool) {
        let alpha: CGFloat = isVisible ? 1 : 0
        guard emptyView.alpha != alpha else { return }
        let changes: () -> Void = { [weak self] in
            self?.emptyView.alpha = alpha
        }
        if animated {
            UIView.animate(withDuration: 0.25, animations: changes)
        } else {
            changes()
        }
    }
    
    public func updateSensitiveData() {
        if let dataSource {
            var snapshot = dataSource.snapshot()
            snapshot.reconfigureItems([.historyHeader])
            dataSource.apply(snapshot)
        }
    }
    
    public var onScroll: ((CGFloat) -> Void)?
    public var scrollingView: UIScrollView? { collectionView }
    public func calculateHeight(isHosted: Bool) -> CGFloat { 0 }
}


extension EarnVC: UICollectionViewDelegate {
    
    private func makeSnapshot() -> NSDiffableDataSourceSnapshot<Section, Row> {
        
        let historyItems = earnVM.historyItems ?? []
        
        var snapshot = NSDiffableDataSourceSnapshot<Section, Row>()
        snapshot.appendSections([.header])
        snapshot.appendItems([.header])
        snapshot.appendSections([.history])
        snapshot.appendItems([.historyHeader])
        
        var seenFirstProfit = false
        var profits: [MStakingHistoryItem] = []
        
        if areProfitsCollapsed {
            for historyItem in historyItems {
                switch historyItem.type {
                case .profit:
                    if seenFirstProfit {
                        profits.append(historyItem)
                    } else {
                        seenFirstProfit = true
                        snapshot.appendItems([.historyItem(historyItem)])
                    }
                    
                default:
                    if !profits.isEmpty {
                        let count = profits.count
                        if count == 1 {
                            snapshot.appendItems([.historyItem(profits[0])])
                        } else {
                            if var agg = profits.first, let last = profits.last {
                                agg.amount = profits.reduce(0) { $0 + $1.amount }
                                snapshot.appendItems([.stackedProfits(aggregated: agg, startTimestamp: last.timestamp, count: count)])
                            }
                        }
                        profits = []
                    }
                    snapshot.appendItems([.historyItem(historyItem)])
                }
            }
            
            if !profits.isEmpty {
                let count = profits.count
                if count == 1 {
                    snapshot.appendItems([.historyItem(profits[0])])
                } else {
                    if var agg = profits.first, let last = profits.last {
                        agg.amount = profits.reduce(0) { $0 + $1.amount }
                        snapshot.appendItems([.stackedProfits(aggregated: agg, startTimestamp: last.timestamp, count: count)])
                    }
                }
                profits = []
            }
        } else {
            snapshot.appendItems(historyItems.map { Row.historyItem($0)})
        }
        
        return snapshot
    }
    
    private func applySnapshot(animated: Bool, reloadHeader: Bool = true) {
        var snapshot = makeSnapshot()
        if reloadHeader {
            snapshot.reconfigureItems([.header])
            if snapshot.indexOfItem(.historyHeader) != nil {
                snapshot.reconfigureItems([.historyHeader])
            }
        }
        dataSource?.apply(snapshot, animatingDifferences: animated)
    }
    
    public func collectionView(_: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        switch dataSource?.itemIdentifier(for: indexPath) {
        case .stackedProfits?:
            return areProfitsCollapsed
        default:
            return false
        }
    }

    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        defer {
            collectionView.deselectItem(at: indexPath, animated: true)
        }

        guard case .stackedProfits = dataSource?.itemIdentifier(for: indexPath),
              areProfitsCollapsed else {
            return
        }

        areProfitsCollapsed = false
        applySnapshot(animated: true)
    }
    
    public func collectionView(_: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        if let id = dataSource?.itemIdentifier(for: indexPath) {
            switch id {
            case .historyItem(let historyItem), .stackedProfits(let historyItem, _, _):
                let areProfitsCollapsed = self.areProfitsCollapsed
                if historyItem.type == .profit {
                    return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
                        let action = UIAction(title: areProfitsCollapsed ? lang("Expand") : lang("Collapse")) { [weak self] v in
                            self?.areProfitsCollapsed.toggle()
                            self?.applySnapshot(animated: true)
                        }
                        return UIMenu(children: [action])
                    }
                }
            default:
                break
            }
        }
        return nil
    }
    
    public func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        let identifier = dataSource?.itemIdentifier(for: indexPath)
        if case .historyItem(let showingItem) = identifier {
            if let lastStakingItem = earnVM.lastStakingItem,
               showingItem.timestamp <= lastStakingItem {
                earnVM.loadMoreStakingHistory()
            }
            if let lastActivityItemTimestamp = earnVM.lastActivityItem?.1,
               showingItem.timestamp <= lastActivityItemTimestamp {
                earnVM.loadMoreActivityItems()
            }
            if let lastUnstakeActivityItemTimestamp = earnVM.lastUnstakeActivityItem?.1,
               showingItem.timestamp <= lastUnstakeActivityItemTimestamp {
                earnVM.loadMoreUnstakeActivityItems()
            }
        }
    }
}

extension EarnVC: EarnMVDelegate {
    public func stakingStateUpdated() {
        updateLoadingState()
        applySnapshot(animated: true, reloadHeader: true)
        updateClaimRewardsButton()
    }
    
    public func newPageLoaded(animateChanges: Bool) {
        updateLoadingState(animated: animateChanges)
        if animateChanges {
            applySnapshot(animated: true, reloadHeader: true)
        } else {
            UIView.transition(with: view, duration: 0.3, options: [.allowUserInteraction, .transitionCrossDissolve]) {
                self.applySnapshot(animated: false, reloadHeader: true)
            }
        }
    }
}
