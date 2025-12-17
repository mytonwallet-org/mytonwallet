
import UIKit
import UIComponents
import WalletCore
import WalletContext
import Dependencies

private let log = Log("Home-WalletTokens")


@MainActor public final class WalletTokensVC: WViewController, WalletCoreData.EventsObserver, WalletTokensViewDelegate, Sendable {

    private let compactMode: Bool

    public var tokensView: WalletTokensView { view as! WalletTokensView }
    public var onHeightChanged: ((_ animated: Bool) -> ())?

    private var displayedAccountId: String {
        get { tokensView.accountId }
        set { tokensView.accountId = newValue }
    }
    
    public let accountIdProvider: AccountIdProvider
    
    var accountId: String { accountIdProvider.accountId }

    public init(accountSource: AccountSource, compactMode: Bool) {
        self.accountIdProvider = AccountIdProvider(source: accountSource)
        self.compactMode = compactMode
        super.init(nibName: nil, bundle: nil)
    }

    @MainActor required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func loadView() {
        view = WalletTokensView(compactMode: compactMode, delegate: self)
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        updateTheme()
        WalletCoreData.add(eventObserver: self)
    }

    public override func viewWillAppear(_ animated: Bool) {
        updateWalletTokens(animated: false)
        super.viewWillAppear(animated)
    }

    public override func updateTheme() {
    }

    nonisolated public func walletCore(event: WalletCore.WalletCoreData.Event) {
        MainActor.assumeIsolated {
            switch event {
            case .accountChanged:
                if accountIdProvider.source == .current {
                    updateWalletTokens(animated: true)
                    tokensView.reloadStakeCells(animated: false)
                }

            case .stakingAccountData(let data):
                if data.accountId == self.accountId {
                    stakingDataUpdated()
                }

            case .tokensChanged:
                tokensChanged()

            case .balanceChanged(let accountId, _):
                if accountId == self.accountId {
                    updateWalletTokens(animated: true)
                }

            default:
                break
            }
        }
    }
    
    public func switchAcccountTo(accountId: String, animated: Bool) {
        self.accountIdProvider.accountId = accountId
        updateWalletTokens(animated: animated)
    }

    private func stakingDataUpdated() {
        tokensView.reloadStakeCells(animated: true)
    }

    private func tokensChanged() {
        tokensView.reconfigureAllRows(animated: true)
    }

    private func updateWalletTokens(animated: Bool) {
        let accountChanged = accountId != displayedAccountId
        if accountChanged {
            displayedAccountId = accountId
        }

        if let data = BalanceStore.accountBalanceData[accountId] {
            var allTokens = data.walletStaked + data.walletTokens
            let count = allTokens.count
            if compactMode {
                allTokens = Array(allTokens.prefix(5))
            }
            tokensView.set(
                walletTokens: allTokens,
                allTokensCount: count,
                placeholderCount: 0,
                animated: animated
            )
        } else {
            tokensView.set(
                walletTokens: nil,
                allTokensCount: 0,
                placeholderCount: 4,
                animated: animated
            )
        }
        self.onHeightChanged?(animated)
    }

    public func didSelect(slug: String?) {
        guard let slug, let token = TokenStore.tokens[slug] else {
            return
        }
        AppActions.showToken(token: token, isInModal: !compactMode)
    }

    public func goToStakedPage(slug: String) {
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

    public func goToTokens() {
        AppActions.showAssets(accountSource: accountIdProvider.source, selectedTab: 0, collectionsFilter: .none)
    }
}
