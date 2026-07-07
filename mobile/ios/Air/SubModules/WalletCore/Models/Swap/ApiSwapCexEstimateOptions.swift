//
//  ApiSwapCexEstimateOptions.swift
//  MyTonWalletAir
//
//  Created by nikstar on 31.08.2025.
//

public struct ApiSwapCexEstimateOptions: Encodable, Sendable {
    public let from: String
    public let to: String
    public let fromAmount: MDouble
    public let fromAddress: String?
    public let toAddress: String?
    public let cexLabel: ApiSwapCexLabel?
    public let isFromAmountMax: Bool?
    
    public init(
        from: String,
        to: String,
        fromAmount: MDouble,
        fromAddress: String?,
        toAddress: String?,
        cexLabel: ApiSwapCexLabel?,
        isFromAmountMax: Bool? = nil
    ) {
        self.from = from
        self.to = to
        self.fromAmount = fromAmount
        self.fromAddress = fromAddress
        self.toAddress = toAddress
        self.cexLabel = cexLabel
        self.isFromAmountMax = isFromAmountMax
    }
}
