import OrderedCollections
import WalletContext
import WalletCoreTypes

extension ApiToken {
    public var price: Double? {
        return priceUsd.flatMap { $0 * TokenStore.baseCurrencyRate }
    }
    
    public var isOnChain: Bool {
        AccountStore.account?.supports(chain: chain) ?? false
    }
    
    public var earnAvailable: Bool {
        return AccountStore.activeNetwork == .mainnet && EARN_AVAILABLE_SLUGS.contains(slug)
    }
}

extension ApiToken {
    /// initial StubTokenSlugs
    /// These are shown when account is created and there are no transactions yet.
    /// The order is defined as for displaying in UI.
    public static func defaultSlugs(forNetwork network: ApiNetwork, account: MAccount? = nil) -> OrderedSet<String> {
        if IS_GRAM_WALLET {
            return OrderedSet(defaultSlugs(for: .ton, network: network, account: nil))
        }

        if let account {
            let supportedChains = account.supportedChains
            if supportedChains.count == 1, let chain = supportedChains.first {
                return OrderedSet(defaultSlugs(for: chain, network: network, account: account))
            }
        }

        let slugs: [(ApiChain, String)] = [
            (.ethereum, ETH_SLUG),
            (.solana, SOLANA_SLUG),
            (.ton, TONCOIN_SLUG),
            (.tron, TRX_SLUG),
            (.bnb, BNB_SLUG),
            (.hyperliquid, HYPERLIQUID_SLUG),
        ]

        return OrderedSet(
            slugs.compactMap { chain, slug in
                if let account, !account.supports(chain: chain) {
                    return nil
                }
                return slug
            }
        )
    }

    private static func defaultSlugs(for chain: ApiChain, network: ApiNetwork, account: MAccount?) -> [String] {
        guard account?.supports(chain: chain) != false else {
            return []
        }

        var slugs = [chain.nativeToken.slug]
        if let stablecoinSlug = chain.usdtSlug[network]?.nilIfEmpty {
            slugs.append(stablecoinSlug)
        }
        return slugs
    }
}
