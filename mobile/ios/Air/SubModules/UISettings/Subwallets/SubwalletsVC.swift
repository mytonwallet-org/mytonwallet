import Foundation
import SwiftUI
import UIKit
import UIComponents
import WalletCore
import WalletContext

private let maxSegmentedWidth: CGFloat = 580
private let segmentedContainerHeight: CGFloat = 54
private let segmentedContentTopSpacing: CGFloat = 20
private let additionalTableContentTopInset: CGFloat = 36
private let bottomButtonInset: CGFloat = 28
private let searchPause: Duration = .seconds(5)
private let maxEmptyResultsInRow = 5

private struct SubwalletRowData: Hashable {
    let title: String
    let subtitle: String
    let label: String?
    let tokenAmount: String
    let totalBalance: String
}

private enum SubwalletsStatusState: Hashable {
    case scanning
    case noResults
}

final class SubwalletsVC: SettingsBaseVC, WSegmentedController.Delegate {
    private let password: String
    private let availableChains: [ApiChain]
    private let tabViewControllers: [SubwalletsListVC]

    private var segmentedController: WSegmentedController!
    private var segmentedWidthConstraint: NSLayoutConstraint?
    private var segmentedControlContainer: UIView?

    init(password: String) {
        let account = AccountStore.account ?? DUMMY_ACCOUNT
        let chains = account.orderedChains.map(\.0).filter { account.supportsSubwallets(on: $0) }
        let topInset = chains.count > 1 ? segmentedContainerHeight : 0

        self.password = password
        self.availableChains = chains
        self.tabViewControllers = chains.map {
            SubwalletsListVC(password: password, chain: $0, topInset: topInset)
        }

        super.init(nibName: nil, bundle: nil)
    }

    @MainActor required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.title = lang("Subwallets")
        addCloseNavigationItemIfNeeded()

        setupViews()
        configureNavigationItemWithTransparentBackground()
        addCustomNavigationBarBackground(
            constant: availableChains.count > 1
                ? segmentedContainerHeight + segmentedContentTopSpacing
                : 6
        )
        if let segmentedControlContainer {
            view.bringSubviewToFront(segmentedControlContainer)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        segmentedWidthConstraint?.constant = min(maxSegmentedWidth, view.bounds.width - 32)
    }

    private func setupViews() {
        view.backgroundColor = .air.groupedBackground

        let items = zip(availableChains, tabViewControllers).map { chain, viewController in
            SegmentedControlItem(
                id: chain.rawValue,
                title: chain.title,
                viewController: viewController
            )
        }

        segmentedController = WSegmentedController(
            items: items,
            defaultItemId: availableChains.first?.rawValue,
            barHeight: 44,
            animationSpeed: .slow,
            secondaryTextColor: UIColor.secondaryLabel,
            capsuleFillColor: .airBundle("DarkCapsuleColor"),
            delegate: self
        )
        segmentedController.translatesAutoresizingMaskIntoConstraints = false
        segmentedController.backgroundColor = .clear
        segmentedController.blurView.isHidden = true
        segmentedController.separator.isHidden = true
        segmentedController.scrollView.isScrollEnabled = availableChains.count > 1

        view.addSubview(segmentedController)
        NSLayoutConstraint.activate([
            segmentedController.topAnchor.constraint(equalTo: view.topAnchor),
            segmentedController.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            segmentedController.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            segmentedController.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        if availableChains.count > 1 {
            let segmentedControl = segmentedController.segmentedControl!
            segmentedControl.removeFromSuperview()
            segmentedControl.translatesAutoresizingMaskIntoConstraints = false

            let container = UIView()
            container.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(segmentedControl)
            segmentedControlContainer = container

            let widthConstraint = container.widthAnchor.constraint(
                equalToConstant: min(maxSegmentedWidth, view.bounds.width - 32)
            )
            segmentedWidthConstraint = widthConstraint

            NSLayoutConstraint.activate([
                segmentedControl.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
                segmentedControl.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                segmentedControl.widthAnchor.constraint(equalTo: container.widthAnchor),
                widthConstraint,
                container.heightAnchor.constraint(equalToConstant: segmentedContainerHeight),
            ])

            view.addSubview(container)
            NSLayoutConstraint.activate([
                container.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                container.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            ])
        } else {
            segmentedController.segmentedControl.removeFromSuperview()
        }

        let bottomButton = HostingView {
            SubwalletsCreateButton { [weak self] in
                self?.createSubwalletPressed()
            }
        }
        view.addSubview(bottomButton)
        NSLayoutConstraint.activate([
            bottomButton.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomButton.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomButton.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func createSubwalletPressed() {
        guard let selectedIndex = segmentedController?.selectedIndex,
              tabViewControllers.indices.contains(selectedIndex) else {
            return
        }

        tabViewControllers[selectedIndex].createSubwallet()
    }

    override func scrollToTop(animated: Bool) {
        segmentedController?.scrollToTop(animated: animated)
    }
}

final class SubwalletsListVC: SettingsBaseVC, WSegmentedControllerContent, UICollectionViewDelegate {
    private enum Section: Hashable {
        case currentWallet
        case subwallets
        case status
    }

    private enum Item: Hashable {
        case currentWallet
        case subwallet(String)
        case status(SubwalletsStatusState)
    }

    let chain: ApiChain

    private let password: String
    private let accountId: String
    private let network: ApiNetwork
    private let topInset: CGFloat

    private var mnemonic: [String] = []
    private var variants: [ApiWalletVariant] = []
    private var isLoading = false
    private var fetchTask: Task<Void, Never>?

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!

    var onScroll: ((CGFloat) -> Void)?
    var onScrollStart: (() -> Void)?
    var onScrollEnd: (() -> Void)?
    var scrollingView: UIScrollView? { collectionView }

    init(password: String, chain: ApiChain, topInset: CGFloat) {
        let account = AccountStore.account ?? DUMMY_ACCOUNT

        self.password = password
        self.chain = chain
        self.accountId = account.id
        self.network = account.network
        self.topInset = topInset

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
        applySnapshot(animated: false)
        loadMnemonicAndStartSearch()
    }

    private var currentAccount: MAccount {
        AccountStore.get(accountId: accountId)
    }

    private var currentAddress: String {
        currentAccount.getAddress(chain: chain) ?? ""
    }

    private var visibleVariants: [ApiWalletVariant] {
        variants.filter { $0.balance > 0 && $0.wallet.address != currentAddress }
    }

    private func setupViews() {
        view.backgroundColor = .air.groupedBackground

        var configuration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        configuration.backgroundColor = .clear
        configuration.headerMode = .supplementary
        configuration.footerMode = .supplementary
        let layout = UICollectionViewCompositionalLayout.list(using: configuration)

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
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
        let resolvedTopInset = topInset
            + segmentedContentTopSpacing
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
                var content = UIListContentConfiguration.groupedHeader()
                content.text = lang("Current Wallet")
                cell.contentConfiguration = content
            case .subwallets:
                cell.contentConfiguration = UIHostingConfiguration {
                    SubwalletsSectionHeader(isLoading: self.isLoading)
                }
                .background(Color.clear)
                .margins(.horizontal, 20)
                .margins(.vertical, 8)
            case .status:
                cell.contentConfiguration = nil
            }
        }

        let footerRegistration = UICollectionView.SupplementaryRegistration<UICollectionViewCell>(
            elementKind: UICollectionView.elementKindSectionFooter
        ) { [weak self] cell, _, indexPath in
            guard let self,
                  dataSource.sectionIdentifier(for: indexPath.section) == .subwallets,
                  !visibleVariants.isEmpty else {
                cell.contentConfiguration = nil
                return
            }

            cell.contentConfiguration = UIHostingConfiguration {
                SubwalletsFooterView()
            }
            .margins(.horizontal, 20)
            .margins(.vertical, 8)
        }

        let currentWalletRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, Void> { [weak self] cell, _, _ in
            guard let self else { return }
            let rowData = currentWalletRowData()
            cell.configurationUpdateHandler = { cell, _ in
                cell.contentConfiguration = UIHostingConfiguration {
                    SubwalletRowView(rowData: rowData)
                }
                .background(Color.air.groupedItem)
                .margins(.all, EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20))
                .minSize(height: 62)
            }
        }

        let subwalletRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, String> { [weak self] cell, _, address in
            guard let self, let variant = visibleVariants.first(where: { $0.wallet.address == address }) else {
                return
            }

            let rowData = rowData(for: variant)
            cell.configurationUpdateHandler = { cell, state in
                cell.contentConfiguration = UIHostingConfiguration {
                    SubwalletRowView(rowData: rowData)
                }
                .background {
                    CellBackgroundHighlight(isHighlighted: state.isHighlighted)
                }
                .margins(.all, EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20))
                .minSize(height: 62)
            }
        }

        let statusRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, SubwalletsStatusState> { cell, _, state in
            cell.isUserInteractionEnabled = false
            cell.configurationUpdateHandler = { cell, _ in
                cell.backgroundConfiguration = UIBackgroundConfiguration.clear()
                cell.backgroundColor = .clear
                cell.contentConfiguration = UIHostingConfiguration {
                    SubwalletsStatusView(state: state)
                }
                .background(Color.clear)
                .margins(.horizontal, 20)
                .margins(.vertical, 16)
            }
        }

        dataSource = UICollectionViewDiffableDataSource<Section, Item>(collectionView: collectionView) {
            collectionView, indexPath, item in
            switch item {
            case .currentWallet:
                collectionView.dequeueConfiguredReusableCell(using: currentWalletRegistration, for: indexPath, item: ())
            case .subwallet(let address):
                collectionView.dequeueConfiguredReusableCell(using: subwalletRegistration, for: indexPath, item: address)
            case .status(let state):
                collectionView.dequeueConfiguredReusableCell(using: statusRegistration, for: indexPath, item: state)
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
            let pageVariants: [ApiWalletVariant]
            let hasPositiveBalance: Bool

            do {
                pageVariants = try await Api.getWalletVariants(
                    network: network,
                    chain: chain,
                    accountId: accountId,
                    page: page,
                    isTestnetSubwalletId: chain == .ton && network == .testnet ? true : nil,
                    mnemonic: mnemonic
                )

                hasPositiveBalance = pageVariants.contains { $0.balance > 0 }

                await MainActor.run {
                    let existingAddresses = Set(variants.map(\.wallet.address))
                    let newItems = pageVariants.filter { !existingAddresses.contains($0.wallet.address) }
                    if !newItems.isEmpty {
                        variants.append(contentsOf: newItems)
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

        if !visibleVariants.isEmpty {
            snapshot.appendSections([.subwallets])
            snapshot.appendItems(visibleVariants.map { .subwallet($0.wallet.address) }, toSection: .subwallets)
        } else {
            snapshot.appendSections([.status])
            snapshot.appendItems([.status(isLoading ? .scanning : .noResults)], toSection: .status)
        }

        dataSource.apply(snapshot, animatingDifferences: animated)
    }

    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return false }

        switch item {
        case .currentWallet, .status:
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
            case .subwallet(let address) = dataSource.itemIdentifier(for: indexPath),
            let variant = visibleVariants.first(where: { $0.wallet.address == address })
        else {
            return
        }

        presentAddSubwalletAlert(for: variant)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        onScroll?(scrollView.contentOffset.y + scrollView.adjustedContentInset.top)
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        onScrollStart?()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            onScrollEnd?()
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        onScrollEnd?()
    }

    private func presentAddSubwalletAlert(for variant: ApiWalletVariant) {
        let alert = UIAlertController(
            title: lang("Add Subwallet"),
            message: formatStartEndAddress(variant.wallet.address),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: lang("Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: lang("Create New Wallet"), style: .default) { [weak self] _ in
            self?.addSubwallet(variant, isReplace: false)
        })

        let replaceAction = UIAlertAction(title: lang("Replace in this wallet"), style: .default) { [weak self] _ in
            self?.addSubwallet(variant, isReplace: true)
        }
        alert.addAction(replaceAction)
        alert.preferredAction = replaceAction
        present(alert, animated: true)
    }

    private func addSubwallet(_ variant: ApiWalletVariant, isReplace: Bool) {
        Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                _ = try await AccountStore.addSubWallet(chain: chain, newWallet: variant.wallet, isReplace: isReplace)
                AppActions.showToast(message: lang(isReplace ? "Subwallet Switched" : "Subwallet Added"))
                AppActions.showHome(popToRoot: true)
                popToRootAfterDelay()
            } catch {
                showAlert(error: error)
            }
        }
    }

    func createSubwallet() {
        Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                _ = try await AccountStore.createSubWallet(chain: chain, password: password)
                AppActions.showToast(message: lang("Subwallet Created"))
                AppActions.showHome(popToRoot: true)
                popToRootAfterDelay()
            } catch {
                showAlert(error: error)
            }
        }
    }

    private func currentWalletRowData() -> SubwalletRowData {
        let title: String
        if chain == .ton {
            title = currentAccount.currentTonWalletVersion ?? ApiTonWalletVersion.W5.rawValue
        } else {
            title = currentWalletDerivation()
                .map { "#\($0.index + 1)" }
                ?? "#1"
        }

        return SubwalletRowData(
            title: title,
            subtitle: formatStartEndAddress(currentAddress),
            label: currentWalletLabel(),
            tokenAmount: nativeBalanceText(),
            totalBalance: totalBalanceText()
        )
    }

    private func rowData(for variant: ApiWalletVariant) -> SubwalletRowData {
        let title: String
        let label: String?

        switch variant.metadata {
        case .version(let version):
            title = version.rawValue
            label = nil
        case .path(_, let variantLabel):
            title = "#\((variant.wallet.derivation?.index ?? 0) + 1)"
            label = variantLabel
        }

        let token = chain.nativeToken
        let tokenAmount = TokenAmount(variant.balance, token).formatted(.defaultAdaptive)
        let totalBalance: String
        if let balance = MTokenBalance(tokenSlug: token.slug, balance: variant.balance, isStaking: false).toBaseCurrency {
            totalBalance = BaseCurrencyAmount.fromDouble(balance, TokenStore.baseCurrency)
                .formatted(.baseCurrencyEquivalent, roundHalfUp: true)
        } else {
            totalBalance = BaseCurrencyAmount.fromDouble(0, TokenStore.baseCurrency)
                .formatted(.baseCurrencyEquivalent, roundHalfUp: true)
        }

        return SubwalletRowData(
            title: title,
            subtitle: formatStartEndAddress(variant.wallet.address),
            label: label,
            tokenAmount: tokenAmount,
            totalBalance: totalBalance
        )
    }

    private func nativeBalanceText() -> String {
        let rawBalance = BalanceDataStore.for(accountId: accountId).walletTokensData?
            .walletTokens
            .first(where: { $0.tokenSlug == chain.nativeToken.slug && !$0.isStaking })?
            .balance ?? .zero

        return TokenAmount(rawBalance, chain.nativeToken).formatted(.defaultAdaptive)
    }

    private func totalBalanceText() -> String {
        let total = BalanceDataStore.for(accountId: accountId).balanceTotals?
            .totalBalanceUsdByChain[chain] ?? 0

        return BaseCurrencyAmount.fromDouble(total, TokenStore.baseCurrency)
            .formatted(.baseCurrencyEquivalent, roundHalfUp: true)
    }

    private func currentWalletLabel() -> String? {
        currentAccount.derivation(chain: chain)?.label
    }

    private func currentWalletDerivation() -> ApiDerivation? {
        currentAccount.derivation(chain: chain)
    }

    override func scrollToTop(animated: Bool) {
        collectionView?.setContentOffset(
            CGPoint(x: 0, y: -collectionView.adjustedContentInset.top),
            animated: animated
        )
    }

    func calculateHeight(isHosted: Bool) -> CGFloat { 0 }
}

private struct SubwalletsSectionHeader: View {
    let isLoading: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(lang("Subwallets"))
                .airFont15h18(weight: .medium)
                .foregroundStyle(Color.air.primaryLabel)

            if isLoading {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)

                    Text(lang("Scanning..."))
                        .font13()
                        .foregroundStyle(Color.air.secondaryLabel)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SubwalletsFooterView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(lang("You have tokens on other subwallets. Each subwallet has its own address."))
                .font13()
                .foregroundStyle(Color.air.secondaryLabel)

            Text(lang("You can create a new subwallet if you need another address on the same recovery phrase."))
                .font13()
                .foregroundStyle(Color.air.secondaryLabel)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SubwalletsStatusView: View {
    let state: SubwalletsStatusState

    var body: some View {
        VStack(spacing: 10) {
            switch state {
            case .scanning:
                WUIAnimatedSticker("duck_wait", size: 100, loop: true)

                Text(lang("Scanning for subwallets..."))
                    .font17h22()
                    .foregroundStyle(Color.air.primaryLabel)

                Text(lang("This process may take up to a minute. Please wait."))
                    .airFont15h18(weight: .regular)
                    .foregroundStyle(Color.air.secondaryLabel)

                Text(lang("You can create a new subwallet if you need another address on the same recovery phrase."))
                    .airFont15h18(weight: .regular)
                    .foregroundStyle(Color.air.secondaryLabel)
            case .noResults:
                WUIAnimatedSticker("duck_no-data", size: 100, loop: false)

                Text(lang("No existing subwallets found"))
                    .font17h22()
                    .foregroundStyle(Color.air.primaryLabel)

                Text(lang("You can create a new subwallet if you need another address on the same recovery phrase."))
                    .airFont15h18(weight: .regular)
                    .foregroundStyle(Color.air.secondaryLabel)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 20)
    }
}

private struct SubwalletRowView: View {
    let rowData: SubwalletRowData

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(rowData.title)
                        .font17h22()

                    if let label = rowData.label?.nilIfEmpty {
                        Text(label)
                            .font13()
                            .foregroundStyle(Color.air.secondaryLabel)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.air.groupedItem, in: Capsule())
                    }
                }

                Text(rowData.subtitle)
                    .airFont15h18(weight: .regular)
                    .foregroundStyle(Color.air.secondaryLabel)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 2) {
                Text(rowData.tokenAmount)
                    .airFont15h18(weight: .regular)
                    .foregroundStyle(Color.air.secondaryLabel)

                Text("≈ \(rowData.totalBalance)")
                    .airFont15h18(weight: .regular)
                    .foregroundStyle(Color.air.secondaryLabel)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SubwalletsCreateButton: View {
    let onCreate: () -> Void

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
            .padding(.horizontal, 30)
            .padding(.top, 16)
            .padding(.bottom, bottomButtonInset)
        }
    }
}

#if DEBUG
@available(iOS 18, *)
#Preview {
    UINavigationController(rootViewController: SubwalletsVC(password: "password"))
}
#endif
