import Foundation
import WalletContext
import WalletCore

private enum AgentRequestContextMetrics {
    static let client = "native"
    static let platform = "ios"
}

struct AgentRequestContext: Encodable {
    let platform: String
    let client: String
    let lang: String?
    let baseCurrency: String?
    let userAddresses: [AgentAddressInfo]?
    let balances: [String]?
    let walletTokens: [[String]]?
    let isEdit: Bool?
    let originalText: String?

    @MainActor
    static func current(
        using accountContext: AccountContext,
        editContext: AgentBackendEditContext? = nil
    ) -> AgentRequestContext {
        let account = AccountStore.account
        let balances = account.map { _ in
            accountContext.balances
                .sorted { lhs, rhs in lhs.key < rhs.key }
                .map { "\($0.key):\($0.value)" }
                .nilIfEmpty
        } ?? nil

        let walletTokenSlugs: [String] = accountContext.walletTokensData
            .map { Set($0.walletTokens.map(\.tokenSlug) + $0.walletStaked.map(\.tokenSlug)).sorted() }
            ?? []
        let walletTokens: [[String]]? = {
            let items: [[String]] = walletTokenSlugs.compactMap { slug -> [String]? in
                guard let token = TokenStore.getToken(slug: slug) else { return nil }
                let price = token.priceUsd.map { String($0) } ?? ""
                return [token.slug, token.symbol, token.name, String(token.decimals), price]
            }
            return items.nilIfEmpty
        }()

        return AgentRequestContext(
            platform: AgentRequestContextMetrics.platform,
            client: AgentRequestContextMetrics.client,
            lang: LocalizationSupport.shared.langCode,
            baseCurrency: TokenStore.baseCurrency.rawValue,
            userAddresses: {
                guard let account else { return nil }
                let addrs = account.orderedChains.compactMap { chain, _ -> String? in
                    guard let address = account.getAddress(chain: chain)?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                          !address.isEmpty else {
                        return nil
                    }
                    return "\(chain.rawValue):\(address)"
                }
                return addrs.isEmpty ? nil : [AgentAddressInfo(name: account.displayName, addresses: addrs)]
            }(),
            balances: balances,
            walletTokens: walletTokens,
            isEdit: editContext == nil ? nil : true,
            originalText: editContext?.originalText
        )
    }
}

struct AgentAddressInfo: Encodable, Sendable {
    let name: String
    let addresses: [String]  // e.g. ["ton:UQ...", "solana:addr", "tron:addr"]
}

private extension Array {
    var nilIfEmpty: Self? {
        isEmpty ? nil : self
    }
}
