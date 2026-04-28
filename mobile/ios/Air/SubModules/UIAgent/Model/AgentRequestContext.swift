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
    let savedAddresses: [AgentAddressInfo]?
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
            .map { Set($0.orderedTokenBalances.map(\.tokenSlug)).sorted() }
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
            userAddresses: buildUserAddresses(activeAccount: account),
            savedAddresses: buildSavedAddresses(using: accountContext),
            balances: balances,
            walletTokens: walletTokens,
            isEdit: editContext == nil ? nil : true,
            originalText: editContext?.originalText
        )
    }

    @MainActor
    private static func buildUserAddresses(activeAccount: MAccount?) -> [AgentAddressInfo]? {
        let allAccounts = AccountStore.orderedAccounts
        guard !allAccounts.isEmpty else { return nil }

        let firstFive = allAccounts.prefix(5)
        let activeId = activeAccount?.id
        let activeInFirstFive = firstFive.contains { $0.id == activeId }

        var result: [AgentAddressInfo] = firstFive.compactMap { account in
            let addrs = account.orderedChains.compactMap { chain, _ -> String? in
                guard let address = account.getAddress(chain: chain)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                      !address.isEmpty else { return nil }
                return "\(chain.rawValue):\(address)"
            }
            guard !addrs.isEmpty else { return nil }
            return AgentAddressInfo(
                name: account.displayName,
                addresses: addrs,
                accountType: account.type.rawValue,
                isActive: account.id == activeId
            )
        }

        // If active account is not among the first 5, append it
        if !activeInFirstFive, let account = activeAccount {
            let addrs = account.orderedChains.compactMap { chain, _ -> String? in
                guard let address = account.getAddress(chain: chain)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                      !address.isEmpty else { return nil }
                return "\(chain.rawValue):\(address)"
            }
            if !addrs.isEmpty {
                result.append(AgentAddressInfo(
                    name: account.displayName,
                    addresses: addrs,
                    accountType: account.type.rawValue,
                    isActive: true
                ))
            }
        }

        return result.nilIfEmpty
    }

    @MainActor
    private static func buildSavedAddresses(using accountContext: AccountContext) -> [AgentAddressInfo]? {
        let saved = accountContext.savedAddresses.values.prefix(10)
        let result: [AgentAddressInfo] = saved.map { addr in
            AgentAddressInfo(
                name: addr.name,
                addresses: ["\(addr.chain.rawValue):\(addr.address)"]
            )
        }
        return result.nilIfEmpty
    }
}

struct AgentAddressInfo: Encodable, Sendable {
    let name: String
    let addresses: [String]  // e.g. ["ton:UQ...", "solana:addr", "tron:addr"]
    var accountType: String?  // "mnemonic", "hardware", "view"
    var isActive: Bool?

    enum CodingKeys: String, CodingKey {
        case name, addresses, accountType, isActive
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(addresses, forKey: .addresses)
        try container.encodeIfPresent(accountType, forKey: .accountType)
        if isActive == true {
            try container.encode(true, forKey: .isActive)
        }
    }
}

private extension Array {
    var nilIfEmpty: Self? {
        isEmpty ? nil : self
    }
}
