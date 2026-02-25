
import Foundation
import WalletContext

extension Api {
    
    /// - Important: Do not call this method directly, use **AccountStore** instead
    internal static func activateAccount(accountId: String, newestActivityTimestamps: ApiActivityTimestamps?) async throws {
        try await bridge.callApiVoid("activateAccount", accountId, newestActivityTimestamps)
    }

    public static func deactivateAllAccounts() async throws {
        try await bridge.callApiVoid("deactivateAllAccounts")
    }

    public static func fetchLedgerAccount(accountId: String) async throws -> ApiLedgerAccount {
        try await bridge.callApi("fetchLedgerAccount", accountId, decoding: ApiLedgerAccount.self)
    }
}


// MARK: - Types

public typealias ApiActivityTimestamps = [String: Int64]

public struct ApiLedgerAccount: Equatable, Hashable, Codable {
  public var type = "ledger"
  public var byChain: [String: ApiTonWallet]
  public var driver: ApiLedgerDriver
  public var deviceId: String?
  public var deviceName: String?
}
