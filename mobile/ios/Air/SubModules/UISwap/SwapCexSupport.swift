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
    ) async throws -> ApiActivity? {
        let createResult = try await Api.swapCexCreateTransaction(accountId: accountId, password: passcode, params: params)
        if shouldTransfer {
            
            let amount = createResult.swap.fromAmount.bigintAmount(decimals: sellingToken.decimals)
            
            guard let toAddress = createResult.swap.cex?.payinAddress else {
                throw BridgeCallError.customMessage("Missing payin address", nil)
            }

            guard let networkFee = createResult.swap.networkFee else {
                throw BridgeCallError.customMessage("Missing network fee", createResult)
            }
            let nativeDecimals = sellingToken.chain.nativeToken.decimals
            let fee = networkFee.bigintAmount(decimals: nativeDecimals)

            let options = ApiSubmitTransferOptions(
                accountId: accountId,
                toAddress: toAddress,
                amount: amount,
                payload: nil,
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
                throw BridgeCallError(message: error, payload: result)
            }
            return nil
        } else {
            return createResult.activity
        }
    }
}
