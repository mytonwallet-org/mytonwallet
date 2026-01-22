
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
    public var status: ApiSwapStatus
    public let hashes: [String]?
    public let isCanceled: Bool?
    public let cex: ApiSwapCexTransactionExtras?
}

public enum ApiSwapStatus: String, Codable, Sendable {
    case pending
    case pendingTrusted
    case confirmed
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
    case confirmed
    
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
        case .new, .waiting, .confirming, .exchanging, .sending, .hold, .pending:
            return .pending
        case .expired, .refunded, .overdue:
            return .expired
        case .failed:
            return .failed
        case .finished, .confirmed:
            return .completed
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
        guard let decimals = fromToken?.decimals else { return nil }
        return doubleToBigInt(fromAmount.value, decimals: decimals)
    }
    
    var toAmountInt64: BigInt? {
        guard let decimals = toToken?.decimals else { return nil }
        return doubleToBigInt(toAmount.value, decimals: decimals)
    }
    
    var fromSymbolName: String {
        fromToken?.symbol ?? ""
    }
    
    var toSymbolName: String {
        toToken?.symbol ?? ""
    }
}

public func getSwapType(from: String, to: String, accountChains: Set<ApiChain>) -> SwapType {
    let fromChain = getChainBySlug(from)
    let toChain = getChainBySlug(to)
    
    if let fromChain, fromChain == toChain && fromChain.isOnchainSwapSupported {
        return .onChain
    }
    if let fromChain, let toChain, accountChains.contains(fromChain) && accountChains.contains(toChain) {
        return .crosschainInsideWallet
    }
    if let fromChain, accountChains.contains(fromChain) {
        return .crosschainFromWallet
    }
    return .crosschainToWallet
}
