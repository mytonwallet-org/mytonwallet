
import Foundation

extension Api {

    public struct SwapEstimateRequest: Codable {
        public let from: String
        public let to: String
        public let slippage: Double
        public let fromAmount: MDouble?
        public let toAmount: MDouble?
        public let fromAddress: String
        public let shouldTryDiesel: Bool?
        public let swapVersion: Int?
        public let toncoinBalance: MDouble?
        public let walletVersion: String?
        public let isFromAmountMax: Bool?
        
        public init(from: String, to: String, slippage: Double, fromAmount: MDouble?, toAmount: MDouble?, fromAddress: String, shouldTryDiesel: Bool?, swapVersion: Int?, toncoinBalance: MDouble?, walletVersion: String?, isFromAmountMax: Bool?) {
            self.from = from
            self.to = to
            self.slippage = slippage
            self.fromAmount = fromAmount
            self.toAmount = toAmount
            self.fromAddress = fromAddress
            self.shouldTryDiesel = shouldTryDiesel
            self.swapVersion = swapVersion
            self.toncoinBalance = toncoinBalance
            self.walletVersion = walletVersion
            self.isFromAmountMax = isFromAmountMax
        }
    }

    public struct SwapEstimateVariant: Equatable, Hashable, Codable, Sendable {
        public let toAmount: MDouble
        public let fromAmount: MDouble
        public let toMinAmount: MDouble
        public let impact: Double
        public let dexLabel: ApiSwapDexLabel
        // Fees
        public let networkFee: MDouble
        public let realNetworkFee: MDouble
        public let swapFee: MDouble
        public let swapFeePercent: Double?
        public let ourFee: MDouble
        public let dieselFee: MDouble?
    }

    public struct SwapEstimateResponse: Equatable, Hashable, Codable, Sendable {
        
        public var from: String
        public var to: String
        public var slippage: Double
        public var fromAmount: MDouble?
        public var toAmount: MDouble?
        public var fromAddress: String?
        public var shouldTryDiesel: Bool?
        public var swapVersion: Int?
        public var toncoinBalance: MDouble?
        public var walletVersion: String?
        public var isFromAmountMax: Bool?
        public var toMinAmount: MDouble
        public var impact: Double
        public var dexLabel: ApiSwapDexLabel
        public var dieselStatus: DieselStatus
        public var other: [SwapEstimateVariant]? // v2
//        routes?: ApiSwapRoute[][]; // Only in V3
        // Fees
        public var networkFee: MDouble
        public var realNetworkFee: MDouble
        public var swapFee: MDouble
        public var swapFeePercent: Double?
        public var ourFee: MDouble?
        public var ourFeePercent: Double?
        public var dieselFee: MDouble?
        
        public mutating func updateFromVariant(_ variant: SwapEstimateVariant) {
            self.toAmount = variant.toAmount
            self.fromAmount = variant.fromAmount
            self.toMinAmount = variant.toMinAmount
            self.impact = variant.impact
            self.dexLabel = variant.dexLabel
            self.networkFee = variant.networkFee
            self.realNetworkFee = variant.realNetworkFee
            self.swapFee = variant.swapFee
            self.swapFeePercent = variant.swapFeePercent
            self.ourFee = variant.ourFee
            self.dieselFee = variant.dieselFee
        }
    }
}
