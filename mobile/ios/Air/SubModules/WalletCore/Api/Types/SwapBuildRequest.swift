
import Foundation

extension Api {

    public struct SwapBuildRequest: Codable {
        public let from: String
        public let to: String
        public let fromAddress: String
        public let dexLabel: ApiSwapDexLabel
        public let fromAmount: MDouble
        public let toAmount: MDouble
        public let toMinAmount: MDouble
        public let slippage: Double
        public let shouldTryDiesel: Bool?
        public let swapVersion: Int?
        public let walletVersion: String?
        // Fees
        public let networkFee: MDouble?
        public let swapFee: MDouble
        public let ourFee: MDouble?
        public let dieselFee: MDouble?
        
        public init(from: String, to: String, fromAddress: String, dexLabel: ApiSwapDexLabel, fromAmount: MDouble, toAmount: MDouble, toMinAmount: MDouble, slippage: Double, shouldTryDiesel: Bool?, swapVersion: Int?, walletVersion: String?, networkFee: MDouble?, swapFee: MDouble, ourFee: MDouble?, dieselFee: MDouble?) {
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
            self.networkFee = networkFee
            self.swapFee = swapFee
            self.ourFee = ourFee
            self.dieselFee = dieselFee
        }
    }
    
    public struct SwapHistoryItem: Codable {
        public let id: String
        public let timestamp: Int64
        public let lt: Int64?
        public let from: String
        public let fromAmount: MDouble
        public let to: String
        public let toAmount: MDouble
        public let networkFee: MDouble?
        public let swapFee: MDouble
        public let ourFee: MDouble?
        
        public enum Status: String, Codable {
            case pending = "pending"
            case completed = "completed"
            case failed = "failed"
            case expired = "expired"
        }
        public let status: Status
        
        public let txIds: [String]
        public let isCanceled: Bool?
        public let cex: ApiSwapCexTransaction?
    }
    
    public static func makeSwapHistoryItem(swapBuildRequest: SwapBuildRequest, swapTransferData: SwapTransferData) -> SwapHistoryItem {
        SwapHistoryItem(id: swapTransferData.id,
                        timestamp: Int64(Date().timeIntervalSince1970 * 1000),
                        lt: nil,
                        from: swapBuildRequest.from,
                        fromAmount: swapBuildRequest.fromAmount,
                        to: swapBuildRequest.to,
                        toAmount: swapBuildRequest.toAmount,
                        networkFee:  swapBuildRequest.networkFee,
                        swapFee: swapBuildRequest.swapFee,
                        ourFee: swapBuildRequest.ourFee,
                        status: .pending,
                        txIds: [],
                        isCanceled: nil,
                        cex: nil)
    }
}
