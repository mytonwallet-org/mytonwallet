//
//  SwapCexSupport.swift
//  UISwap
//
//  Created by nikstar on 31.08.2025.
//

import Foundation
import WalletCore
import WalletContext

enum SwapCexSupport {
    public static func swapCexCreateTransaction(
        sellingToken: ApiToken?,
        params: ApiSwapCexCreateTransactionParams,
        shouldTransfer: Bool,
        passcode: String
    ) async throws -> ApiActivity? {
        guard let sellingToken else {
            return nil
        }
        let createResult = try await Api.swapCexCreateTransaction(accountId: AccountStore.accountId!, password: passcode, params: params)
        if shouldTransfer {
            
            let amountValue = createResult.swap.fromAmount.value
            let amount: BigInt = doubleToBigInt(amountValue, decimals: sellingToken.decimals)
            
            let networkFeeValue = createResult.swap.networkFee?.value
            let networkFee = networkFeeValue.map { doubleToBigInt($0, decimals: sellingToken.decimals) }
            
            let toAddress = createResult.swap.cex?.payinAddress
            
            guard let toAddress, let accountId = AccountStore.accountId else {
                return nil
            }
            let checkOptions = ApiCheckTransactionDraftOptions(
                accountId: accountId,
                toAddress: toAddress,
                amount: amount,
                payload: nil,
                stateInit: nil,
                tokenAddress: sellingToken.tokenAddress,
                allowGasless: false
            )
            let draft = try await Api.checkTransactionDraft(chain: sellingToken.chainValue, options: checkOptions)
            let options = ApiSubmitTransferOptions(
                accountId: accountId,
                toAddress: toAddress,
                amount: amount,
                payload: nil,
                stateInit: nil,
                tokenAddress: sellingToken.tokenAddress,
                realFee: draft.realFee,
                isGasless: false,
                dieselAmount: nil,
                isGaslessWithStars: nil,
                password: passcode,
                fee: draft.fee,
                noFeeCheck: nil
            )
            _ = try await Api.swapCexSubmit(chain: sellingToken.chainValue, options: options, swapId: createResult.swap.id)
            return nil
        } else {
            return createResult.activity
        }
    }
}
