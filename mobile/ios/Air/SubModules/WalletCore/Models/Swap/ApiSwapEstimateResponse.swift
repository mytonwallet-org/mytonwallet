//
//  ApiSwapEstimateResponse.swift
//  MyTonWalletAir
//
//  Created by nikstar on 31.08.2025.
//


public struct ApiSwapEstimateResponse: Equatable, Codable {
    
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
    
    public static func ==(lhs: Self, rhs: Self) -> Bool {
        lhs.from == rhs.from &&
        lhs.to == rhs.to &&
        lhs.slippage == rhs.slippage &&
        lhs.fromAmount == rhs.fromAmount &&
        lhs.toAmount == rhs.toAmount &&
        lhs.fromAddress == rhs.fromAddress &&
        lhs.shouldTryDiesel == rhs.shouldTryDiesel &&
        lhs.swapVersion == rhs.swapVersion &&
        lhs.toncoinBalance == rhs.toncoinBalance &&
        lhs.walletVersion == rhs.walletVersion &&
        lhs.isFromAmountMax == rhs.isFromAmountMax &&
        lhs.toMinAmount == rhs.toMinAmount &&
        lhs.impact == rhs.impact &&
        lhs.dexLabel == rhs.dexLabel &&
        lhs.dieselStatus == rhs.dieselStatus &&
//        lhs.other == rhs.other &&
        lhs.networkFee == rhs.networkFee &&
        lhs.realNetworkFee == rhs.realNetworkFee &&
        lhs.swapFee == rhs.swapFee &&
        lhs.swapFeePercent == rhs.swapFeePercent &&
        lhs.ourFee == rhs.ourFee &&
        lhs.ourFeePercent == rhs.ourFeePercent &&
        lhs.dieselFee == rhs.dieselFee
    }
}

