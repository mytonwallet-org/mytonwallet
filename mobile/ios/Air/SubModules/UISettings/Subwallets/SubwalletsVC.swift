import Foundation
import Combine
import SwiftUI
import UIKit
import UIComponents
import WalletCore
import WalletContext

private let segmentedContentTopSpacing: CGFloat = 20
private let additionalTableContentTopInset: CGFloat = 36
private let bottomButtonInset: CGFloat = 28
private let bottomActionsContentInset: CGFloat = 160
private let searchPause: Duration = .seconds(1)
private let maxEmptyResultsInRow = 5
private let postHomeToastDelay: TimeInterval = 0.45
private let hiddenDerivationLabels: Set<String> = ["default", "phantom"]
private typealias AssetBalanceDisplayItem = (fiat: Double, text: String)

private struct SubwalletAddressData: Hashable {
    let chain: ApiChain
    let address: String
}

private struct SubwalletRowData: Hashable {
    let title: String
    let badge: String?
    let addresses: [SubwalletAddressData]
    let assetAmounts: String
    let totalBalance: String
}

private final class _NoInsetsCollectionView: UICollectionView {
    override var safeAreaInsets: UIEdgeInsets { .zero }
}

@MainActor
private final class SubwalletsActionsState: ObservableObject {
    @Published var canAddAllFoundSubwallets = false
}

final class SubwalletsVC: SettingsBaseVC {
    private let variantChains: [ApiChain]
    private let listViewController: SubwalletsListVC
    private let actionsState: SubwalletsActionsState

    init(password: String) {
        let account = AccountStore.account ?? DUMMY_ACCOUNT
        let accountContext = AccountContext(source: .current)
        let displayChains = accountContext.orderedChains.map(\.0)
        let actionsState = SubwalletsActionsState()

        self.variantChains = displayChains.filter { account.supportsSubwallets(on: $0) }
        self.actionsState = actionsState
        self.listViewController = SubwalletsListVC(
            password: password,
            displayChains: displayChains,
            actionsState: actionsState
        )

        super.init(nibName: nil, bundle: nil)
    }

    @MainActor required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.title = navigationTitle
        addCloseNavigationItemIfNeeded()

        setupViews()
        
        view.backgroundColor = .air.groupedBackground
        addCustomNavigationBarBackground(color: .air.groupedBackground)
    }

    private func setupViews() {
        addChild(listViewController)
        listViewController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(listViewController.view)
        NSLayoutConstraint.activate([
            listViewController.view.topAnchor.constraint(equalTo: view.topAnchor),
            listViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            listViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            listViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        listViewController.didMove(toParent: self)

        let bottomButton = HostingView {
            SubwalletsBottomActions(
                actionsState: actionsState,
                performAddAll: { [weak self] in
                    guard let self else { return }
                    try await self.listViewController.addAllFoundSubwallets()
                },
                performCreate: { [weak self] in
                    guard let self else { return }
                    try await self.listViewController.createSubwallet()
                }
            )
        }
        view.addSubview(bottomButton)
        NSLayoutConstraint.activate([
            bottomButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            bottomButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            bottomButton.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private var navigationTitle: String {
        guard variantChains.count == 1, let chain = variantChains.first else {
            return lang("Subwallets")
        }

        let key = "$chain_Subwallets"
        let localized = lang(key)
        guard localized != key else {
            return "\(chain.title) \(lang("Subwallets"))"
        }
        return String(format: localized, chain.title)
    }

    override func scrollToTop(animated: Bool) {
        listViewController.scrollToTop(animated: animated)
    }
}

final class SubwalletsListVC: SettingsBaseVC, UICollectionViewDelegate {
    private enum Section: Hashable {
        case currentWallet
        case subwallets
    }

    private enum Item: Hashable {
        case currentWallet
        case subwallet(Int)
        case noSubwallets
    }

    private let password: String
    private let accountId: String
    private let displayChains: [ApiChain]
    private let actionsState: SubwalletsActionsState

    private var mnemonic: [String] = []
    private var groups: [ApiGroupedWalletVariant] = []
    private var isLoading = false
    private var fetchTask: Task<Void, Never>?

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!

    fileprivate init(password: String, displayChains: [ApiChain], actionsState: SubwalletsActionsState) {
        let account = AccountStore.account ?? DUMMY_ACCOUNT

        self.password = password
        self.accountId = account.id
        self.displayChains = displayChains
        self.actionsState = actionsState

        super.init(nibName: nil, bundle: nil)
    }

    @MainActor required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        fetchTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        setupViews()
        configureDataSource()
        loadMnemonicAndStartSearch()
    }

    private var currentAccount: MAccount {
        AccountStore.get(accountId: accountId)
    }

    private var visibleGroups: [ApiGroupedWalletVariant] {
        groups.filter { $0.index != currentSubwalletIndex() }
    }

    private func setupViews() {
        view.backgroundColor = .air.groupedBackground

        var configuration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        configuration.backgroundColor = .clear
        configuration.headerMode = .supplementary
        configuration.footerMode = .supplementary
        let layout = UICollectionViewCompositionalLayout.list(using: configuration)

        collectionView = _NoInsetsCollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.delaysContentTouches = false
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.contentInset = .init(top: 0, left: 0, bottom: bottomActionsContentInset, right: 0)
        collectionView.verticalScrollIndicatorInsets = .init(top: 0, left: 0, bottom: bottomActionsContentInset, right: 0)

        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let resolvedTopInset = segmentedContentTopSpacing
            + additionalTableContentTopInset
            + (view.window?.safeAreaInsets.top ?? view.safeAreaInsets.top)
        if collectionView.contentInset.top != resolvedTopInset {
            collectionView.contentInset.top = resolvedTopInset
        }
        if collectionView.verticalScrollIndicatorInsets.top != resolvedTopInset {
            collectionView.verticalScrollIndicatorInsets.top = resolvedTopInset
        }
    }

    private func configureDataSource() {
        let headerRegistration = UICollectionView.SupplementaryRegistration<UICollectionViewCell>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] cell, _, indexPath in
            guard
                let self,
                let section = dataSource.sectionIdentifier(for: indexPath.section)
            else {
                return
            }

            self.configureHeaderCell(cell, section: section)
        }

        let footerRegistration = UICollectionView.SupplementaryRegistration<UICollectionViewCell>(
            elementKind: UICollectionView.elementKindSectionFooter
        ) { [weak self] cell, _, indexPath in
            guard let self,
                  let section = dataSource.sectionIdentifier(for: indexPath.section) else { return }

            self.configureFooterCell(cell, section: section)
        }

        let currentWalletRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, Void> { [weak self] cell, _, _ in
            guard let self else { return }
            let rowData = currentWalletRowData()
            cell.isUserInteractionEnabled = false
            cell.configurationUpdateHandler = { cell, _ in
                cell.contentConfiguration = UIHostingConfiguration {
                    SubwalletRowView(rowData: rowData)
                }
                .background(Color.air.groupedItem)
                .margins(.all, EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .minSize(height: 60)
            }
        }

        let subwalletRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, Int> { [weak self] cell, _, index in
            guard let self, let group = visibleGroups.first(where: { $0.index == index }) else {
                return
            }

            let rowData = rowData(for: group)
            cell.isUserInteractionEnabled = true
            cell.configurationUpdateHandler = { cell, state in
                cell.contentConfiguration = UIHostingConfiguration {
                    SubwalletRowView(rowData: rowData)
                }
                .background {
                    CellBackgroundHighlight(isHighlighted: state.isHighlighted)
                }
                .margins(.all, EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .minSize(height: 60)
            }
        }

        let emptyRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, Void> { cell, _, _ in
            cell.isUserInteractionEnabled = false
            cell.configurationUpdateHandler = { cell, _ in
                cell.contentConfiguration = UIHostingConfiguration {
                    SubwalletsEmptyView()
                }
                .background(Color.air.groupedItem)
                .margins(.all, EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .minSize(height: 52)
            }
        }

        dataSource = UICollectionViewDiffableDataSource<Section, Item>(collectionView: collectionView) {
            collectionView, indexPath, item in
            switch item {
            case .currentWallet:
                collectionView.dequeueConfiguredReusableCell(using: currentWalletRegistration, for: indexPath, item: ())
            case .subwallet(let index):
                collectionView.dequeueConfiguredReusableCell(using: subwalletRegistration, for: indexPath, item: index)
            case .noSubwallets:
                collectionView.dequeueConfiguredReusableCell(using: emptyRegistration, for: indexPath, item: ())
            }
        }

        dataSource.supplementaryViewProvider = { collectionView, kind, indexPath in
            switch kind {
            case UICollectionView.elementKindSectionHeader:
                collectionView.dequeueConfiguredReusableSupplementary(using: headerRegistration, for: indexPath)
            case UICollectionView.elementKindSectionFooter:
                collectionView.dequeueConfiguredReusableSupplementary(using: footerRegistration, for: indexPath)
            default:
                nil
            }
        }
    }

    private func configureHeaderCell(_ cell: UICollectionViewCell, section: Section) {
        switch section {
        case .currentWallet:
            cell.contentConfiguration = UIHostingConfiguration {
                VStack(alignment: .leading, spacing: 0) {
                    SubwalletsExplainerText(text: lang("$subwallets_hint"))
                    SubwalletsSectionTitle(title: lang("Current Wallet"))
                }
            }
            .background(Color.clear)
            .margins(.horizontal, 0)
            .margins(.vertical, 0)
        case .subwallets:
            cell.contentConfiguration = UIHostingConfiguration {
                SubwalletsSectionHeader(
                    isLoading: self.isLoading,
                    foundCount: self.visibleGroups.count
                )
            }
            .background(Color.clear)
            .margins(.horizontal, 0)
            .margins(.vertical, 0)
        }
    }

    private func configureFooterCell(_ cell: UICollectionViewCell, section: Section) {
        switch section {
        case .currentWallet:
            cell.contentConfiguration = UIHostingConfiguration {
                SubwalletsExplainerText(text: lang("$subwallets_created_wallets"), topPadding: 16)
            }
            .background(Color.clear)
            .margins(.horizontal, 0)
            .margins(.vertical, 0)
        case .subwallets:
            cell.contentConfiguration = nil
        }
    }

    private func refreshVisibleSupplementaryViews() {
        for indexPath in collectionView.indexPathsForVisibleSupplementaryElements(ofKind: UICollectionView.elementKindSectionHeader) {
            guard
                let section = dataSource.sectionIdentifier(for: indexPath.section),
                let cell = collectionView.supplementaryView(
                    forElementKind: UICollectionView.elementKindSectionHeader,
                    at: indexPath
                ) as? UICollectionViewCell
            else {
                continue
            }
            configureHeaderCell(cell, section: section)
        }

        for indexPath in collectionView.indexPathsForVisibleSupplementaryElements(ofKind: UICollectionView.elementKindSectionFooter) {
            guard
                let section = dataSource.sectionIdentifier(for: indexPath.section),
                let cell = collectionView.supplementaryView(
                    forElementKind: UICollectionView.elementKindSectionFooter,
                    at: indexPath
                ) as? UICollectionViewCell
            else {
                continue
            }
            configureFooterCell(cell, section: section)
        }
    }

    private func loadMnemonicAndStartSearch() {
        isLoading = true
        applySnapshot(animated: false)

        Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                mnemonic = try await Api.fetchMnemonic(accountId: accountId, password: password)
                startFetchingVariants()
            } catch {
                isLoading = false
                applySnapshot(animated: false)
                showAlert(error: error) { [weak self] in
                    self?.goBack()
                }
            }
        }
    }

    private func startFetchingVariants() {
        isLoading = true
        fetchTask?.cancel()
        fetchTask = Task { [weak self] in
            await self?.fetchVariantsLoop()
        }
        applySnapshot(animated: false)
    }

    private func fetchVariantsLoop() async {
        var page = 0
        var emptyResultsInRow = 0

        while !Task.isCancelled {
            let pageGroups: [ApiGroupedWalletVariant]
            let hasPositiveBalance: Bool

            do {
                pageGroups = try await Api.getWalletVariants(
                    accountId: accountId,
                    page: page,
                    mnemonic: mnemonic
                )

                hasPositiveBalance = pageGroups.contains { group in
                    group.byChain.contains { _, entry in
                        entry.balancesBySlug.contains { _, balance in balance > 0 }
                    }
                }

                await MainActor.run {
                    let existingIndices = Set(groups.map(\.index))
                    let newItems = pageGroups.filter { !existingIndices.contains($0.index) }
                    if !newItems.isEmpty {
                        groups.append(contentsOf: newItems)
                    }
                    applySnapshot(animated: !newItems.isEmpty)
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    applySnapshot(animated: false)
                    showAlert(error: error)
                }
                return
            }

            emptyResultsInRow = hasPositiveBalance ? 0 : (emptyResultsInRow + 1)
            page += 1

            if emptyResultsInRow >= maxEmptyResultsInRow {
                break
            }

            do {
                try await Task.sleep(for: searchPause)
            } catch {
                break
            }
        }

        await MainActor.run {
            isLoading = false
            applySnapshot(animated: false)
        }
    }

    private func applySnapshot(animated: Bool) {
        actionsState.canAddAllFoundSubwallets = !visibleGroups.isEmpty

        guard dataSource != nil else { return }

        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.currentWallet])
        snapshot.appendItems([.currentWallet], toSection: .currentWallet)

        snapshot.appendSections([.subwallets])
        if !visibleGroups.isEmpty {
            snapshot.appendItems(visibleGroups.map { .subwallet($0.index) }, toSection: .subwallets)
        } else if !isLoading {
            snapshot.appendItems([.noSubwallets], toSection: .subwallets)
        }

        dataSource.apply(snapshot, animatingDifferences: animated) { [weak self] in
            self?.refreshVisibleSupplementaryViews()
        }
    }

    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return false }

        switch item {
        case .currentWallet, .noSubwallets:
            return false
        case .subwallet:
            return true
        }
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        defer {
            collectionView.deselectItem(at: indexPath, animated: true)
        }

        guard
            case .subwallet(let index) = dataSource.itemIdentifier(for: indexPath),
            let group = visibleGroups.first(where: { $0.index == index })
        else {
            return
        }

        addSubwallet(group)
    }

    private func addSubwallet(_ group: ApiGroupedWalletVariant) {
        Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                let result = try await AccountStore.addSubWallet(group: group)
                AppActions.showHome(popToRoot: true)
                popToRootAfterDelay()
                showToastAfterReturningHome(message: lang(result.isNew ? "Subwallet Added" : "Subwallet Switched"), account: result.account)
            } catch {
                showAlert(error: error)
            }
        }
    }

    func createSubwallet() async throws {
        let account = try await AccountStore.createSubWallet(password: password)
        AppActions.showHome(popToRoot: true)
        popToRootAfterDelay()
        showToastAfterReturningHome(message: lang("Subwallet Created"), account: account)
    }

    func addAllFoundSubwallets() async throws {
        let groups = visibleGroups
        guard !groups.isEmpty else { return }

        let result = try await AccountStore.addAllFoundSubwallets(groups: groups)
        AppActions.showHome(popToRoot: true)
        popToRootAfterDelay()
        showToastAfterReturningHome(message: lang(result.isNew ? "Subwallet Added" : "Subwallet Switched"), account: result.account)
    }

    private func showToastAfterReturningHome(message: String, account: MAccount) {
        DispatchQueue.main.asyncAfter(deadline: .now() + postHomeToastDelay) {
            AppActions.showToast(style: .large, icon: .symbolImage("plus"), message: message, actionTitle: lang("Set Name")) {
                AppActions.showRenameAccount(accountId: account.id)
            }
        }
    }

    private func currentWalletRowData() -> SubwalletRowData {
        let chains = displayChains
        return SubwalletRowData(
            title: ".\(currentSubwalletIndex() + 1)",
            badge: currentDerivationBadge(),
            addresses: currentAddresses(chains: chains),
            assetAmounts: currentAssetBalancesText(chains: chains),
            totalBalance: currentTotalBalanceText(chains: chains)
        )
    }

    private func rowData(for group: ApiGroupedWalletVariant) -> SubwalletRowData {
        let chains = chains(for: group)
        let (assetAmounts, totalBalance) = subwalletBalanceDisplay(for: group, chains: chains)
        return SubwalletRowData(
            title: ".\(group.index + 1)",
            badge: derivationBadge(for: group),
            addresses: addresses(for: group, chains: chains),
            assetAmounts: assetAmounts,
            totalBalance: totalBalance
        )
    }

    private func currentSubwalletIndex() -> Int {
        displayChains
            .compactMap { currentAccount.derivation(chain: $0)?.index }
            .first ?? 0
    }

    private func currentDerivationBadge() -> String? {
        displayChains
            .compactMap { derivationBadgeText(currentAccount.derivation(chain: $0)?.label) }
            .first
    }

    private func derivationBadge(for group: ApiGroupedWalletVariant) -> String? {
        displayChains
            .compactMap { chain in
                derivationBadgeText(group.entry(for: chain)?.wallet.derivation?.label)
            }
            .first
    }

    private func derivationBadgeText(_ label: String?) -> String? {
        guard let label = label?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else { return nil }
        guard !hiddenDerivationLabels.contains(label.lowercased()) else { return nil }
        return label.prefix(1).uppercased() + String(label.dropFirst())
    }

    private func currentAddresses(chains: [ApiChain]) -> [SubwalletAddressData] {
        chains.compactMap { chain in
            guard let address = currentAccount.getAddress(chain: chain)?.nilIfEmpty else { return nil }
            return SubwalletAddressData(chain: chain, address: address)
        }
    }

    private func addresses(for group: ApiGroupedWalletVariant, chains: [ApiChain]) -> [SubwalletAddressData] {
        chains.compactMap { chain in
            guard let address = group.entry(for: chain)?.wallet.address.nilIfEmpty else { return nil }
            return SubwalletAddressData(chain: chain, address: address)
        }
    }

    private func chains(for group: ApiGroupedWalletVariant) -> [ApiChain] {
        displayChains.filter { group.entry(for: $0) != nil }
    }

    private func subwalletBalanceDisplay(
        for group: ApiGroupedWalletVariant,
        chains: [ApiChain]
    ) -> (assetAmounts: String, totalBalance: String) {
        var items: [AssetBalanceDisplayItem] = []

        for chain in chains {
            guard let entry = group.entry(for: chain) else { continue }

            for (slug, raw) in entry.balancesBySlug where raw > .zero {
                guard let token = TokenStore.getToken(slug: slug) else { continue }

                let tokenBalance = MTokenBalance(tokenSlug: token.slug, balance: raw, isStaking: false)
                items.append((
                    fiat: tokenBalance.toBaseCurrency ?? 0,
                    text: TokenAmount(raw, token).formatted(.defaultAdaptive)
                ))
            }
        }

        return assetBalanceDisplay(from: items)
    }

    private func currentAssetBalancesText(chains: [ApiChain]) -> String {
        assetBalanceDisplay(from: currentAssetBalanceItems(chains: chains)).assetAmounts
    }

    private func currentTotalBalanceText(chains: [ApiChain]) -> String {
        assetBalanceDisplay(from: currentAssetBalanceItems(chains: chains)).totalBalance
    }

    private func currentAssetBalanceItems(chains: [ApiChain]) -> [AssetBalanceDisplayItem] {
        let chainSet = Set(chains)
        return BalanceDataStore.for(accountId: accountId).walletTokensData?
            .walletTokens
            .compactMap { tokenBalance in
                guard
                    tokenBalance.balance > .zero,
                    let token = tokenBalance.token,
                    chainSet.contains(token.chain)
                else {
                    return nil
                }

                return (
                    fiat: tokenBalance.toBaseCurrency ?? 0,
                    text: TokenAmount(tokenBalance.balance, token).formatted(.defaultAdaptive)
                )
            } ?? []
    }

    private func assetBalanceDisplay(from items: [AssetBalanceDisplayItem]) -> (assetAmounts: String, totalBalance: String) {
        let sortedItems = items.sorted { lhs, rhs in
            if lhs.fiat == rhs.fiat {
                lhs.text < rhs.text
            } else {
                lhs.fiat > rhs.fiat
            }
        }
        let assetAmounts = sortedItems.map(\.text).joined(separator: ", ")
        let total = items.reduce(0) { partialResult, item in partialResult + item.fiat }
        let totalBalance = BaseCurrencyAmount.fromDouble(total, TokenStore.baseCurrency)
            .formatted(.baseCurrencyEquivalent, roundHalfUp: true)

        return (assetAmounts, totalBalance)
    }

    override func scrollToTop(animated: Bool) {
        collectionView?.setContentOffset(
            CGPoint(x: 0, y: -collectionView.adjustedContentInset.top),
            animated: animated
        )
    }
}

private struct SubwalletsExplainerText: View {
    let text: String
    var topPadding: CGFloat = 8

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .regular))
            .lineSpacing(2)
            .tracking(-0.078)
            .foregroundStyle(Color.air.secondaryLabel)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, topPadding)
            .padding(.bottom, 6)
    }
}

private struct SubwalletsSectionTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 17, weight: .semibold))
            .tracking(-0.43)
            .foregroundStyle(Color.air.secondaryLabel)
            .frame(maxWidth: .infinity, minHeight: 39, alignment: .bottomLeading)
            .padding(.horizontal, 16)
            .padding(.bottom, 9)
    }
}

private struct SubwalletsSectionHeader: View {
    let isLoading: Bool
    let foundCount: Int

    var body: some View {
        HStack(spacing: 10) {
            SubwalletsSectionTitle(title: lang("Subwallets"))

            SubwalletsSearchStatus(isLoading: isLoading, foundCount: foundCount)
                .padding(.trailing, 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SubwalletsSearchStatus: View {
    let isLoading: Bool
    let foundCount: Int

    var body: some View {
        HStack(spacing: 4) {
            if isLoading {
                WUIActivityIndicator(size: 14)

                Text(lang("Scanning..."))
            } else {
                Text(subwalletsFoundText(foundCount))
            }
        }
        .font(.system(size: 14, weight: .regular))
        .tracking(-0.15)
        .foregroundStyle(Color.air.secondaryLabel)
        .lineLimit(1)
        .frame(minHeight: 39, alignment: .bottomTrailing)
        .padding(.bottom, 10.5)
    }
}

private struct SubwalletsEmptyView: View {
    var body: some View {
        Text(lang("$subwallets_none"))
            .font(.system(size: 13, weight: .regular))
            .tracking(-0.078)
            .foregroundStyle(Color.air.secondaryLabel)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .center)
    }
}

private struct SubwalletRowView: View {
    let rowData: SubwalletRowData

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Text(rowData.title)
                        .font(.system(size: 16, weight: .medium))
                        .tracking(-0.43)
                        .foregroundStyle(Color.air.primaryLabel)
                        .lineLimit(1)

                    if let badge = rowData.badge?.nilIfEmpty {
                        Text(badge)
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(0.066)
                            .foregroundStyle(Color.air.secondaryLabel)
                            .frame(height: 14)
                            .padding(.horizontal, 3)
                            .background(Color.air.groupedBackground, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                }
                .frame(height: 22, alignment: .center)

                SubwalletAddressesView(addresses: rowData.addresses)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 0) {
                Text("≥ \(rowData.totalBalance)")
                    .font(.system(size: 16, weight: .regular))
                    .tracking(-0.43)
                    .foregroundStyle(Color.air.primaryLabel)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(rowData.assetAmounts)
                    .font(.system(size: 14, weight: .regular))
                    .tracking(-0.15)
                    .foregroundStyle(Color.air.secondaryLabel)
                    .lineLimit(1)
            }
            .frame(minWidth: 140, alignment: .trailing)
            .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .center)
    }
}

private struct SubwalletAddressesView: View {
    let addresses: [SubwalletAddressData]

    var body: some View {
        HStack(spacing: 3) {
            let displayAddresses = Array(addresses.prefix(3))
            let addressCount = displayAddresses.count
            let visibleAddressCount = min(2, addressCount)
            ForEach(Array(displayAddresses.enumerated()), id: \.offset) { index, address in
                SubwalletAddressView(
                    address: address,
                    itemsCount: addressCount,
                    showsAddress: index < visibleAddressCount,
                    showsComma: index < visibleAddressCount && index < addressCount - 1
                )
            }
        }
        .foregroundStyle(Color.air.secondaryLabel)
        .frame(height: 18, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
    }
}

private struct SubwalletAddressView: View {
    let address: SubwalletAddressData
    let itemsCount: Int
    let showsAddress: Bool
    let showsComma: Bool

    var body: some View {
        HStack(spacing: 0) {
            ChainIcon(address.chain)
                .imageScale(.small)

            if showsAddress {
                Text(formattedAddress + (showsComma ? "," : ""))
                    .tracking(-0.15)
                    .foregroundStyle(Color.air.secondaryLabel)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .font(.system(size: 14, weight: .regular))
        .frame(height: 18, alignment: .center)
    }

    private var formattedAddress: String {
        formatStartEndAddress(
            address.address,
            prefix: itemsCount == 1 ? 6 : 0,
            suffix: 6
        )
    }
}

private func subwalletsFoundText(_ count: Int) -> String {
    let localized = lang("$subwallets_found")
    guard !localized.isEmpty, localized != "$subwallets_found" else {
        return "Found: \(count)"
    }
    return String.localizedStringWithFormat(localized, count)
}

private struct SubwalletsBottomActions: View {
    @ObservedObject var actionsState: SubwalletsActionsState
    let performAddAll: @MainActor () async throws -> Void
    let performCreate: @MainActor () async throws -> Void

    @State private var isAddingAll = false
    @State private var isCreating = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.clear, .air.groupedBackground.opacity(0.9)],
                startPoint: .top,
                endPoint: .bottom
            )
            .padding(.top, -16)
            .ignoresSafeArea()

            VStack(spacing: 16) {
                Button(action: onAddAll) {
                    Label {
                        Text(lang("Add All Found"))
                    } icon: {
                        Image(systemName: "plus.rectangle.on.rectangle")
                    }
                }
                .buttonStyle(.airCompactCapsule)
                .environment(\.isLoading, isAddingAll)
                .disabled(!actionsState.canAddAllFoundSubwallets || isBusy)

                Button(action: onCreate) {
                    Label {
                        Text(lang("Create Subwallet"))
                    } icon: {
                        Image(systemName: "plus")
                    }
                }
                .buttonStyle(.airPrimary)
                .environment(\.isLoading, isCreating)
                .disabled(isBusy)
            }
            .padding(.horizontal, 30)
            .padding(.top, 16)
            .padding(.bottom, bottomButtonInset)
        }
    }

    private var isBusy: Bool {
        isAddingAll || isCreating
    }

    private func onAddAll() {
        guard actionsState.canAddAllFoundSubwallets, !isBusy else { return }
        isAddingAll = true
        Task { @MainActor in
            do {
                try await performAddAll()
            } catch {
                isAddingAll = false
                AppActions.showError(error: error)
            }
        }
    }

    private func onCreate() {
        guard !isBusy else { return }
        isCreating = true
        Task { @MainActor in
            do {
                try await performCreate()
            } catch {
                isCreating = false
                AppActions.showError(error: error)
            }
        }
    }
}

#if DEBUG
@available(iOS 18, *)
#Preview {
    UINavigationController(rootViewController: SubwalletsVC(password: "password"))
}
#endif
