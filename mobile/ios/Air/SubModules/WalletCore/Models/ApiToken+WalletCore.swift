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
    
    public func displayName(strippingLabelWhenShown: Bool) -> String {
        displayName(
            strippingLabelWhenShown: strippingLabelWhenShown,
            useLocalizedName: AppStorageHelper.useLocalizedTokenNames
        )
    }

    public func displayName(strippingLabelWhenShown: Bool, useLocalizedName: Bool) -> String {
        let displayName = if useLocalizedName {
            localizedName?.nilIfEmpty ?? name
        } else {
            name
        }

        guard strippingLabelWhenShown,
              isRwaStock,
              let label = label?.trimmingCharacters(in: .whitespacesAndNewlines),
              !label.isEmpty else {
            return displayName
        }

        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = [label, label.removingSuffix("s"), label.removingSuffix("S")]
            .filter { !$0.isEmpty }
            .uniqued()

        for candidate in candidates {
            let strippedName = trimmedName.strippingPrefixOrSuffix(candidate).trimmingCharacters(in: .whitespacesAndNewlines)
            if strippedName != trimmedName {
                return strippedName.isEmpty ? displayName : strippedName
            }
        }

        return displayName
    }
}

private extension String {
    func removingSuffix(_ suffix: String) -> String {
        guard hasSuffix(suffix) else { return self }
        return String(dropLast(suffix.count))
    }

    func strippingPrefixOrSuffix(_ value: String) -> String {
        guard count > value.count else { return self }

        if range(of: value, options: [.caseInsensitive, .anchored]) != nil {
            return String(dropFirst(value.count))
        }

        if range(of: value, options: [.caseInsensitive, .anchored, .backwards]) != nil {
            return String(dropLast(value.count))
        }

        return self
    }
}

private extension Array where Element == String {
    func uniqued() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0).inserted }
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
            let supportedChains = ApiChain.allCases.filter { account.supports(chain: $0) }
            if supportedChains.count == 1, let chain = supportedChains.first {
                return OrderedSet(defaultSlugs(for: chain, network: network, account: account))
            }

            return OrderedSet(supportedChains.map(\.nativeToken.slug))
        }

        return OrderedSet(ApiChain.allCases.map(\.nativeToken.slug))
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
