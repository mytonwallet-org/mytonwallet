
import WalletContext

/**
 * "Gas" is a fee in the native token.
 * "Diesel" is a fee in the transferred token (or in Telegram stars) in gasless mode.
 */
public struct ApiFetchEstimateDieselResult: Equatable, Codable, Sendable {
    
    public let status: DieselStatus?
    
    /// The amount of the diesel itself. It will be sent together with the actual transfer. None of this will return back
    /// as the excess. Undefined means that
    /// gasless transfer is not available, and the diesel shouldn't be shown as the fee; nevertheless, the status should
    /// be displayed by the UI.
    ///
    /// - If the status is not 'stars-fee', the value is measured in the transferred token and charged on top of the
    ///   transferred amount.
    /// - If the status is 'stars-fee', the value is measured in Telegram stars, and the BigInt assumes 0 decimal places
    ///   (i.e. the number is equal to the visible number of stars).
    let amount: BigInt?
    
    /// The native token amount covered by the diesel. Guaranteed to be > 0.
    let nativeAmount: BigInt
    
    /// The remaining part of the fee (the first part is `nativeAmount`) that will be taken from the existing wallet
    /// balance. Guaranteed that this amount is available in the wallet. Measured in the native token.
    let remainingFee: BigInt
    
    /// An approximate fee that will be actually spent. The difference between `nativeAmount+remainingFee` and this
    /// number is called "excess" and will be returned back to the wallet. Measured in the native token.
    let realFee: BigInt
}

extension ApiFetchEstimateDieselResult {
    public var tokenAmount: BigInt? { status == .starsFee ? nil : amount }
    public var starsAmount: BigInt? { status == .starsFee ? amount : nil }
}


public enum DieselStatus: String, Codable, Sendable {
    case notAvailable = "not-available"
    case notAuthorized = "not-authorized"
    case pendingPrevious = "pending-previous"
    case available = "available"
    case starsFee = "stars-fee"
}

extension DieselStatus {
    public var canContinue: Bool {
        return self == .notAuthorized || self == .available || self == .starsFee
    }

    public var errorString: String? {
        switch self {
        case .notAvailable, .starsFee, .notAuthorized, .available:
            return nil
        case .pendingPrevious:
            return lang("Awaiting Previous Fee")
        }
    }
}
