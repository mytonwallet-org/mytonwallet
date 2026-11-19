import Foundation
import WalletCoreTypes

public struct ApiSwapCexBuildRequest: Codable, Sendable {
    public let from: String
    public let to: String
    /// Swap asset ids may be a bare token contract shared across networks, so the source chain is named apart
    public let fromChain: ApiChain
    public let cexLabel: ApiSwapCexLabel?
    public let fromAmount: MDouble
    public let toAmount: MDouble?
    public let toAddress: String
    public let networkFee: MDouble?
    public let swapFee: MDouble?

    public init(
        from: String,
        to: String,
        fromChain: ApiChain,
        cexLabel: ApiSwapCexLabel?,
        fromAmount: MDouble,
        toAmount: MDouble? = nil,
        toAddress: String,
        networkFee: MDouble? = nil,
        swapFee: MDouble? = nil
    ) {
        self.from = from
        self.to = to
        self.fromChain = fromChain
        self.cexLabel = cexLabel
        self.fromAmount = fromAmount
        self.toAmount = toAmount
        self.toAddress = toAddress
        self.networkFee = networkFee
        self.swapFee = swapFee
    }
}
