import Foundation
import WalletCore
import WalletContext

enum SwapCexSupport {
    static func swapCexCreateTransaction(
        accountId: String,
        sellingToken: ApiToken,
        params: ApiSwapCexCreateTransactionParams,
        shouldTransfer: Bool,
        passcode: String
    ) async throws -> SwapExecutionResult {
        let createResult = try await Api.swapCexCreateTransaction(accountId: accountId, password: passcode, params: params)
        if shouldTransfer {
            
            let amount = createResult.swap.fromAmount.bigintAmount(decimals: sellingToken.decimals)
            
            guard let toAddress = createResult.swap.cex?.payinAddress else {
                throw SdkError.unexpected(message: "Missing payin address")
            }

            guard let networkFee = createResult.swap.networkFee else {
                throw SdkError.unexpected(message: "Missing network fee", context: createResult)
            }
            let nativeDecimals = sellingToken.chain.nativeToken.decimals
            let fee = networkFee.bigintAmount(decimals: nativeDecimals)
            let payload = try makeDepositMemoPayload(
                cexLabel: createResult.swap.cexLabel ?? params.cexLabel,
                memo: createResult.swap.cex?.payinExtraId?.nilIfEmpty,
                sourceChain: sellingToken.chain,
                createResult: createResult
            )

            let options = ApiSubmitTransferOptions(
                accountId: accountId,
                toAddress: toAddress,
                amount: amount,
                payload: payload,
                stateInit: nil,
                tokenAddress: sellingToken.tokenAddress,
                realFee: nil,
                isGasless: false,
                dieselAmount: nil,
                isGaslessWithStars: nil,
                gaslessTransaction: nil,
                password: passcode,
                fee: fee,
                noFeeCheck: nil
            )
            let result = try await Api.swapCexSubmit(chain: sellingToken.chain, options: options, swapId: createResult.swap.id)
            if let error = result.error {
                throw SdkError.apiReturnedError(error: error, context: result)
            }
            return SwapExecutionResult(activity: nil, swapId: createResult.swap.id, mfaRequestHash: result.mfaRequestHash)
        } else {
            return SwapExecutionResult(activity: createResult.activity, swapId: nil, mfaRequestHash: nil)
        }
    }

    private static func makeDepositMemoPayload(
        cexLabel: ApiSwapCexLabel?,
        memo: String?,
        sourceChain: ApiChain,
        createResult: ApiSwapCexCreateTransactionResult
    ) throws -> AnyTransferPayload? {
        guard cexLabel == .nearIntents, let memo else {
            return nil
        }

        guard canAutoSubmitDepositMemo(sourceChain) else {
            throw SdkError.unexpected(message: "Unsupported auto-submitted deposit memo chain", context: createResult)
        }

        return .comment(text: memo, shouldEncrypt: false)
    }

    private static func canAutoSubmitDepositMemo(_ chain: ApiChain) -> Bool {
        chain == .ton || chain == .solana
    }
}
