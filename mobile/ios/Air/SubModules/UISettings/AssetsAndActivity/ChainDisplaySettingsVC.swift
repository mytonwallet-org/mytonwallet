import UIComponents
import UIKit
import WalletContext
import WalletCore

final class ChainDisplaySettingsVC: SettingsBaseVC {
    @AccountContext private var account: MAccount

    private enum Section: Hashable {
        case sorting
        case chains
    }

    private enum Item: Hashable {
        case sortByValue
        case chain(ApiChain)
    }

    private let isModal: Bool
    private var configuration: MChainDisplayConfiguration
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!
    private var isInteractivelyReordering = false

    init(accountContext: AccountContext, isModal: Bool) {
        self._account = accountContext
        self.isModal = isModal
        self.configuration = AssetsAndActivityDataStore
            .data(accountId: accountContext.account.id)?
            .chainDisplayConfiguration ?? MChainDisplayConfiguration()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        normalizeManualOrderForPresentation()
        setupViews()
        WalletCoreData.add(eventObserver: self)
    }

    private var defaultChains: [ApiChain] {
        account.orderedChains.map(\.0)
    }

    private var valueOrderedChains: [ApiChain] {
        _account.orderedChains.map(\.0)
    }

    private var chains: [ApiChain] {
        configuration.orderedChains(
            defaultOrder: defaultChains,
            valueOrder: valueOrderedChains,
            automaticallyVisibleChains: automaticallyVisibleChains
        )
    }

    private var automaticallyVisibleChains: Set<ApiChain> {
        _account.automaticallyVisibleChains
    }

    private var visibleChains: Set<ApiChain> {
        Set(configuration.visibleChains(
            defaultOrder: defaultChains,
            valueOrder: valueOrderedChains,
            automaticallyVisibleChains: automaticallyVisibleChains
        ))
    }

    private func setupViews() {
        title = lang("Blockchains")
        view.backgroundColor = isModal ? .air.sheetBackground : .air.groupedBackground

        var layoutConfiguration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        layoutConfiguration.backgroundColor = .clear
        layoutConfiguration.headerTopPadding = 24
        layoutConfiguration.footerMode = .supplementary
        let layout = UICollectionViewCompositionalLayout.list(using: layoutConfiguration)
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.delaysContentTouches = false
        collectionView.delegate = self
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        let sortingRegistration = UICollectionView.CellRegistration<SimpleGroupCell, Item> { [weak self] cell, _, _ in
            guard let self else { return }
            cell.title = lang("Sort by Value")
            cell.isSelectable = false
            cell.configureSwitchAccessory(isOn: configuration.displayMode == .value) { [weak self] isOn in
                self?.setDisplayMode(isOn ? .value : .manual)
            }
        }

        let chainRegistration = UICollectionView.CellRegistration<ChainVisibilityCell, Item> { [weak self] cell, _, item in
            guard let self, case .chain(let chain) = item else { return }
            let usesAutomaticAppearance = configuration.displayMode == .value
            let isVisible = visibleChains.contains(chain)
            cell.configure(
                chain: chain,
                isVisible: isVisible,
                isSwitchEnabled: !usesAutomaticAppearance && (!isVisible || visibleChains.count > 1),
                showsReorderControl: !usesAutomaticAppearance,
                usesAutomaticAppearance: usesAutomaticAppearance
            ) { [weak self] isVisible in
                self?.setChain(chain, isVisible: isVisible)
            } onReorderGesture: { [weak self, weak cell] gesture in
                guard let self, let cell else { return }
                self.handleReorderGesture(gesture, from: cell)
            }
        }

        dataSource = UICollectionViewDiffableDataSource<Section, Item>(collectionView: collectionView) {
            collectionView, indexPath, item in
            switch item {
            case .sortByValue:
                collectionView.dequeueConfiguredReusableCell(
                    using: sortingRegistration,
                    for: indexPath,
                    item: item
                )
            case .chain:
                collectionView.dequeueConfiguredReusableCell(
                    using: chainRegistration,
                    for: indexPath,
                    item: item
                )
            }
        }

        let footerRegistration = UICollectionView.SupplementaryRegistration<SimpleGroupSectionFooter>(
            elementKind: UICollectionView.elementKindSectionFooter
        ) { [weak self] view, _, indexPath in
            switch self?.dataSource.sectionIdentifier(for: indexPath.section) {
            case .sorting:
                view.text = lang("Automatically sort and hide chains based on your portfolio.")
            case .chains:
                view.text = lang("Hidden chains will still be available to receive and send tokens, but won’t appear in the main list.")
            case nil:
                break
            }
        }
        dataSource.supplementaryViewProvider = { collectionView, kind, indexPath in
            guard kind == UICollectionView.elementKindSectionFooter else { return nil }
            return collectionView.dequeueConfiguredReusableSupplementary(
                using: footerRegistration,
                for: indexPath
            )
        }

        dataSource.reorderingHandlers.canReorderItem = { [weak self] item in
            guard let self,
                  configuration.displayMode == .manual,
                  case .chain = item else { return false }
            return true
        }
        dataSource.reorderingHandlers.didReorder = { [weak self] transaction in
            self?.didReorder(transaction.finalSnapshot)
        }

        dataSource.apply(makeSnapshot(), animatingDifferences: false)
    }

    private func makeSnapshot() -> NSDiffableDataSourceSnapshot<Section, Item> {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.sorting, .chains])
        snapshot.appendItems([.sortByValue], toSection: .sorting)
        snapshot.appendItems(chains.map(Item.chain), toSection: .chains)
        return snapshot
    }

    private func setDisplayMode(_ displayMode: MChainDisplayMode) {
        guard configuration.displayMode != displayMode else { return }
        if isInteractivelyReordering {
            collectionView.cancelInteractiveMovement()
            isInteractivelyReordering = false
        }
        let capturedOrder = displayMode == .manual ? orderForEnteringManualMode() : nil
        configuration.setDisplayMode(displayMode, capturing: capturedOrder)
        applyCurrentSnapshot()

        let accountId = account.id
        AssetsAndActivityDataStore.update(accountId: accountId) { data in
            data.saveChainDisplayMode(displayMode, capturing: capturedOrder)
        }
    }

    private func setChain(_ chain: ApiChain, isVisible: Bool) {
        guard configuration.displayMode == .manual else {
            reconfigureChains()
            return
        }
        guard isVisible || visibleChains.count > 1 else {
            reconfigureChains()
            return
        }

        let automaticVisibility = automaticallyVisibleChains
        let automaticallyVisible = automaticVisibility.contains(chain)
        configuration.setVisible(
            chain,
            isVisible: isVisible,
            automaticallyVisible: automaticallyVisible
        )
        let updatedManualOrder = isVisible
            ? currentSnapshotChains.filter {
                configuration.isVisible($0, automaticallyVisibleChains: automaticVisibility)
            }
            : nil
        if let updatedManualOrder {
            configuration.setManualOrder(
                updatedManualOrder,
                automaticallyVisibleChains: automaticVisibility
            )
        }
        reconfigureChains()

        let accountId = account.id
        AssetsAndActivityDataStore.update(accountId: accountId) { data in
            data.saveChainVisible(
                chain,
                isVisible: isVisible,
                automaticallyVisible: automaticallyVisible
            )
            if let updatedManualOrder {
                data.saveChainOrder(
                    updatedManualOrder,
                    automaticallyVisibleChains: automaticVisibility
                )
            }
        }
    }

    private func didReorder(_ snapshot: NSDiffableDataSourceSnapshot<Section, Item>) {
        let automaticVisibility = automaticallyVisibleChains
        let reorderedChains = snapshot.itemIdentifiers(inSection: .chains).compactMap { item -> ApiChain? in
            guard case .chain(let chain) = item else { return nil }
            return chain
        }.filter { visibleChains.contains($0) }
        configuration.setManualOrder(
            reorderedChains,
            automaticallyVisibleChains: automaticVisibility
        )
        // UIKit is still committing this snapshot, so applying another one here would be reentrant.

        let accountId = account.id
        AssetsAndActivityDataStore.update(accountId: accountId) { data in
            data.saveChainOrder(
                reorderedChains,
                automaticallyVisibleChains: automaticVisibility
            )
        }
    }

    private func orderForEnteringManualMode() -> [ApiChain] {
        if configuration.manualOrder.isEmpty {
            return chains.filter {
                configuration.isVisible($0, automaticallyVisibleChains: automaticallyVisibleChains)
            }
        }
        return configuration.normalizedManualOrder(
            defaultOrder: defaultChains,
            automaticallyVisibleChains: automaticallyVisibleChains
        )
    }

    private func normalizeManualOrderForPresentation() {
        guard configuration.displayMode == .manual else { return }
        let automaticVisibility = automaticallyVisibleChains
        let normalizedOrder = configuration.normalizedManualOrder(
            defaultOrder: defaultChains,
            automaticallyVisibleChains: automaticVisibility
        )
        guard normalizedOrder != configuration.manualOrder else { return }

        configuration.setManualOrder(
            normalizedOrder,
            automaticallyVisibleChains: automaticVisibility
        )
        let accountId = account.id
        AssetsAndActivityDataStore.update(accountId: accountId) { data in
            data.saveChainOrder(
                normalizedOrder,
                automaticallyVisibleChains: automaticVisibility
            )
        }
    }

    private var currentSnapshotChains: [ApiChain] {
        dataSource.snapshot().itemIdentifiers(inSection: .chains).compactMap { item in
            guard case .chain(let chain) = item else { return nil }
            return chain
        }
    }

    private func handleReorderGesture(
        _ gesture: UILongPressGestureRecognizer,
        from cell: ChainVisibilityCell
    ) {
        guard configuration.displayMode == .manual else { return }
        let location = gesture.location(in: collectionView)

        switch gesture.state {
        case .began:
            guard let indexPath = collectionView.indexPath(for: cell),
                  dataSource.sectionIdentifier(for: indexPath.section) == .chains else {
                return
            }
            isInteractivelyReordering = collectionView.beginInteractiveMovementForItem(at: indexPath)
        case .changed:
            guard isInteractivelyReordering else { return }
            collectionView.updateInteractiveMovementTargetPosition(location)
        case .ended:
            guard isInteractivelyReordering else { return }
            collectionView.endInteractiveMovement()
            isInteractivelyReordering = false
        case .cancelled, .failed:
            guard isInteractivelyReordering else { return }
            collectionView.cancelInteractiveMovement()
            isInteractivelyReordering = false
        default:
            break
        }
    }

    private func applyCurrentSnapshot() {
        var snapshot = makeSnapshot()
        snapshot.reconfigureItems(snapshot.itemIdentifiers)
        dataSource.apply(snapshot, animatingDifferences: true)
    }

    private func reconfigureChains() {
        var snapshot = dataSource.snapshot()
        snapshot.reconfigureItems(snapshot.itemIdentifiers(inSection: .chains))
        dataSource.apply(snapshot, animatingDifferences: true)
    }

    private func refreshManualSnapshotPreservingOrder() {
        let existingOrder = currentSnapshotChains
        let modelOrder = chains
        let availableChains = Set(modelOrder)
        let retainedOrder = existingOrder.filter { availableChains.contains($0) }
        let retainedChains = Set(retainedOrder)
        let mergedOrder = retainedOrder + modelOrder.filter { !retainedChains.contains($0) }

        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.sorting, .chains])
        snapshot.appendItems([.sortByValue], toSection: .sorting)
        snapshot.appendItems(mergedOrder.map(Item.chain), toSection: .chains)
        let existingItems = Set(dataSource.snapshot().itemIdentifiers)
        snapshot.reconfigureItems(snapshot.itemIdentifiers.filter(existingItems.contains))
        dataSource.apply(snapshot, animatingDifferences: true)
    }

    private func reloadConfiguration() {
        let previousDisplayMode = configuration.displayMode
        configuration = AssetsAndActivityDataStore
            .data(accountId: account.id)?
            .chainDisplayConfiguration ?? MChainDisplayConfiguration()
        if configuration.displayMode == .value, isInteractivelyReordering {
            collectionView.cancelInteractiveMovement()
            isInteractivelyReordering = false
        }
        if configuration.displayMode == .value || previousDisplayMode != configuration.displayMode {
            applyCurrentSnapshot()
        } else {
            refreshManualSnapshotPreservingOrder()
        }
    }

    override func viewWillLayoutSubviews() {
        UIView.performWithoutAnimation {
            collectionView.frame = view.bounds
        }
        super.viewWillLayoutSubviews()
    }
}

extension ChainDisplaySettingsVC: UICollectionViewDelegate {
    func collectionView(
        _ collectionView: UICollectionView,
        targetIndexPathForMoveFromItemAt originalIndexPath: IndexPath,
        toProposedIndexPath proposedIndexPath: IndexPath
    ) -> IndexPath {
        guard let chainsSection = dataSource.snapshot().indexOfSection(.chains) else {
            return originalIndexPath
        }
        let lastChainIndex = currentSnapshotChains.count - 1
        guard lastChainIndex >= 0 else {
            return originalIndexPath
        }
        if proposedIndexPath.section < chainsSection {
            return IndexPath(item: 0, section: chainsSection)
        } else if proposedIndexPath.section > chainsSection {
            return IndexPath(item: lastChainIndex, section: chainsSection)
        } else {
            return IndexPath(
                item: min(proposedIndexPath.item, lastChainIndex),
                section: chainsSection
            )
        }
    }
}

extension ChainDisplaySettingsVC: WalletCoreData.EventsObserver {
    func walletCore(event: WalletCoreData.Event) {
        switch event {
        case .assetsAndActivityDataUpdated:
            reloadConfiguration()
        case .balanceChanged(let accountId) where accountId == account.id:
            configuration.displayMode == .value ? applyCurrentSnapshot() : refreshManualSnapshotPreservingOrder()
        case .tokensChanged:
            configuration.displayMode == .value ? applyCurrentSnapshot() : refreshManualSnapshotPreservingOrder()
        default:
            break
        }
    }
}
