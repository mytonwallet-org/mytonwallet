//
//  ApiSwapEstimateResponse.swift
//  MyTonWalletAir
//
//  Created by nikstar on 31.08.2025.
//


public struct ApiSwapEstimateResponse: Equatable, Hashable, Codable, Sendable {
    
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
    public var dexLabel: ApiSwapDexLabel?
    public var dieselStatus: DieselStatus
    /// only in v2
    public var other: [ApiSwapEstimateVariant]?
    /// only in v3
    public var routes: [[ApiSwapRoute]]?
    // Fees
    public var networkFee: MDouble
    public var realNetworkFee: MDouble
    public var swapFee: MDouble
    public var swapFeePercent: Double?
    public var ourFee: MDouble?
    public var ourFeePercent: Double?
    public var dieselFee: MDouble?
    
    public mutating func updateFromVariant(_ variant: ApiSwapEstimateVariant) {
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

