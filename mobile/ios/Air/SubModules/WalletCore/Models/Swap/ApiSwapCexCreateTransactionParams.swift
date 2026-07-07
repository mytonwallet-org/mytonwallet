//
//  ApiSwapCexCreateTransactionParams.swift
//  MyTonWalletAir
//
//  Created by nikstar on 31.08.2025.
//

public struct ApiSwapCexCreateTransactionParams: Encodable, Sendable {
    public let from: String
    public let fromAmount: MDouble
    /// Source-chain refund/sender address for Near Intents; TON history address for Changelly.
    public let fromAddress: String
    /// TON address that owns/authenticates the backend swap history row.
    public let historyAddress: String?
    public let cexLabel: ApiSwapCexLabel?
    public let to: String
    public let toAmount: MDouble?
    public let toAddress: String
    public let payoutExtraId: String?
    public let swapFee: MDouble
    public let networkFee: MDouble?

    public init(from: String, fromAmount: MDouble, fromAddress: String, historyAddress: String?, cexLabel: ApiSwapCexLabel?, to: String, toAmount: MDouble?, toAddress: String, payoutExtraId: String? = nil, swapFee: MDouble, networkFee: MDouble?) {
        self.from = from
        self.fromAmount = fromAmount
        self.fromAddress = fromAddress
        self.historyAddress = historyAddress
        self.cexLabel = cexLabel
        self.to = to
        self.toAmount = toAmount
        self.toAddress = toAddress
        self.payoutExtraId = payoutExtraId
        self.swapFee = swapFee
        self.networkFee = networkFee
    }
}
