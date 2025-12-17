//
//  SwapVM.swift
//  UISwap
//
//  Created by Sina on 5/11/24.
//

import Foundation
import UIKit
import UIComponents
import WalletCore
import WalletContext
import SwiftUI

private let log = Log("SwapVM")

protocol SwapVMDelegate: AnyObject {
    @MainActor func updateIsValidPair()
    @MainActor func receivedEstimateData(swapEstimate: ApiSwapEstimateResponse?, selectedDex: ApiSwapDexLabel?, lateInit: ApiSwapCexEstimateResponse.LateInitProperties?)
    @MainActor func receivedCexEstimate(swapEstimate: ApiSwapCexEstimateResponse)
}


@MainActor
final class SwapVM: ObservableObject {
    
    @Published private(set) var swapEstimate: ApiSwapEstimateResponse? = nil
    @Published private(set) var lateInit: ApiSwapCexEstimateResponse.LateInitProperties? = nil
    @Published private(set) var cexEstimate: ApiSwapCexEstimateResponse? = nil
    @Published private(set) var isValidPair = true
    @Published private(set) var swapType = SwapType.onChain
    @Published private(set) var dex: ApiSwapDexLabel? = nil
    @Published private(set) var slippage: Double = 5.0
    
    private weak var delegate: SwapVMDelegate?
    private weak var tokensSelector: SwapSelectorsVM?
    private var prevPair = ""
    
    init(delegate: SwapVMDelegate, tokensSelector: SwapSelectorsVM) {
        self.delegate = delegate
        self.tokensSelector =  tokensSelector
    }
    
    // MARK: - Swap data changed
    
    func updateSwapType(selling: TokenAmount, buying: TokenAmount) {
        swapType = getSwapType(fromToken: selling.token, toToken: buying.token)
    }
    
    func updateDexPreference(_ dex: ApiSwapDexLabel?) {
        self.dex = dex
        delegate?.receivedEstimateData(swapEstimate: swapEstimate, selectedDex: dex, lateInit: lateInit)
    }
    
    func updateSlippage(_ slippage: Double) {
        self.slippage = slippage
    }
    
    /// called whenever swap data changed to receive new swap estimate data
    func swapDataChanged(changedFrom: SwapSide, selling: TokenAmount, buying: TokenAmount) async throws {

        let accountId = try AccountStore.accountId.orThrow()
        var selling = selling
        var buying = buying
        
        // to get full token object containing minter address!
        selling.token = TokenStore.tokens[selling.token.slug] ?? selling.token
        buying.token = TokenStore.tokens[buying.token.slug] ?? buying.token

        // validate pair
        let newPair = "\(selling.token.slug)||\(buying.token.slug)"
        if prevPair != newPair {
//            updateEstimate(nil, lateInit: nil)
            isValidPair = true
            prevPair = newPair
            if selling.token.chain == TON_CHAIN && buying.token.chain == TON_CHAIN && selling.token.slug != buying.token.slug {
                isValidPair = true
            } else {
                let pairs = try await Api.swapGetPairs(symbolOrMinter: selling.token.swapIdentifier)
                try Task.checkCancellation()
                isValidPair = pairs.contains(where: { p in p.slug == buying.token.slug })
            }
            delegate?.updateIsValidPair()
            if !isValidPair {
                return
            }
        }
        
        if selling.amount <= 0 && buying.amount <= 0 {
            return
        }
        
        // get estimation data
        let from = selling.token.swapIdentifier
        let to = buying.token.swapIdentifier
        
        if swapType != .onChain {
            let options: ApiSwapCexEstimateOptions
            if changedFrom == .selling {
                // normal request
                options = ApiSwapCexEstimateOptions(from: from,
                                                               to: to,
                                                               fromAmount: String(selling.amount.doubleAbsRepresentation(decimals: selling.token.decimals)))
            } else {
                // reversed request!
                options = ApiSwapCexEstimateOptions(from: to,
                                                               to: from,
                                                               fromAmount: String(buying.amount.doubleAbsRepresentation(decimals: buying.token.decimals)))
            }
            var swapEstimate = try await Api.swapCexEstimate(swapEstimateOptions: options)
            try Task.checkCancellation()
            
            if changedFrom == .buying {
                swapEstimate?.reverse()
            }
            if var swapEstimate {
                swapEstimate.calculateLateInitProperties(selling: selling, swapType: swapType)
                updateCexEstimate(swapEstimate)
            } else {
                throw NilError()
            }
            
        } else {
            let props = ApiSwapCexEstimateResponse.calculateLateInitProperties(selling: selling,
                                                                  swapType: swapType,
                                                                  networkFee: swapEstimate?.networkFee.value,
                                                                  dieselFee: swapEstimate?.dieselFee?.value,
                                                                  ourFeePercent: swapEstimate?.ourFeePercent)
            let fromAddress = try (AccountStore.account?.tonAddress).orThrow()
            let shouldTryDiesel = props.isEnoughNative == false
            let toncoinBalance = (BalanceStore.currentAccountBalances["toncoin"]).flatMap { MDouble.forBigInt($0, decimals: 9) }
            let walletVersion = AccountStore.account?.version
            let swapEstimateRequest = ApiSwapEstimateRequest(
                from: from,
                to: to,
                slippage: slippage,
                fromAmount: changedFrom == .selling ? MDouble.forBigInt(selling.amount, decimals: selling.token.decimals) : nil,
                toAmount: changedFrom == .buying ? MDouble.forBigInt(buying.amount, decimals: buying.token.decimals) : nil,
                fromAddress: fromAddress,
                shouldTryDiesel: shouldTryDiesel,
                swapVersion: nil,
                toncoinBalance: toncoinBalance,
                walletVersion: walletVersion,
                isFromAmountMax: nil
            )
            
            // On-chain swap estimate
            do {
                let swapEstimate = try await Api.swapEstimate(accountId: accountId, request: swapEstimateRequest)
                try Task.checkCancellation()
                let lateInit = ApiSwapCexEstimateResponse.calculateLateInitProperties(selling: selling,
                                                                         swapType: swapType,
                                                                         networkFee: swapEstimate.networkFee.value,
                                                                         dieselFee: swapEstimate.dieselFee?.value,
                                                                         ourFeePercent: swapEstimate.ourFeePercent)
                self.updateEstimate(swapEstimate, lateInit: lateInit)
            } catch {
                if !Task.isCancelled {
                    log.error("swapEstimate error \(error, .public)")
                    self.updateEstimate(nil, lateInit: nil)
                }
            }
        }
    }
    
    func updateEstimate(_ swapEstimate: ApiSwapEstimateResponse?, lateInit: ApiSwapCexEstimateResponse.LateInitProperties?) {
        self.swapEstimate = swapEstimate
        self.lateInit = lateInit
        Task {
            delegate?.receivedEstimateData(swapEstimate: swapEstimate, selectedDex: dex, lateInit: lateInit)
        }
    }
    
    func updateCexEstimate(_ swapEstimate: ApiSwapCexEstimateResponse) {
        self.cexEstimate = swapEstimate
        Task {
            delegate?.receivedCexEstimate(swapEstimate: swapEstimate)
        }
    }
    
    // MARK: Check for error
    ///  checks for swap error, returns nil if swap is possible
    func checkDexSwapError(swapEstimate: ApiSwapEstimateResponse, lateInit: ApiSwapCexEstimateResponse.LateInitProperties) -> String? {
        guard let tokensSelector else {
            return nil
        }
        var swapError: String? = nil
        let sellToken = TokenStore.tokens[tokensSelector.sellingToken.slug] ?? tokensSelector.sellingToken
        var balanceIn = BalanceStore.currentAccountBalances[sellToken.slug] ?? 0
        if sellToken.slug == "trx" && AccountStore.account?.isMultichain ?? false {
            balanceIn -= 1
        }
        if sellToken.isOnChain == true {
            if let sellingAmount = tokensSelector.sellingAmount, balanceIn < sellingAmount {
                swapError = lang("Insufficient Balance")
            }
        }
        if swapEstimate.toAmount?.value == 0 && lateInit.isEnoughNative == false {
            swapError = lang("Insufficient Balance")
        }
        if lateInit.isEnoughNative == false && (lateInit.isDiesel != true || swapEstimate.dieselStatus.canContinue != true) {
            if lateInit.isDiesel == true, let swapDieselError = swapEstimate.dieselStatus.errorString {
                swapError = swapDieselError
            } else {
                swapError = lang("Insufficient Balance")
            }
        }
        return swapError
    }
    
    func checkCexSwapError(swapEstimate: ApiSwapCexEstimateResponse) -> String? {
        guard let tokensSelector else {
            return nil
        }
        var swapError: String? = nil
        let sellToken = TokenStore.tokens[tokensSelector.sellingToken.slug] ?? tokensSelector.sellingToken
        var balanceIn = BalanceStore.currentAccountBalances[sellToken.slug] ?? 0
        if sellToken.slug == "trx" && AccountStore.account?.isMultichain ?? false {
            balanceIn -= 1
        }
        if sellToken.isOnChain == true {
            if let sellingAmount = tokensSelector.sellingAmount, balanceIn < sellingAmount {
                swapError = lang("Insufficient Balance")
            }
        }
        if swapEstimate.toAmount.value == 0 && swapEstimate.isEnoughNative == false {
            swapError = lang("Insufficient Balance")
        }
        if swapEstimate.isEnoughNative == false && (swapEstimate.isDiesel != true || swapEstimate.dieselStatus?.canContinue != true) {
            if swapEstimate.isDiesel == true, let swapDieselError = swapEstimate.dieselStatus?.errorString {
                swapError = swapDieselError
            } else {
                swapError = lang("Insufficient Balance")
            }
        }
        if let fromMin = swapEstimate.fromMin {
            if swapEstimate.fromAmount < fromMin {
                swapError = lang("Minimum amount", arg1: "\(fromMin) \(tokensSelector.sellingToken.symbol)")
            }
        }
        if let fromMax = swapEstimate.fromMax, fromMax > 0 {
            if swapEstimate.fromAmount > fromMax {
                swapError = lang("Maximum amount", arg1: "\(fromMax) \(tokensSelector.sellingToken.symbol)")
            }
        }
        if let toMin = swapEstimate.toMin {
            if swapEstimate.toAmount < toMin {
                swapError = lang("Minimum amount", arg1: "\(toMin) \(tokensSelector.buyingToken.symbol)")
            }
        }
        if let toMax = swapEstimate.toMax, toMax > 0 {
            if swapEstimate.toAmount > toMax {
                swapError = lang("Maximum amount", arg1: "\(toMax) \(tokensSelector.buyingToken.symbol)")
            }
        }
        return swapError
    }
    
    
    // MARK: - Swap now!
    func swapInChain(sellingToken: ApiToken, buyingToken: ApiToken, passcode: String, onTaskDone: @escaping (ApiActivity?, BridgeCallError?) -> ()) {
        Task {
            do {
                try await onChainSwap(passcode: passcode)
                onTaskDone(nil, nil)
            } catch {
                onTaskDone(nil, error as? BridgeCallError)
            }
        }
    }
    
    func swapNow(sellingToken: ApiToken, buyingToken: ApiToken, passcode: String, onTaskDone: @escaping (ApiActivity?, Error?) -> Void) {
        switch swapType {
        case .onChain:
            swapInChain(sellingToken: sellingToken, buyingToken: buyingToken, passcode: passcode, onTaskDone: onTaskDone)
        case .crosschainInsideWallet:
            crossChainToTonSwap(sellingToken: sellingToken, buyingToken: buyingToken, passcode: passcode, onTaskDone: onTaskDone)
        case .crosschainToWallet:
            crossChainToTonSwap(sellingToken: sellingToken, buyingToken: buyingToken, passcode: passcode, onTaskDone: onTaskDone)
        case .crosschainFromWallet:
            crossChainFromTonSwap(sellingToken: sellingToken, buyingToken: buyingToken, passcode: passcode, onTaskDone: onTaskDone)
        }
    }
    
    // MARK: - On-Chain swap
    private func onChainSwap(passcode: String) async throws {
        let swapEstimate = try self.swapEstimate.orThrow()
        let fromAddress = try (AccountStore.account?.tonAddress).orThrow()
        let walletVersion = AccountStore.account?.version
        let shouldTryDiesel = swapEstimate.networkFee.value > 0 &&
            BalanceStore.currentAccountBalances["toncoin"] ?? 0 < BigInt((swapEstimate.networkFee.value + 0.015) * 1e9) && swapEstimate.dieselStatus == .available
        
        let swapBuildRequest = ApiSwapBuildRequest(
            from: swapEstimate.from,
            to: swapEstimate.to,
            fromAddress: fromAddress,
            dexLabel: dex ?? swapEstimate.dexLabel,
            fromAmount: swapEstimate.fromAmount ?? .zero,
            toAmount: swapEstimate.toAmount ?? .zero,
            toMinAmount: swapEstimate.toMinAmount,
            slippage: self.slippage,
            shouldTryDiesel: shouldTryDiesel,
            swapVersion: nil,
            walletVersion: walletVersion,
            routes: swapEstimate.routes,
            networkFee: swapEstimate.realNetworkFee,
            swapFee: swapEstimate.swapFee,
            ourFee: swapEstimate.ourFee,
            dieselFee: swapEstimate.dieselFee
        )
        let accountId = try AccountStore.accountId.orThrow()
        let transferData = try await Api.swapBuildTransfer(accountId: accountId, password: passcode, request: swapBuildRequest)
        let historyItem = ApiSwapHistoryItem.makeFrom(swapBuildRequest: swapBuildRequest, swapTransferData: transferData)
        let result = try await Api.swapSubmit(accountId: accountId, password: passcode, transfers: transferData.transfers, historyItem: historyItem, isGasless: shouldTryDiesel)
        #if DEBUG
        log.info("\(result)")
        #endif
    }
    
    // MARK: - Cross-Chain to ton swap
    private func crossChainToTonSwap(sellingToken: ApiToken, buyingToken: ApiToken, passcode: String, onTaskDone: @escaping (ApiActivity?, (any Error)?) -> Void) {
        guard let swapEstimate = self.cexEstimate else {
            return
        }
        if let account = AccountStore.account {
            let fromAddress = account.addressByChain[sellingToken.chain]
            let toAddress = account.addressByChain[buyingToken.chain]
            let swapCexParams = ApiSwapCexCreateTransactionParams(
                from: sellingToken.swapIdentifier,
                fromAmount: swapEstimate.fromAmount,
                fromAddress: fromAddress ?? "",
                to: buyingToken.swapIdentifier,
                toAddress: toAddress ?? "",
                swapFee: swapEstimate.swapFee,
                networkFee: 0
            )
            Task {
                do {
                    _ = try await SwapCexSupport.swapCexCreateTransaction(
                        sellingToken: sellingToken,
                        params: swapCexParams,
                        shouldTransfer: AccountStore.account?.supports(chain: sellingToken.chain) == true,
                        passcode: passcode
                    )
                    onTaskDone(nil, nil)
                } catch {
                    log.error("SwapCexSupport.swapCexCreateTransaction: \(error, .public)")
                    onTaskDone(nil, error)
                }
            }

        }
    }
    
    // MARK: - Cross-Chain from ton swap
    private func crossChainFromTonSwap(sellingToken: ApiToken, buyingToken: ApiToken, passcode: String, onTaskDone: @escaping (ApiActivity?, (any Error)?) -> Void) {
        guard let swapEstimate = self.cexEstimate else {
            return
        }
        if let account = AccountStore.account {
            let fromAddress = account.addressByChain[sellingToken.chain]
            let toAddress = account.addressByChain[buyingToken.chain]
            let cexFromTonSwapParams = ApiSwapCexCreateTransactionParams(
                from: sellingToken.swapIdentifier,
                fromAmount: swapEstimate.fromAmount,
                fromAddress: fromAddress ?? "",
                to: buyingToken.swapIdentifier,
                toAddress: toAddress ?? "",
                swapFee: swapEstimate.swapFee,
                networkFee: 0
            )
            Task {
                do {
                    _ = try await SwapCexSupport.swapCexCreateTransaction(
                        sellingToken: sellingToken,
                        params: cexFromTonSwapParams,
                        shouldTransfer: true,
                        passcode: passcode
                    )
                    onTaskDone(nil, nil)
                } catch {
                    log.error("SwapCexSupport.swapCexCreateTransaction: \(error, .public)")
                    onTaskDone(nil, error)
                }
            }
        }
    }

}
