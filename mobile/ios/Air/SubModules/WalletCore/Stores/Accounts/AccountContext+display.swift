import Foundation
import WalletContext
import WalletCoreTypes

public extension AccountContext {
    var orderedChains: [(ApiChain, AccountChain)] {
        let defaultOrderedChains = account.orderedChains
        guard defaultOrderedChains.count > 1 else {
            return defaultOrderedChains
        }

        let defaultOrder = Dictionary(uniqueKeysWithValues: defaultOrderedChains.enumerated().map { offset, element in
            (element.0, offset)
        })
        let chainBalances = balanceUsdByChain ?? [:]

        return defaultOrderedChains.sorted { lhs, rhs in
            let lhsBalance = chainBalances[lhs.0] ?? 0
            let rhsBalance = chainBalances[rhs.0] ?? 0

            if lhsBalance != rhsBalance {
                return lhsBalance > rhsBalance
            }

            return defaultOrder[lhs.0, default: Int.max] < defaultOrder[rhs.0, default: Int.max]
        }
    }

    var displayedChains: [(ApiChain, AccountChain)] {
        displayedChains(including: nil)
    }

    func displayedChains(including requiredChain: ApiChain?) -> [(ApiChain, AccountChain)] {
        let defaultOrderedChains = account.orderedChains
        let valueOrderedChains = orderedChains
        let displayData = AssetsAndActivityDataStore.data(accountId: account.id) ?? .empty
        let displayedChainOrder = displayData.visibleChains(
            defaultOrder: defaultOrderedChains.map(\.0),
            valueOrder: valueOrderedChains.map(\.0),
            automaticallyVisibleChains: automaticallyVisibleChains,
            including: requiredChain
        )
        let chainInfo = Dictionary(uniqueKeysWithValues: defaultOrderedChains)
        return displayedChainOrder.compactMap { chain in
            chainInfo[chain].map { (chain, $0) }
        }
    }

    var automaticallyVisibleChains: Set<ApiChain> {
        var hasTokenBalance = false
        var chainsWithBalance: Set<ApiChain> = []

        for (slug, balance) in balances where balance > 0 {
            hasTokenBalance = true
            if let chain = getChainBySlug(slug) ?? TokenStore.tokens[slug]?.chain {
                chainsWithBalance.insert(chain)
            }
        }

        if let stakingStates = stakingData?.stateById.values {
            for state in stakingStates where getFullStakingBalance(state: state) > 0 {
                hasTokenBalance = true
                if let chain = getChainBySlug(state.tokenSlug) ?? TokenStore.tokens[state.tokenSlug]?.chain {
                    chainsWithBalance.insert(chain)
                }
            }
        }

        return MChainDisplayConfiguration.automaticallyVisibleChains(
            defaultOrder: account.orderedChains.map(\.0),
            chainsWithBalance: chainsWithBalance,
            hasTokenBalance: hasTokenBalance,
            isGramWallet: IS_GRAM_WALLET
        )
    }

    var addressLine: MAccount.AddressLine {
        account.addressLine(orderedChains: displayedChains, tokenChains: addressLineTokenChains)
    }

    var shareLink: URL {
        account.shareLink(visibleChains: Set(displayedChains.map(\.0)))
    }

    private var addressLineTokenChains: Set<ApiChain>? {
        guard let tokens = walletTokensData?.orderedTokenBalances else { return nil }
        var chains: Set<ApiChain> = []
        for token in tokens {
            guard let chain = getChainBySlug(token.tokenSlug) ?? token.token?.chain else {
                return nil
            }
            chains.insert(chain)
        }
        return chains
    }
}
