//
//  ApiSwapEstimateRequest.swift
//  MyTonWalletAir
//
//  Created by nikstar on 31.08.2025.
//

public struct ApiSwapEstimateRequest: Codable {
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

