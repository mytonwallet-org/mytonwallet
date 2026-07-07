
import UIKit
import WalletContext
import WalletCoreTypes

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
    public let ourFeeMode: String?
    public let cexLabel: ApiSwapCexLabel?
    public var status: ApiSwapStatus
    public let hashes: [String]?
    public let transactionIds: ApiSwapTransactionIds
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


public struct ApiSwapTransactionRef: Codable, Equatable, Hashable, Sendable {
    public let hash: String
    public let chain: ApiChain
}

public struct ApiSwapTransactionIds: Codable, Equatable, Hashable, Sendable {
    public let outgoing: ApiSwapTransactionRef?
    public let incoming: ApiSwapTransactionRef?

    public init(outgoing: ApiSwapTransactionRef? = nil, incoming: ApiSwapTransactionRef? = nil) {
        self.outgoing = outgoing
        self.incoming = incoming
    }
}

public enum SwapDisplayStatus: Sendable, Equatable {
    case pending
    case waitingForPayment
    case hold
    case expired
    case refunded
    case failed
    case completed

    public var isPending: Bool {
        switch self {
        case .pending, .waitingForPayment:
            true
        case .hold, .expired, .refunded, .failed, .completed:
            false
        }
    }

    public var isError: Bool {
        switch self {
        case .expired, .refunded, .failed:
            true
        case .pending, .waitingForPayment, .hold, .completed:
            false
        }
    }
}

public struct ApiSwapCexTransactionExtras: Codable, Equatable, Hashable, Sendable {
    public let payinAddress: String
    public let payoutAddress: String
    public let payinExtraId: String?
    public let status: ApiSwapCexTransactionStatus
    public let transactionId: String
    public let providerName: String?
    public let supportUrl: String?
    public let supportEmail: String?
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
    func displayStatus(accountChains: Set<ApiChain>? = nil) -> SwapDisplayStatus {
        if let cexStatus = cex?.status {
            switch cexStatus {
            case .expired, .overdue:
                return .expired
            case .refunded:
                return .refunded
            case .failed:
                return .failed
            case .hold:
                return .hold
            case .finished, .confirmed:
                return .completed
            case .waiting:
                if let accountChains, !getShouldSkipSwapWaitingStatus(swap: self, accountChains: accountChains) {
                    return .waitingForPayment
                }
                return .pending
            case .new, .confirming, .exchanging, .sending, .pending:
                return .pending
            }
        }

        switch status {
        case .failed:
            return .failed
        case .expired:
            return .expired
        case .pending, .pendingTrusted:
            return .pending
        case .completed, .confirmed:
            return .completed
        }
    }

    var fromToken: ApiToken? {
        TokenStore.getToken(slugOrAddress: from)
    }
    
    var toToken: ApiToken? {
        TokenStore.getToken(slugOrAddress: to)
    }

    var displayFromToken: ApiToken {
        TokenStore.getDisplayToken(slugOrAddress: from)
    }

    var displayToToken: ApiToken {
        TokenStore.getDisplayToken(slugOrAddress: to)
    }
    
    var fromTokenSlug: String {
        fromToken?.slug ?? from
    }

    var toTokenSlug: String {
        toToken?.slug ?? to
    }

    var fromAmountInt64: BigInt? {
        guard let decimals = fromToken?.decimals else { return nil }
        return doubleToBigInt(fromAmount.value, decimals: decimals)
    }
    
    var toAmountInt64: BigInt? {
        guard let decimals = toToken?.decimals else { return nil }
        return doubleToBigInt(toAmount.value, decimals: decimals)
    }

    var displayFromAmount: TokenAmount {
        TokenAmount.fromDouble(fromAmount.value, displayFromToken)
    }

    var displayToAmount: TokenAmount {
        TokenAmount.fromDouble(toAmount.value, displayToToken)
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

public func getShouldSkipSwapWaitingStatus(swap: ApiSwapActivity, accountChains: Set<ApiChain>) -> Bool {
    getSwapType(from: swap.from, to: swap.to, accountChains: accountChains) != .crosschainToWallet
}

public func getShouldSkipSwapWaitingStatus(activity: ApiActivity, accountChains: Set<ApiChain>) -> Bool {
    if let swap = activity.swap {
        return getShouldSkipSwapWaitingStatus(swap: swap, accountChains: accountChains)
    }
    return false
}
