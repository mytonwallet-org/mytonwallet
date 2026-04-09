import Foundation
import WalletContext

private let wrappedTonSlug = "ton-eqcm3b12qk"
private let unknownTokenSymbol = "[Unknown]"

extension ApiUpdate {
    public struct DappSendTransactions: Equatable, Hashable, Decodable, Sendable {
        public var type = "dappSendTransactions"
        public var promiseId: String
        public var accountId: String
        public var dapp: ApiDapp
        public var operationChain: ApiChain
        public var transactions: [ApiDappTransfer]
        public var activities: [ApiActivity]?
        public var fee: BigInt?
        public var vestingAddress: String?
        public var validUntil: Int?
        public var emulation: Emulation?
        public var shouldHideTransfers: Bool?
        public var isLegacyOutput: Bool?
        
        public init(
            promiseId: String,
            accountId: String,
            dapp: ApiDapp,
            operationChain: ApiChain = .ton,
            transactions: [ApiDappTransfer],
            activities: [ApiActivity]? = nil,
            fee: BigInt? = nil,
            vestingAddress: String? = nil,
            validUntil: Int? = nil,
            emulation: Emulation?,
            shouldHideTransfers: Bool?,
            isLegacyOutput: Bool? = nil
        ) {
            self.promiseId = promiseId
            self.accountId = accountId
            self.dapp = dapp
            self.operationChain = operationChain
            self.transactions = transactions
            self.activities = activities
            self.fee = fee
            self.vestingAddress = vestingAddress
            self.validUntil = validUntil
            self.emulation = emulation
            self.shouldHideTransfers = shouldHideTransfers
            self.isLegacyOutput = isLegacyOutput
        }
        
        enum CodingKeys: CodingKey {
            case promiseId
            case accountId
            case dapp
            case operationChain
            case transactions
            case activities
            case fee
            case vestingAddress
            case validUntil
            case emulation
            case shouldHideTransfers
            case isLegacyOutput
        }
        
        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.promiseId = try container.decode(String.self, forKey: .promiseId)
            self.accountId = try container.decode(String.self, forKey: .accountId)
            self.dapp = try container.decode(ApiDapp.self, forKey: .dapp)
            self.operationChain = (try? container.decodeIfPresent(ApiChain.self, forKey: .operationChain)) ?? FALLBACK_CHAIN
            self.transactions = try container.decode([ApiDappTransfer].self, forKey: .transactions)
            self.activities = try container.decodeIfPresent([ApiActivity].self, forKey: .activities)
            self.fee = try? container.decodeIfPresent(BigInt.self, forKey: .fee)
            self.vestingAddress = try? container.decodeIfPresent(String.self, forKey: .vestingAddress)
            self.validUntil = try? container.decodeIfPresent(Int.self, forKey: .validUntil)
            self.emulation = try container.decodeIfPresent(Emulation.self, forKey: .emulation)
            self.shouldHideTransfers = try? container.decodeIfPresent(Bool.self, forKey: .shouldHideTransfers)
            self.isLegacyOutput = try? container.decodeIfPresent(Bool.self, forKey: .isLegacyOutput)
        }
    }
}

extension ApiUpdate.DappSendTransactions {
    public struct CombinedInfo {
        public var isDangerous: Bool
        public var isScam: Bool
        public var tokenTotals: [String: BigInt]
        public var tokenOrder: [String]
        public var nftsCount = 0
    }

    public struct TokenDisplayInfo {
        public var balance: BigInt
        public var token: ApiToken
    }
    
    public var combinedInfo: CombinedInfo {
        var totals: [String: BigInt] = [:]
        var tokenOrder: [String] = []
        var nftsCount = 0
        let nativeSlug = operationChain.nativeToken.slug

        func addAmount(slug: String, amount: BigInt) {
            if totals[slug] == nil {
                tokenOrder.append(slug)
            }
            totals[slug, default: 0] += amount
        }

        for transaction in transactions {
            addAmount(slug: nativeSlug, amount: transaction.amount + transaction.networkFee)

            switch transaction.payload {
            case .tokensTransfer(let parsed):
                addAmount(slug: parsed.slug, amount: parsed.amount)
            case .tokensTransferNonStandard(let parsed):
                addAmount(slug: parsed.slug, amount: parsed.amount)
            case .nftTransfer:
                nftsCount += 1
            default:
                break
            }
        }

        return CombinedInfo(
            isDangerous: transactions.any(\.isDangerous),
            isScam: transactions.any(\.isScam),
            tokenTotals: totals,
            tokenOrder: tokenOrder,
            nftsCount: nftsCount
        )
    }

    @MainActor public func insufficientTokens(accountContext: AccountContext) -> String? {
        let balances = accountContext.balances
        var insufficientTokens: [String] = []

        for slug in combinedInfo.tokenOrder {
            guard let requiredAmount = combinedInfo.tokenTotals[slug] else { continue }

            let availableBalance = balances[balanceSlug(for: slug)] ?? 0

            if availableBalance < requiredAmount {
                insufficientTokens.append(insufficientSymbol(for: slug))
            }
        }

        return insufficientTokens.isEmpty ? nil : insufficientTokens.joined(separator: ", ")
    }

    @MainActor public func hasSufficientBalance(accountContext: AccountContext) -> Bool {
        insufficientTokens(accountContext: accountContext) == nil
    }

    @MainActor public func tokenToDisplay(accountContext: AccountContext) -> TokenDisplayInfo {
        let nativeToken = operationChain.nativeToken
        let balances = accountContext.balances

        if combinedInfo.tokenTotals.isEmpty {
            return TokenDisplayInfo(
                balance: balances[nativeToken.slug] ?? 0,
                token: nativeToken
            )
        }

        var insufficientTokens: [(usdValue: Double, balance: BigInt, token: ApiToken)] = []
        var sufficientTokens: [(usdValue: Double, balance: BigInt, token: ApiToken)] = []

        for slug in combinedInfo.tokenOrder {
            guard let requiredAmount = combinedInfo.tokenTotals[slug],
                  let token = displayToken(for: slug) else { continue }

            let availableBalance = balances[slug] ?? 0
            let priceUsd = token.priceUsd ?? 0

            if availableBalance < requiredAmount {
                let insufficientAmount = requiredAmount - availableBalance
                let insufficientUsdValue = TokenAmount(insufficientAmount, token).doubleValue * priceUsd
                insufficientTokens.append((insufficientUsdValue, availableBalance, token))
            } else {
                let transactionUsdValue = TokenAmount(requiredAmount, token).doubleValue * priceUsd
                sufficientTokens.append((transactionUsdValue, availableBalance, token))
            }
        }

        if let token = insufficientTokens.max(by: { $0.usdValue < $1.usdValue }) {
            return TokenDisplayInfo(balance: token.balance, token: token.token)
        }

        if let token = sufficientTokens.max(by: { $0.usdValue < $1.usdValue }) {
            return TokenDisplayInfo(balance: token.balance, token: token.token)
        }

        return TokenDisplayInfo(
            balance: balances[nativeToken.slug] ?? 0,
            token: nativeToken
        )
    }

    @MainActor private func displayToken(for slug: String) -> ApiToken? {
        TokenStore.getToken(slug: slug)
    }

    private func balanceSlug(for slug: String) -> String {
        slug == wrappedTonSlug ? ApiChain.ton.nativeToken.slug : slug
    }

    @MainActor private func insufficientSymbol(for slug: String) -> String {
        if slug == wrappedTonSlug {
            return ApiChain.ton.nativeToken.symbol
        }

        return displayToken(for: slug)?.symbol ?? unknownTokenSymbol
    }
}
