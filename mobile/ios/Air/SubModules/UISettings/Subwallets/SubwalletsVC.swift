import Foundation
import SwiftUI
import UIKit
import UIComponents
import WalletCore
import WalletContext

private let segmentedContentTopSpacing: CGFloat = 20
private let additionalTableContentTopInset: CGFloat = 36
private let bottomButtonInset: CGFloat = 28
private let searchPause: Duration = .seconds(5)
private let maxEmptyResultsInRow = 5
private let postHomeToastDelay: TimeInterval = 0.45
private let hiddenDerivationLabels: Set<String> = ["default", "phantom"]

private struct SubwalletAddressData: Hashable {
    let chain: ApiChain
    let address: String
}

private struct SubwalletRowData: Hashable {
    let title: String
    let badge: String?
    let addresses: [SubwalletAddressData]
    let nativeAmount: String
    let totalBalance: String
}

private final class _NoInsetsCollectionView: UICollectionView {
    override var safeAreaInsets: UIEdgeInsets { .zero }
}

final class SubwalletsVC: SettingsBaseVC {
    private let variantChains: [ApiChain]
    private let listViewController: SubwalletsListVC

    init(password: String) {
        let account = AccountStore.account ?? DUMMY_ACCOUNT
        let accountContext = AccountContext(source: .current)
        let defaultChains = account.orderedChains.map(\.0)
        let displayChains = accountContext.orderedChains.map(\.0)

        self.variantChains = displayChains.filter { account.supportsSubwallets(on: $0) }
        self.listViewController = SubwalletsListVC(
            password: password,
            displayChains: displayChains,
            defaultChains: defaultChains
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
        configureNavigationItemWithTransparentBackground()
        addCustomNavigationBarBackground()
    }

    private func setupViews() {
        view.backgroundColor = .air.groupedBackground

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
            SubwalletsCreateButton(performCreate: { [weak self] in
                guard let self else { return }
                try await self.listViewController.createSubwallet()
            })
        }
        view.addSubview(bottomButton)
        NSLayoutConstraint.activate([
            bottomButton.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomButton.trailingAnchor.constraint(equalTo: view.trailingAnchor),
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
    private let defaultChains: [ApiChain]

    private var mnemonic: [String] = []
    private var groups: [ApiGroupedWalletVariant] = []
    private var isLoading = false
    private var fetchTask: Task<Void, Never>?

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!

    init(password: String, displayChains: [ApiChain], defaultChains: [ApiChain]) {
        let account = AccountStore.account ?? DUMMY_ACCOUNT

        self.password = password
        self.accountId = account.id
        self.displayChains = displayChains
        self.defaultChains = defaultChains

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
        groups
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
        collectionView.contentInset = .init(top: 0, left: 0, bottom: 96, right: 0)
        collectionView.verticalScrollIndicatorInsets = .init(top: 0, left: 0, bottom: 96, right: 0)

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

        let footerRegistration = UICollectionView.SupplementaryRegistration<UICollectionViewCell>(
            elementKind: UICollectionView.elementKindSectionFooter
        ) { [weak self] cell, _, indexPath in
            guard let self,
                  dataSource.sectionIdentifier(for: indexPath.section) == .currentWallet else {
                cell.contentConfiguration = nil
                return
            }

            cell.contentConfiguration = UIHostingConfiguration {
                SubwalletsExplainerText(text: lang("$subwallets_created_wallets"), topPadding: 16)
            }
            .background(Color.clear)
            .margins(.horizontal, 0)
            .margins(.vertical, 0)
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
                    group.byChain.contains { _, entry in entry.balance > 0 }
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
        if dataSource.snapshot().sectionIdentifiers.contains(.subwallets) {
            snapshot.reloadSections([.subwallets])
        }

        dataSource.apply(snapshot, animatingDifferences: animated)
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
                showToastAfterReturningHome(message: lang(result.isNew ? "Subwallet Added" : "Subwallet Switched"))
            } catch {
                showAlert(error: error)
            }
        }
    }

    func createSubwallet() async throws {
        _ = try await AccountStore.createSubWallet(password: password)
        AppActions.showToast(message: lang("Subwallet Created"))
        AppActions.showHome(popToRoot: true)
        popToRootAfterDelay()
    }

    private func showToastAfterReturningHome(message: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + postHomeToastDelay) {
            AppActions.showToast(message: message)
        }
    }

    private func currentWalletRowData() -> SubwalletRowData {
        let chains = displayChains
        return SubwalletRowData(
            title: ".\(currentSubwalletIndex() + 1)",
            badge: currentDerivationBadge(),
            addresses: currentAddresses(chains: chains),
            nativeAmount: currentNativeBalancesText(chains: chains),
            totalBalance: currentTotalBalanceText(chains: chains)
        )
    }

    private func rowData(for group: ApiGroupedWalletVariant) -> SubwalletRowData {
        let chains = chains(for: group)
        return SubwalletRowData(
            title: ".\(group.index + 1)",
            badge: derivationBadge(for: group),
            addresses: addresses(for: group, chains: chains),
            nativeAmount: nativeBalancesText(for: group, chains: chains),
            totalBalance: totalBalanceText(for: group, chains: chains)
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
        let defaultOrder = Dictionary(uniqueKeysWithValues: defaultChains.enumerated().map { offset, chain in
            (chain, offset)
        })

        return displayChains
            .filter { group.entry(for: $0) != nil }
            .sorted { lhs, rhs in
                let lhsValue = nativeBalanceValue(for: lhs, in: group)
                let rhsValue = nativeBalanceValue(for: rhs, in: group)

                if lhsValue != rhsValue {
                    return lhsValue > rhsValue
                }

                return defaultOrder[lhs, default: Int.max] < defaultOrder[rhs, default: Int.max]
            }
    }

    private func nativeBalanceValue(for chain: ApiChain, in group: ApiGroupedWalletVariant) -> Double {
        let balance = group.entry(for: chain)?.balance ?? .zero
        return MTokenBalance(tokenSlug: chain.nativeToken.slug, balance: balance, isStaking: false).toUsd ?? 0
    }

    private func currentNativeBalancesText(chains: [ApiChain]) -> String {
        return chains.prefix(2).map { chain in
            TokenAmount(currentNativeBalance(for: chain), chain.nativeToken).formatted(.defaultAdaptive)
        }.joined(separator: ", ")
    }

    private func currentTotalBalanceText(chains: [ApiChain]) -> String {
        let total = chains.reduce(0) { partialResult, chain in
            let balance = currentNativeBalance(for: chain)
            return partialResult + (MTokenBalance(tokenSlug: chain.nativeToken.slug, balance: balance, isStaking: false).toBaseCurrency ?? 0)
        }

        return BaseCurrencyAmount.fromDouble(total, TokenStore.baseCurrency)
            .formatted(.baseCurrencyEquivalent, roundHalfUp: true)
    }

    private func currentNativeBalance(for chain: ApiChain) -> BigInt {
        BalanceDataStore.for(accountId: accountId).walletTokensData?
            .walletTokens
            .first(where: { $0.tokenSlug == chain.nativeToken.slug && !$0.isStaking })?
            .balance ?? .zero
    }

    private func nativeBalancesText(for group: ApiGroupedWalletVariant, chains: [ApiChain]) -> String {
        chains.prefix(2).compactMap { chain in
            guard let entry = group.entry(for: chain) else { return nil }
            return TokenAmount(entry.balance, chain.nativeToken).formatted(.defaultAdaptive)
        }.joined(separator: ", ")
    }

    private func totalBalanceText(for group: ApiGroupedWalletVariant, chains: [ApiChain]) -> String {
        let total = chains.reduce(0) { partialResult, chain in
            guard let entry = group.entry(for: chain),
                  let balance = MTokenBalance(tokenSlug: chain.nativeToken.slug, balance: entry.balance, isStaking: false).toBaseCurrency else {
                return partialResult
            }
            return partialResult + balance
        }

        return BaseCurrencyAmount.fromDouble(total, TokenStore.baseCurrency)
            .formatted(.baseCurrencyEquivalent, roundHalfUp: true)
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
            .layoutPriority(1)
            .clipped()

            VStack(alignment: .trailing, spacing: 0) {
                Text("≥ \(rowData.totalBalance)")
                    .font(.system(size: 16, weight: .regular))
                    .tracking(-0.43)
                    .foregroundStyle(Color.air.primaryLabel)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(rowData.nativeAmount)
                    .font(.system(size: 14, weight: .regular))
                    .tracking(-0.15)
                    .foregroundStyle(Color.air.secondaryLabel)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .multilineTextAlignment(.trailing)
            .fixedSize(horizontal: true, vertical: false)
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
            ChainIcon(address.chain, font: .system(size: 14, weight: .regular))

            if showsAddress {
                Text(formattedAddress + (showsComma ? "," : ""))
                    .font(.system(size: 14, weight: .regular))
                    .tracking(-0.15)
                    .foregroundStyle(Color.air.secondaryLabel)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
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

private struct SubwalletsCreateButton: View {
    let performCreate: @MainActor () async throws -> Void

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

            Button(action: onCreate) {
                Label {
                    Text(lang("Create Subwallet"))
                } icon: {
                    Image(systemName: "plus")
                }
            }
            .buttonStyle(.airPrimary)
            .environment(\.isLoading, isCreating)
            .padding(.horizontal, 30)
            .padding(.top, 16)
            .padding(.bottom, bottomButtonInset)
        }
    }

    private func onCreate() {
        guard !isCreating else { return }
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
