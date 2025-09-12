//
//  ApiSwapCexCreateTransactionParams.swift
//  MyTonWalletAir
//
//  Created by nikstar on 31.08.2025.
//

public struct ApiSwapCexCreateTransactionParams: Encodable {
    public let from: String
    public let fromAmount: MDouble   // Always TON address
    public let fromAddress: String
    public let to: String
    public let toAddress: String
    public let swapFee: MDouble
    public let networkFee: MDouble?

    public init(from: String, fromAmount: MDouble, fromAddress: String, to: String, toAddress: String, swapFee: MDouble, networkFee: MDouble?) {
        self.from = from
        self.fromAmount = fromAmount
        self.fromAddress = fromAddress
        self.to = to
        self.toAddress = toAddress
        self.swapFee = swapFee
        self.networkFee = networkFee
    }
}
