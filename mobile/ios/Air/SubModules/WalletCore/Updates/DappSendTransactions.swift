import Foundation
import WalletContext

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
        public var nftsCount = 0
    }
    
    public var combinedInfo: CombinedInfo {
        var totals: [String: BigInt] = [:]
        var nftsCount = 0
        let nativeSlug = operationChain.nativeToken.slug
        for transaction in transactions {
            totals[nativeSlug, default: 0] += transaction.amount + transaction.networkFee
            if operationChain == .ton {
                if case .tokensTransfer(let parsed) = transaction.payload {
                    totals[parsed.slug, default: 0] += parsed.amount
                } else if case .nftTransfer(_) = transaction.payload {
                    nftsCount += 1
                }
            }
        }
        return CombinedInfo(
            isDangerous: transactions.any(\.isDangerous),
            isScam: transactions.any(\.isScam),
            tokenTotals: totals,
            nftsCount: nftsCount
        )
    }
    
    public func hasSufficientBalance(accountContext: AccountContext) -> Bool {
        let totals = combinedInfo.tokenTotals
        let balances = accountContext.balances
        for (slug, amount) in totals {
            let available = balances[slug] ?? 0
            if amount > available {
                return false
            }
        }
        return true
    }
}
