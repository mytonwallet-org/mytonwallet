//
//  CrossChainSwapVM.swift
//  UISwap
//
//  Created by Sina on 5/11/24.
//

import Foundation
import UIComponents
import WalletCore
import WalletContext


class CrossChainSwapVM {
    
    // MARK: - Initializer
    let sellingToken: (ApiToken?, BigInt)
    let buyingToken: (ApiToken?, BigInt)
    let swapType: SwapType
    private let swapFee: String
    private let networkFee: String
    // payin address for cex to ton swaps
    let payinAddress: String?
    let exchangerTxId: String?
    let dt: Date?
    
    var addressInputString: String = ""

    init(sellingToken: (ApiToken?, BigInt),
         buyingToken: (ApiToken?, BigInt),
         swapType: SwapType,
         swapFee: String,
         networkFee: String,
         payinAddress: String?,
         exchangerTxId: String?,
         dt: Date?) {
        self.sellingToken = sellingToken
        self.buyingToken = buyingToken
        self.swapType = swapType
        self.swapFee = swapFee
        self.networkFee = networkFee
        self.payinAddress = payinAddress
        self.exchangerTxId = exchangerTxId
        self.dt = dt
    }

    func cexFromTonSwap(toAddress: String, passcode: String, onTaskDone: @escaping (BridgeCallError?) -> Void) {
        let cexFromTonSwapParams = Api.SwapCexParams(
            from: sellingToken.0?.swapIdentifier ?? "",
            fromAmount: String(sellingToken.1.doubleAbsRepresentation(decimals: sellingToken.0?.decimals ?? 9)),
            fromAddress: AccountStore.account?.tonAddress ?? "",
            to: buyingToken.0?.swapIdentifier ?? "",
            toAddress: toAddress,
            swapFee: swapFee,
            networkFee: networkFee
        )
        Api.swapCexCreateTransaction(sellingToken: sellingToken.0,
                                    params: cexFromTonSwapParams,
                                    shouldTransfer: true,
                                    passcode: passcode) { res in
            switch res {
            case .success(_):
                onTaskDone(nil)
                break
            case .failure(let failure):
                onTaskDone(failure)
            }
        }
    }

}
