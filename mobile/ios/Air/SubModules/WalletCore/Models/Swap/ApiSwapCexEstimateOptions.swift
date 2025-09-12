//
//  ApiSwapCexEstimateOptions.swift
//  MyTonWalletAir
//
//  Created by nikstar on 31.08.2025.
//

public struct ApiSwapCexEstimateOptions: Encodable {
    public let from: String
    public let to: String
    public let fromAmount: String
    
    public init(from: String, to: String, fromAmount: String) {
        self.from = from
        self.to = to
        self.fromAmount = fromAmount
    }
}
