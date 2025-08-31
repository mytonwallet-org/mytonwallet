
import UIKit
import UIComponents
import WalletCore
import WalletContext

private let log = Log("Home-WalletTokens")


@MainActor public final class WalletTokensVC: WViewController, WalletCoreData.EventsObserver, WalletTokensViewDelegate, Sendable {
    
    private let compactMode: Bool
    private var topInset: CGFloat { compactMode ? 0 : 56 }
    
    public var tokensView: WalletTokensView { view as! WalletTokensView }
    public var onHeightChanged: ((_ animated: Bool) -> ())?
    
    private var currentAccountId: String?
    
    public init(compactMode: Bool) {
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
        tokensView.contentInset.top = topInset
        tokensView.verticalScrollIndicatorInsets.top = topInset
        tokensView.contentOffset.y = -topInset
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
                updateWalletTokens(animated: true)
                tokensView.reloadStakeCells(animated: false)
                
            case .stakingAccountData(let data):
                if data.accountId == AccountStore.accountId {
                    stakingDataUpdated()
                }
                
            case .tokensChanged:
                tokensChanged()
            
            case .balanceChanged(_):
                updateWalletTokens(animated: true)
                
            default:
                break
            }
        }
    }
    
    private func stakingDataUpdated() {
        tokensView.reloadStakeCells(animated: true)
    }
    
    private func tokensChanged() {
        tokensView.reconfigureAllRows(animated: true)
    }
    
    private func updateWalletTokens(animated: Bool) {
        var animated = animated
        if let account = AccountStore.account {
            let accountId = account.id
            if accountId != currentAccountId {
                animated = false
                currentAccountId = accountId
            }
            
            if let data = BalanceStore.currentAccountBalanceData {
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
    }
    
    public func didSelect(slug: String?) {
        guard let slug, let token = TokenStore.tokens[slug] else {
            return
        }
        AppActions.showToken(token: token, isInModal: !compactMode)
    }

    public func goToStakedPage(slug: String) {
        let token: ApiToken? = switch slug {
        case TONCOIN_SLUG, STAKED_TON_SLUG:
            nil
        case MYCOIN_SLUG, STAKED_MYCOIN_SLUG:
            TokenStore.tokens[STAKED_MYCOIN_SLUG]!
        case TON_USDE_SLUG, TON_TSUSDE_SLUG:
            TokenStore.tokens[TON_USDE_SLUG]!
        default:
            nil
        }
        AppActions.showEarn(token: token)
    }

    public func goToTokens() {
        AppActions.showAssets(selectedTab: 0, collectionsFilter: .none)
    }
}
