//
//  Api+Swap.swift
//  WalletCore
//
//  Created by Sina on 5/11/24.
//

import Foundation
import WalletContext


extension Api {
    
    public static func swapEstimate(accountId: String, request: SwapEstimateRequest) async throws -> SwapEstimateResponse {
        try await bridge.callApi("swapEstimate", accountId, request, decoding: SwapEstimateResponse.self)
    }
    
    public struct SwapTransferData: Codable {    
        public struct Transfer: Codable {
            public let toAddress: String
            public let amount: String
            public let payload: String?
        }
        
        public let id: String
        public var transfers: [Transfer]
        public let fee: BigInt?
    }

    public static func swapBuildTransfer(accountId: String, password: String, request: SwapBuildRequest) async throws -> SwapTransferData {
        try await bridge.callApi("swapBuildTransfer", accountId, password, request, decoding: SwapTransferData.self)
    }
    
    public struct SwapSubmitResult: Codable {
        public let paymentLink: String?
    }

    public static func swapSubmit(accountId: String, password: String, transfers: [SwapTransferData.Transfer], historyItem: SwapHistoryItem, isGasless: Bool?) async throws -> SwapSubmitResult {
        try await bridge.callApi("swapSubmit", accountId, password, transfers, historyItem, isGasless, decoding: SwapSubmitResult.self)
    }
    
    
    // Mark: - Swap assets
    
    public struct SwapCEXEstimateOptions: Encodable {
        public let from: String
        public let to: String
        public let fromAmount: String
        public init(from: String,
                    to: String,
                    fromAmount: String) {
            self.from = from
            self.to = to
            self.fromAmount = fromAmount
        }
    }

    /// - Important: call through TokenStore
    internal static func swapGetAssets() async throws -> [ApiToken] {
        return try await bridge.callApi("swapGetAssets", decoding: [ApiToken].self)
    }

    public static func swapGetPairs(symbolOrMinter: String) async throws -> [MPair] {
        if let pairs = TokenStore.swapPairs[symbolOrMinter] {
            return pairs
        }
        let pairs = try await bridge.callApi("swapGetPairs", symbolOrMinter == "toncoin" ? "TON" : symbolOrMinter, decoding: [MPair].self)
        TokenStore.swapPairs[symbolOrMinter] = pairs
        return pairs
    }
    
    public static func swapCexEstimate(swapEstimateOptions: SwapCEXEstimateOptions) async throws -> MSwapEstimate? {
        let successData = try await bridge.callApiRaw("swapCexEstimate", swapEstimateOptions)
        let dict = try (successData as? [String: Any]).orThrow()
        return MSwapEstimate(dictionary: dict)
    }
    
    
    // MARK: - CEX
    
    public struct SwapCexParams: Encodable {
        public let from: String
        public let fromAmount: String   // Always TON address
        public let fromAddress: String
        public let to: String
        public let toAddress: String
        public let swapFee: String
        public let networkFee: String?

        public init(from: String,
                    fromAmount: String,
                    fromAddress: String,
                    to: String,
                    toAddress: String,
                    swapFee: String,
                    networkFee: String?) {
            self.from = from
            self.fromAmount = fromAmount
            self.fromAddress = fromAddress
            self.to = to
            self.toAddress = toAddress
            self.swapFee = swapFee
            self.networkFee = networkFee
        }
    }
    
    public static func swapCexCreateTransaction(
        sellingToken: ApiToken?,
        params: SwapCexParams,
        shouldTransfer: Bool,
        passcode: String,
        callback: @escaping (Result<(ApiActivity?), BridgeCallError>) -> Void
    ) {
        guard let sellingToken else {
            return
        }
        shared?.webViewBridge.callApi(
            methodName: "swapCexCreateTransaction",
            args: [
                AnyEncodable(AccountStore.accountId),
                AnyEncodable(passcode),
                AnyEncodable(params)
            ],
            callback: { res in
                switch res {
                case .success(let successData):
                    if shouldTransfer {
                        if let successData = successData as? [String: Any],
                           let swap = successData["swap"] as? [String: Any] {
                            let amount: BigInt
                            if let amountStr = swap["fromAmount"] as? String,
                               let amountValue = Double(amountStr) {
                                amount = doubleToBigInt(amountValue, decimals: sellingToken.decimals)
                            } else {
                                return
                            }
                            let swapFee: BigInt
                            if let networkFeeStr = swap["networkFee"] as? String,
                               let networkFeeValue = Double(networkFeeStr) {
                                swapFee = doubleToBigInt(networkFeeValue, decimals: sellingToken.decimals)
                            } else {
                                return
                            }
                            let toAddress: String
                            if let cex = swap["cex"] as? [String: Any],
                               let payinAddress = cex["payinAddress"] as? String {
                                toAddress = payinAddress
                            } else {
                                return
                            }

                            Task {
                                do {
                                    let checkOptions = CheckTransactionDraftOptions(
                                        accountId: AccountStore.accountId!,
                                        toAddress: toAddress,
                                        amount: amount,
                                        tokenAddress: sellingToken.tokenAddress,
                                        data: nil,
                                        stateInit: nil,
                                        shouldEncrypt: nil,
                                        isBase64Data: nil,
                                        forwardAmount: nil,
                                        allowGasless: false
                                    )
                                    let draft = try await Api.checkTransactionDraft(chain: sellingToken.chain, options: checkOptions)
                                    let options = SubmitTransferOptions(
                                        accountId: AccountStore.accountId!,
                                        password: passcode,
                                        toAddress: draft.resolvedAddress ?? toAddress,
                                        amount: amount,
                                        comment: nil,
                                        tokenAddress: sellingToken.tokenAddress,
                                        fee: draft.fee,
                                        realFee: draft.realFee,
                                        shouldEncrypt: nil,
                                        isBase64Data: nil,
                                        withDiesel: false,
                                        dieselAmount: nil,
                                        stateInit: nil,
                                        forwardAmount: nil,
                                        noFeeCheck: nil,
                                    )
                                    _ = try await Api.submitTransfer(chain: sellingToken.chainValue, options: options)
                                    callback(.success(nil))
                                } catch {
                                    callback(.failure(BridgeCallError.apiReturnedError(error: error.localizedDescription, data: error)))
                                }
                            }
                        }
                    } else {
                        DispatchQueue.main.async {
                            if let successData = successData as? [String: Any],
                               let dict = successData["activity"] as? [String: Any],
                               let activity = try? ApiActivity(dictionary: dict) {
                                callback(.success(activity))
                            } else {
                                callback(.failure(.unknown()))
                            }
                        }
                    }
                case .failure(let failure):
                    DispatchQueue.main.async {
                        callback(.failure(failure))
                    }
                }
            })
    }
}
