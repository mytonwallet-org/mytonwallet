
import Foundation
import WalletContext

public struct ApiCheckTransactionDraftResult: Equatable, Codable, Sendable {
    
    /// The full fee that will be appended to the transaction. Measured in the native token. It's charged on top of the
    /// transferred amount, unless it's a full-TON transfer.
    public let fee: BigInt?
    /// An approximate fee that will be actually spent. The difference between `fee` and this number is called "excess" and
    /// will be returned back to the wallet. Measured in the native token. Undefined means that it can't be estimated.
    /// If the value is equal to `fee`, then it's known that there will be no excess.
    public let realFee: BigInt?
    public let addressName: String?
    public let isScam: Bool?
    public let resolvedAddress: String?
    public let isToAddressNew: Bool?
    public let isBounceable: Bool?
    public let isMemoRequired: Bool?
    public let error: ApiAnyDisplayError?
    /// Describes a possibility to use diesel for this transfer. The UI should prefer diesel when this field is defined,
    /// and the diesel status is not "not-available". When the diesel is available, and the UI decides to use it, the `fee`
    /// and `realFee` fields should be ignored, because they don't consider an extra transfer of the diesel to the
    /// MTW wallet.
    public let diesel: ApiFetchEstimateDieselResult?
    
    // staking extension
    public var tokenAmount: BigInt?
    public var type: String?
}


extension ApiCheckTransactionDraftResult {
    
    /// Like **diesel** but checks that status is not "not-abailable"
    public var dieselAvailable: ApiFetchEstimateDieselResult? {
        if let diesel, diesel.status != .notAvailable {
            return diesel
        }
        return nil
    }
}

// TODO: surface other errors where appropriate
public func handleDraftError(_ draft: ApiCheckTransactionDraftResult) throws {
    if let error = draft.error, error == .serverError {
        throw BridgeCallError.message(.serverError, draft)
    }
}
