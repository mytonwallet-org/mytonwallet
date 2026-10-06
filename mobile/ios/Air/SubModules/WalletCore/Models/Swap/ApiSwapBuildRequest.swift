
import Foundation
import WalletCoreTypes

public enum ApiSwapMode: String, Codable, Sendable {
    case exactIn = "exact_in"
    case exactOut = "exact_out"
}

public struct ApiSwapBuildRequest: Codable, Sendable {
    public let from: String
    public let to: String
    public let fromAddress: String
    public let historyAddress: String?
    public let dexLabel: ApiSwapDexLabel?
    public let dexRouterLabel: String?
    public let cexLabel: ApiSwapCexLabel?
    public let fromAmount: MDouble
    public let toAmount: MDouble?
    public let toMinAmount: MDouble?
    public let slippage: Double?
    public let shouldTryDiesel: Bool?
    public let swapVersion: Int?
    public let swapMode: ApiSwapMode?
    public let walletVersion: String?
    public let routes: [[ApiSwapRoute]]?
    public let toAddress: String?
    public let payoutExtraId: String?
    // Fees
    public let networkFee: MDouble?
    public let swapFee: MDouble?
    public let ourFee: MDouble?
    public let dieselFee: MDouble?
    public let needsApprove: Bool?

    public init(
        from: String,
        to: String,
        fromAddress: String,
        historyAddress: String? = nil,
        dexLabel: ApiSwapDexLabel? = nil,
        dexRouterLabel: String? = nil,
        cexLabel: ApiSwapCexLabel? = nil,
        fromAmount: MDouble,
        toAmount: MDouble? = nil,
        toMinAmount: MDouble? = nil,
        slippage: Double? = nil,
        shouldTryDiesel: Bool? = nil,
        swapVersion: Int? = nil,
        swapMode: ApiSwapMode? = nil,
        walletVersion: String? = nil,
        routes: [[ApiSwapRoute]]? = nil,
        toAddress: String? = nil,
        payoutExtraId: String? = nil,
        networkFee: MDouble? = nil,
        swapFee: MDouble? = nil,
        ourFee: MDouble? = nil,
        dieselFee: MDouble? = nil,
        needsApprove: Bool? = nil
    ) {
        self.from = from
        self.to = to
        self.fromAddress = fromAddress
        self.historyAddress = historyAddress
        self.dexLabel = dexLabel
        self.dexRouterLabel = dexRouterLabel
        self.cexLabel = cexLabel
        self.fromAmount = fromAmount
        self.toAmount = toAmount
        self.toMinAmount = toMinAmount
        self.slippage = slippage
        self.shouldTryDiesel = shouldTryDiesel
        self.swapVersion = swapVersion
        self.swapMode = swapMode
        self.walletVersion = walletVersion
        self.routes = routes
        self.toAddress = toAddress
        self.payoutExtraId = payoutExtraId
        self.networkFee = networkFee
        self.swapFee = swapFee
        self.ourFee = ourFee
        self.dieselFee = dieselFee
        self.needsApprove = needsApprove
    }
}
