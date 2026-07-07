//
//  ApiSwapEstimateVariant.swift
//  MyTonWalletAir
//
//  Created by nikstar on 31.08.2025.
//

public struct ApiSwapEstimateVariant: Equatable, Codable, Sendable {
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

    public static func ==(lhs: Self, rhs: Self) -> Bool {
        lhs.fromAmount == rhs.fromAmount &&
        lhs.toAmount == rhs.toAmount &&
        lhs.toMinAmount == rhs.toMinAmount &&
        lhs.impact == rhs.impact &&
        lhs.dexLabel == rhs.dexLabel &&
        lhs.other == rhs.other &&
        lhs.networkFee == rhs.networkFee &&
        lhs.realNetworkFee == rhs.realNetworkFee &&
        lhs.swapFee == rhs.swapFee &&
        lhs.swapFeePercent == rhs.swapFeePercent &&
        lhs.ourFee == rhs.ourFee &&
        lhs.dieselFee == rhs.dieselFee
    }
}
