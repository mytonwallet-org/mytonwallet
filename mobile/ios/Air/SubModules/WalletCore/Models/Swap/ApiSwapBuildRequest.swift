
import Foundation

public struct ApiSwapBuildRequest: Codable {
    public let from: String
    public let to: String
    public let fromAddress: String
    public let dexLabel: ApiSwapDexLabel?
    public let fromAmount: MDouble
    public let toAmount: MDouble
    public let toMinAmount: MDouble
    public let slippage: Double
    public let shouldTryDiesel: Bool?
    public let swapVersion: Int?
    public let walletVersion: String?
    public let routes: [[ApiSwapRoute]]?
    // Fees
    public let networkFee: MDouble?
    public let swapFee: MDouble
    public let ourFee: MDouble?
    public let dieselFee: MDouble?
    
    public init(from: String, to: String, fromAddress: String, dexLabel: ApiSwapDexLabel?, fromAmount: MDouble, toAmount: MDouble, toMinAmount: MDouble, slippage: Double, shouldTryDiesel: Bool?, swapVersion: Int?, walletVersion: String?, routes: [[ApiSwapRoute]]?, networkFee: MDouble?, swapFee: MDouble, ourFee: MDouble?, dieselFee: MDouble?) {
        self.from = from
        self.to = to
        self.fromAddress = fromAddress
        self.dexLabel = dexLabel
        self.fromAmount = fromAmount
        self.toAmount = toAmount
        self.toMinAmount = toMinAmount
        self.slippage = slippage
        self.shouldTryDiesel = shouldTryDiesel
        self.swapVersion = swapVersion
        self.walletVersion = walletVersion
        self.routes = routes
        self.networkFee = networkFee
        self.swapFee = swapFee
        self.ourFee = ourFee
        self.dieselFee = dieselFee
    }
}
