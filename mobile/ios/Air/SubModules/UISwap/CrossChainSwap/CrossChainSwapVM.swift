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

private let log = Log("CrossChainSwapVM")

class CrossChainSwapVM {
    
    // MARK: - Initializer
    let sellingToken: (ApiToken?, BigInt)
    let buyingToken: (ApiToken?, BigInt)
    let swapType: SwapType
    private let swapFee: MDouble
    private let networkFee: MDouble
    // payin address for cex to ton swaps
    let payinAddress: String?
    let exchangerTxId: String?
    let dt: Date?
    
    var addressInputString: String = ""

    init(sellingToken: (ApiToken?, BigInt),
         buyingToken: (ApiToken?, BigInt),
         swapType: SwapType,
         swapFee: MDouble,
         networkFee: MDouble,
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

    func cexFromTonSwap(toAddress: String, passcode: String, onTaskDone: @escaping ((any Error)?) -> Void) {
        let cexFromTonSwapParams = ApiSwapCexCreateTransactionParams(
            from: sellingToken.0?.swapIdentifier ?? "",
            fromAmount: MDouble(sellingToken.1.doubleAbsRepresentation(decimals: sellingToken.0?.decimals ?? 9)),
            fromAddress: AccountStore.account?.addressByChain[TON_CHAIN] ?? "",
            to: buyingToken.0?.swapIdentifier ?? "",
            toAddress: toAddress,
            swapFee: swapFee,
            networkFee: networkFee
        )
        Task {
            do {
                _ = try await SwapCexSupport.swapCexCreateTransaction(
                    sellingToken: sellingToken.0,
                    params: cexFromTonSwapParams,
                    shouldTransfer: true,
                    passcode: passcode
                )
                onTaskDone(nil)
            } catch {
                log.error("SwapCexSupport.swapCexCreateTransaction: \(error, .public)")
                onTaskDone(error)
            }
        }
    }

}
