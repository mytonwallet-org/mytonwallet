//
//  ApiSwapEstimateVariant.swift
//  MyTonWalletAir
//
//  Created by nikstar on 31.08.2025.
//

public struct ApiSwapEstimateVariant: Equatable, Hashable, Codable, Sendable {
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
