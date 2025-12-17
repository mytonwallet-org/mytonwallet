
import UIKit
import WalletContext

public struct ApiSwapActivity: BaseActivity, Codable, Equatable, Hashable, Sendable {
    
    // BaseActivity
    public let id: String
    public var kind: String = "swap"
    public var shouldHide: Bool?
    public let externalMsgHashNorm: String?
    public var shouldReload: Bool?
    public var shouldLoadDetails: Bool?
    public var extra: BaseActivityExtra?

    public let timestamp: Int64
    public let lt: Int64?
    public let from: String
    public let fromAmount: MDouble
    public let to: String
    public let toAmount: MDouble
    public let networkFee: MDouble? // FIXME: Had to add ? for comatibility
    public let swapFee: MDouble? // FIXME: Had to add ? for comatibility
    public let ourFee: MDouble?
    /**
       * Swap confirmation status
       * Both 'pendingTrusted' and 'pending' mean the swap is awaiting confirmation by the blockchain.
       * - 'pendingTrusted' — awaiting confirmation and trusted (initiated by our app).
       * - 'pending' — awaiting confirmation from an external/unauthenticated source.
       *
       * There are two backends: ToncenterApi and our backend.
       * Swaps returned by ToncenterApi have the status 'pending'.
       * Swaps returned by our backend also have the status 'pending', but they are meant to be 'pendingTrusted'.
       * When an activity reaches the `GlobalState`, it already has the correct status set.
       *
       * TODO: Replace the status 'pending' with 'pendingTrusted' on our backend once all clients are updated.
       */
    public let status: ApiSwapStatus
    public let hashes: [String]?
    public let isCanceled: Bool?
    public let cex: ApiSwapCexTransactionExtras?
}

public enum ApiSwapStatus: String, Codable, Sendable {
    case pending
    case pendingTrusted
    case completed
    case failed
    case expired
}

public struct ApiSwapCexTransactionExtras: Codable, Equatable, Hashable, Sendable {
    public let payinAddress: String
    public let payoutAddress: String
    public let payinExtraId: String?
    public let status: ApiSwapCexTransactionStatus
    public let transactionId: String
}

public enum ApiSwapCexTransactionStatus: String, Codable, Sendable {
    case new
    case waiting
    case confirming
    case exchanging
    case sending
    case finished
    case failed
    case refunded
    case hold
    case overdue
    case expired
    
    // FIXME: added for compatibility
    case pending
    
    public enum UIStatus: Codable, Sendable {
        case waiting
        case pending
        case expired
        case failed
        case completed
    }
    public var uiStatus: UIStatus {
        switch self {
        case .new, .waiting, .confirming, .exchanging, .sending, .hold:
            return .pending
        case .expired, .refunded, .overdue:
            return .expired
        case .failed:
            return .failed
        case .finished:
            return .completed
        default:
            return .pending
        }
    }
}

public extension ApiSwapActivity {
    var fromToken: ApiToken? {
        TokenStore.getToken(slugOrAddress: from)
    }
    
    var toToken: ApiToken? {
        TokenStore.getToken(slugOrAddress: to)
    }
    
    var fromAmountInt64: BigInt? {
        doubleToBigInt(fromAmount.value, decimals: fromToken?.decimals ?? 9)
    }
    
    var toAmountInt64: BigInt? {
        doubleToBigInt(toAmount.value, decimals: toToken?.decimals ?? 9)
    }
    
    var fromSymbolName: String {
        fromToken?.symbol ?? ""
    }
    
    var toSymbolName: String {
        toToken?.symbol ?? ""
    }
    
    var swapType: SwapType? {
        if let fromToken, let toToken {
            return getSwapType(fromToken: fromToken, toToken: toToken)
        }
        return nil
    }
}


public func getSwapType(fromToken: ApiToken, toToken: ApiToken) -> SwapType {
    if fromToken.isOnChain && toToken.isOnChain {
        if fromToken.chainValue == toToken.chainValue && fromToken.chainValue.supportsSwap {
            return .onChain
        } else {
            return .crosschainInsideWallet
        }
    } else if fromToken.isOnChain {
        return .crosschainFromWallet
    } else {
        return .crosschainToWallet
    }
}
