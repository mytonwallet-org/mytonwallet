
import Foundation
import WalletContext

public protocol ApiTransactionCommonOptions: Equatable, Hashable, Codable, Sendable {
    var accountId: String { get }
    var toAddress: String { get }
    /**
    * When the value is undefined, the method doesn't check the available balance. If you want only to estimate the fee,
    * don't send the amount, because:
    * - The fee doesn't depend on the amount neither in TON nor in TRON.
    * - Errors will happen in edge cases such as 0 and greater than the balance.
    */
    var amount: BigInt? { get }
    var payload: AnyTransferPayload? { get }
    /// Base64
    var stateInit: String? { get }
    /// For token transfer
    var tokenAddress: String? { get }
}
