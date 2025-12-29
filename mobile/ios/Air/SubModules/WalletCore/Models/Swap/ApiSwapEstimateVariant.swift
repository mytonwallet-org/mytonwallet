//
//  ApiSwapEstimateVariant.swift
//  MyTonWalletAir
//
//  Created by nikstar on 31.08.2025.
//

public struct ApiSwapEstimateVariant: Codable {
    public let fromAmount: MDouble
    public let toAmount: MDouble
    public let toMinAmount: MDouble
    public let impact: Double
    public let dexLabel: ApiSwapDexLabel?
    public let other: [ApiSwapEstimateVariant]?
    public let routes: [[ApiSwapRoute]]?
    // Fees
    public let networkFee: MDouble
    public let realNetworkFee: MDouble
    public let swapFee: MDouble
    public let swapFeePercent: Double?
    public let ourFee: MDouble
    public let dieselFee: MDouble?
}
