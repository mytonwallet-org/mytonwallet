import Foundation
import GRDB
import WalletContext

public struct MAccountBalances: Equatable, Hashable, Codable, Sendable, FetchableRecord, PersistableRecord {
    public let accountId: String
    public var chain: ApiChain
    public var balances: [String: BigInt]
    public var updatedAt: Date

    public init(accountId: String, chain: ApiChain, balances: [String: BigInt], updatedAt: Date) {
        self.accountId = accountId
        self.chain = chain
        self.balances = balances
        self.updatedAt = updatedAt
    }

    public static let databaseTableName: String = "account_balances"
}
