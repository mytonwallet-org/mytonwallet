
import UIKit
import UIComponents
import WalletCore
import WalletContext
import Dependencies

private let log = Log("WalletTokens")

public final class WalletTokensVC: WViewController, WalletCoreData.EventsObserver, UITableViewDelegate, Sendable, WSegmentedControllerContent {

    // MARK: - Diffable Data Source Types

    private enum Section: Hashable {
        case main
        case seeAll
    }

    private enum Item: Hashable {
        case token(accountId: String, tokenSlug: String, isStaking: Bool)
        case placeholder(Int)
        case seeAll
    }

    // MARK: - Properties

    private let compactMode: Bool
    @AccountContext var account: MAccount

    private var tableView: UITableView!
    private var dataSource: UITableViewDiffableDataSource<Section, Item>!

    private var walletTokens: [MTokenBalance]?
    private var allTokensCount = 0
    private var placeholderCount = 4
    private var animatedAmounts = true

    public var onHeightChanged: ((_ animated: Bool) -> Void)?

    private let queue = DispatchQueue(label: "WalletTokensVC", qos: .userInitiated)

    private var shouldShowSeeAll: Bool {
        if let walletTokens {
            return allTokensCount > walletTokens.count
        }
        return false
    }

    public var calculatedHeight: CGFloat {
        let itemCount = CGFloat(walletTokens?.count ?? placeholderCount)
        guard itemCount > 0 else { return 0 }
        return itemCount * WalletTokenCell.defaultHeight + (shouldShowSeeAll ? WalletSeeAllCell.defaultHeight : 0)
    }

    public var visibleCells: [UITableViewCell] {
        tableView?.visibleCells ?? []
    }

    // MARK: - Init

    public init(accountSource: AccountSource, compactMode: Bool) {
        self._account = AccountContext(source: accountSource)
        self.compactMode = compactMode
        super.init(nibName: nil, bundle: nil)
    }

    @MainActor required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        configureDataSource()
        updateWalletTokens(animated: false)
        WalletCoreData.add(eventObserver: self)
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        onHeightChanged?(false)
    }

    public override func updateTheme() {
    }

    // MARK: - Setup

    private func setupViews() {
        view.backgroundColor = .clear
        
        tableView = UITableView(frame: .zero, style: .plain)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .clear
        tableView.delegate = self
        tableView.separatorStyle = .none
        tableView.delaysContentTouches = false
        tableView.showsVerticalScrollIndicator = false
        tableView.contentInsetAdjustmentBehavior = .scrollableAxes

        if compactMode {
            tableView.bounces = false
            tableView.isScrollEnabled = false
        }

        tableView.register(compactMode ? WalletTokenCell.self : AssetsWalletTokenCell.self, forCellReuseIdentifier: "WalletToken")
        tableView.register(ActivityCell.self, forCellReuseIdentifier: "Placeholder")
        tableView.register(WalletSeeAllCell.self, forCellReuseIdentifier: "SeeAll")

        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func configureDataSource() {
        dataSource = UITableViewDiffableDataSource<Section, Item>(tableView: tableView) { [unowned self] tableView, indexPath, item in
            switch item {
            case .token(_, let slug, let isStaked):
                let account = self.account
                let cell = tableView.dequeueReusableCell(withIdentifier: "WalletToken", for: indexPath) as! WalletTokenCell
                guard let walletToken = walletTokens?.first(where: { $0.tokenSlug == slug && $0.isStaking == isStaked }) else {
                    log.fault("inconsistent state")
                    return cell
                }
                let badgeContent = getBadgeContent(accountContext: _account, slug: slug, isStaking: isStaked)
                let walletTokensCount = walletTokens?.count ?? 0
                cell.configure(
                    with: walletToken,
                    isLast: indexPath.row == walletTokensCount - 1,
                    animated: animatedAmounts,
                    badgeContent: badgeContent,
                    network: account.network,
                    isMultichain: account.isMultichain,
                    onSelect: { [weak self] in
                        self?.didSelectToken(walletToken)
                    }
                )
                return cell

            case .placeholder:
                let cell = tableView.dequeueReusableCell(withIdentifier: "Placeholder", for: indexPath) as! ActivityCell
                cell.configureSkeleton()
                return cell

            case .seeAll:
                let cell = tableView.dequeueReusableCell(withIdentifier: "SeeAll", for: indexPath) as! WalletSeeAllCell
                cell.configure(delegate: self)
                return cell
            }
        }
        dataSource.defaultRowAnimation = .fade
    }

    private func applySnapshot(animated: Bool) {
        let accountId = self.account.id
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.main])
        
        if let walletTokens {
            snapshot.appendItems(walletTokens.map { .token(accountId: accountId, tokenSlug: $0.tokenSlug, isStaking: $0.isStaking) })
        } else {
            snapshot.appendItems((0..<placeholderCount).map(Item.placeholder))
        }

        if shouldShowSeeAll {
            snapshot.appendSections([.seeAll])
            snapshot.appendItems([.seeAll])
        }

        snapshot.reconfigureItems(snapshot.itemIdentifiers(inSection: .main))
        queue.async { [dataSource] in
            dataSource.apply(snapshot, animatingDifferences: animated)
        }
    }

    // MARK: - Data Updates

    private func updateWalletTokens(animated: Bool) {
        animatedAmounts = animated
        if let data = $account.balanceData {
            var allTokens = data.walletStaked + data.walletTokens
            let count = allTokens.count
            if compactMode {
                allTokens = Array(allTokens.prefix(5))
            }
            walletTokens = allTokens
            allTokensCount = count
            placeholderCount = 0
        } else {
            walletTokens = nil
            allTokensCount = 0
            placeholderCount = 4
        }

        applySnapshot(animated: animated)
        onHeightChanged?(animated)
    }

    private func reloadStakeCells(animated: Bool) {
        for cell in tableView.visibleCells {
            if let cell = cell as? WalletTokenCell, let walletToken = cell.walletToken {
                let badgeContent = getBadgeContent(accountContext: _account, slug: walletToken.tokenSlug, isStaking: walletToken.isStaking)
                cell.configureBadge(badgeContent: badgeContent)
            }
        }
    }

    private func reconfigureAllRows(animated: Bool) {
        var snapshot = dataSource.snapshot()
        snapshot.reconfigureItems(snapshot.itemIdentifiers(inSection: .main))
        queue.async { [dataSource] in
            dataSource.apply(snapshot, animatingDifferences: animated)
        }
    }

    public func switchAcccountTo(accountId: String, animated: Bool) {
        $account.accountId = accountId
        updateWalletTokens(animated: animated)
    }

    // MARK: - WalletCoreData.EventsObserver

    nonisolated public func walletCore(event: WalletCore.WalletCoreData.Event) {
        MainActor.assumeIsolated {
            switch event {
            case .accountChanged:
                if $account.source == .current {
                    updateWalletTokens(animated: false)
                    reloadStakeCells(animated: false)
                }

            case .stakingAccountData(let data):
                if data.accountId == self.account.id {
                    reloadStakeCells(animated: true)
                }

            case .tokensChanged:
                reconfigureAllRows(animated: true)

            case .balanceChanged(let accountId, _):
                log.info("balanceChanged \(accountId, .public) self.account.id=\(self.account.id, .public)")
                if accountId == self.account.id {
                    updateWalletTokens(animated: true)
                }

            default:
                break
            }
        }
    }

    // MARK: - Token Selection

    private func didSelectToken(_ walletToken: MTokenBalance) {
        let slug = walletToken.tokenSlug
        if slug == STAKED_TON_SLUG || slug == STAKED_MYCOIN_SLUG || slug == TON_TSUSDE_SLUG || walletToken.isStaking {
            goToStakedPage(slug: slug)
        } else {
            didSelect(slug: slug)
        }
    }

    private func didSelect(slug: String?) {
        guard let slug, let token = TokenStore.tokens[slug] else { return }
        AppActions.showToken(accountSource: $account.source, token: token, isInModal: !compactMode)
    }

    private func goToStakedPage(slug: String) {
        let tokenSlug: String? = switch slug {
        case TONCOIN_SLUG, STAKED_TON_SLUG:
            TONCOIN_SLUG
        case MYCOIN_SLUG, STAKED_MYCOIN_SLUG:
            MYCOIN_SLUG
        case TON_USDE_SLUG, TON_TSUSDE_SLUG:
            TON_USDE_SLUG
        default:
            nil
        }
        AppActions.showEarn(tokenSlug: tokenSlug)
    }

    // MARK: - UITableViewDelegate

    public func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        switch indexPath.section {
        case 0:
            WalletTokenCell.defaultHeight
        default:
            WalletSeeAllCell.defaultHeight
        }
    }

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        onScroll?(scrollView.contentOffset.y + scrollView.contentInset.top)
    }

    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        onScrollStart?()
    }

    public func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        onScrollEnd?()
    }

    // MARK: - WSegmentedControllerContent

    public var onScroll: ((CGFloat) -> Void)?
    public var onScrollStart: (() -> Void)?
    public var onScrollEnd: (() -> Void)?

    public var scrollingView: UIScrollView? { tableView }
}

// MARK: - WalletSeeAllCell.Delegate

extension WalletTokensVC: WalletSeeAllCell.Delegate {
    func didSelectSeeAll() {
        AppActions.showAssets(accountSource: $account.source, selectedTab: 0, collectionsFilter: .none)
    }
}
