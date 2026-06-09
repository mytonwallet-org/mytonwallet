import Foundation
import WalletContext
import WalletCore

@MainActor
final class WalletSearchProvider: SearchProvider {
    private let actions: ExploreSearchActions

    init(actions: ExploreSearchActions) {
        self.actions = actions
    }

    func search(_ query: SearchQuery, emit: @MainActor ([SearchResultSection]) -> Void) async throws {
        guard !query.isEmpty else { return }

        guard let account = AccountStore.account else { return }
        let network = account.network
        let queryText = query.text

        // Match the query against the user's own added wallets (by name, address, or domain). This is a
        // synchronous, local scan and runs before any eligibility/network work so a name-only query
        // (which is not a valid address) can still surface a wallet.
        let myWalletItems = matchOwnWallets(query: query)
        let mySection: SearchResultSection? = myWalletItems.isEmpty ? nil : .init(
            id: .wallets,
            order: SearchSectionOrder.wallets,
            header: SearchSectionHeader(title: lang("My")),
            items: myWalletItems
        )
        if let mySection, myWalletItems.contains(where: { $0.isExactMatch }) {
            emit([mySection])
            return
        }

        
        // Ask API for well-known address
        var walletSection: SearchResultSection?
        let compatibleChains = ApiChain.allCases.filter { $0.isValidAddressOrDomain(queryText) }
        for chain in compatibleChains {
            let info = try await Api.getAddressInfo(chain: chain, network: network, address: queryText)
            try Task.checkCancellation()

            guard info.error == nil else { continue }

            let isDomain = chain.isValidDomain(queryText)
            let resolved = info.resolvedAddress?.nilIfEmpty

            let address: String
            if let resolved {
                address = resolved
            } else if !isDomain {
                address = queryText
            } else {
                continue
            }

            walletSection = SearchResultSection(
                id: .wallets,
                order: SearchSectionOrder.wallets,
                header: nil,
                items: [
                    WalletSearchResultItem(
                        network: network,
                        chain: chain,
                        inputAddressOrDomain: queryText,
                        address: address,
                        name: info.addressName?.nilIfEmpty,
                        domain: isDomain ? queryText : nil,
                        actions: actions
                    )
                ]
            )
            break
        }
        
        emit([mySection, walletSection].compactMap { $0 })
    }

    private func matchOwnWallets(query: SearchQuery) -> [MyWalletSearchResultItem] {
        let keyword = query.keyword
        guard !keyword.isEmpty else { return [] }

        var items: [MyWalletSearchResultItem] = []
        for account in AccountStore.orderedAccounts {
            let name = account.title?.nilIfEmpty
            let nameLower = name?.lowercased()

            var isPartial = false
            var isFull = false
            var matchedChain: ApiChain?
            var matchedAddress: String?

            if let nameLower {
                if nameLower == keyword {
                    isFull = true
                    isPartial = true
                } else if nameLower.contains(keyword) {
                    isPartial = true
                }
            }

            let minimalAcceptableAddressMatchCount: Int = 4
            let minimalAcceptableDomainMatchCount: Int = 1

            for (chain, info) in account.orderedChains {
                let addressLower = info.address.lowercased()
                let domainLower = info.domain?.lowercased()

                if addressLower == keyword || domainLower == keyword {
                    isFull = true
                    isPartial = true
                    matchedChain = chain
                    matchedAddress = info.address
                    break
                }
                
                let addressMatched = (addressLower.contains(keyword) && keyword.count >= minimalAcceptableAddressMatchCount)
                let domainMatched = (domainLower?.contains(keyword) ?? false) && keyword.count >= minimalAcceptableDomainMatchCount
                if  addressMatched || domainMatched {
                    isPartial = true
                    if matchedChain == nil {
                        matchedChain = chain
                        matchedAddress = info.address
                    }
                }
            }

            guard isPartial else { continue }

            // Matched only by name: fall back to the account's primary chain for display.
            let chain = matchedChain ?? account.firstChain
            let address = matchedAddress ?? account.getAddress(chain: chain) ?? account.firstAddress
            items.append(MyWalletSearchResultItem(
                account: account,
                chain: chain,
                address: address,
                isFullMatch: isFull,
                actions: actions
            ))
        }

        // Full matches first (preserving account order) so the composer promotes one to the top match.
        return items.filter(\.isFullMatch) + items.filter { !$0.isFullMatch }
    }
}
