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
    @MainActor func receivedEstimateData(swapEstimate: Api.SwapEstimateResponse?, selectedDex: ApiSwapDexLabel?, lateInit: MSwapEstimate.LateInitProperties?)
    @MainActor func receivedCexEstimate(swapEstimate: MSwapEstimate)
}


@MainActor
final class SwapVM: ObservableObject {
    
    @Published private(set) var swapEstimate: Api.SwapEstimateResponse? = nil
    @Published private(set) var lateInit: MSwapEstimate.LateInitProperties? = nil
    @Published private(set) var cexEstimate: MSwapEstimate? = nil
    @Published private(set) var isValidPair = true
    @Published private(set) var swapType = SwapType.inChain
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
        swapType = if buying.token.chain != "ton" {
            .crossChainFromTon
        } else if selling.token.chain != "ton" {
            .crossChainToTon
        } else {
            .inChain
        }
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
            let pairs = try await Api.swapGetPairs(symbolOrMinter: selling.token.swapIdentifier)
            try Task.checkCancellation()
            isValidPair = pairs.contains(where: { p in p.slug == buying.token.slug })
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
        
        if swapType != .inChain {
            let options: Api.SwapCEXEstimateOptions
            if changedFrom == .selling {
                // normal request
                options = Api.SwapCEXEstimateOptions(from: from,
                                                               to: to,
                                                               fromAmount: String(selling.amount.doubleAbsRepresentation(decimals: selling.token.decimals)))
            } else {
                // reversed request!
                options = Api.SwapCEXEstimateOptions(from: to,
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
            let props = MSwapEstimate.calculateLateInitProperties(selling: selling,
                                                                  swapType: swapType,
                                                                  networkFee: swapEstimate?.networkFee.value,
                                                                  dieselFee: swapEstimate?.dieselFee?.value,
                                                                  ourFeePercent: swapEstimate?.ourFeePercent)
            let fromAddress = try (AccountStore.account?.tonAddress).orThrow()
            let shouldTryDiesel = props.isEnoughNative == false
            let toncoinBalance = (BalanceStore.currentAccountBalances["toncoin"]).flatMap { MDouble.forBigInt($0, decimals: 9) }
            let walletVersion = AccountStore.account?.version
            let swapEstimateRequest = Api.SwapEstimateRequest(
                from: from,
                to: to,
                slippage: slippage,
                fromAmount: changedFrom == .selling ? MDouble.forBigInt(selling.amount, decimals: selling.token.decimals) : nil,
                toAmount: changedFrom == .buying ? MDouble.forBigInt(buying.amount, decimals: buying.token.decimals) : nil,
                fromAddress: fromAddress,
                shouldTryDiesel: shouldTryDiesel,
                swapVersion: 2,
                toncoinBalance: toncoinBalance,
                walletVersion: walletVersion,
                isFromAmountMax: nil
            )
            
            // On-chain swap estimate
            do {
                let swapEstimate = try await Api.swapEstimate(accountId: accountId, request: swapEstimateRequest)
                try Task.checkCancellation()
                let lateInit = MSwapEstimate.calculateLateInitProperties(selling: selling,
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
    
    func updateEstimate(_ swapEstimate: Api.SwapEstimateResponse?, lateInit: MSwapEstimate.LateInitProperties?) {
        self.swapEstimate = swapEstimate
        self.lateInit = lateInit
        Task {
            delegate?.receivedEstimateData(swapEstimate: swapEstimate, selectedDex: dex, lateInit: lateInit)
        }
    }
    
    func updateCexEstimate(_ swapEstimate: MSwapEstimate) {
        self.cexEstimate = swapEstimate
        Task {
            delegate?.receivedCexEstimate(swapEstimate: swapEstimate)
        }
    }
    
    // MARK: Check for error
    ///  checks for swap error, returns nil if swap is possible
    func checkDexSwapError(swapEstimate: Api.SwapEstimateResponse, lateInit: MSwapEstimate.LateInitProperties) -> String? {
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
                swapError = WStrings.InsufficientBalance_Text(symbol: sellToken.symbol)
            }
        }
        if swapEstimate.toAmount?.value == 0 && lateInit.isEnoughNative == false {
            swapError = WStrings.InsufficientBalance_Text(symbol: sellToken.symbol.uppercased())
        }
        if lateInit.isEnoughNative == false && (lateInit.isDiesel != true || swapEstimate.dieselStatus.canContinue != true) {
            if lateInit.isDiesel == true, let swapDieselError = swapEstimate.dieselStatus.errorString {
                swapError = swapDieselError
            } else {
                swapError = WStrings.InsufficientBalance_Text(symbol: sellToken.chain.uppercased())
            }
        }
        return swapError
    }
    
    func checkCexSwapError(swapEstimate: MSwapEstimate) -> String? {
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
                swapError = WStrings.InsufficientBalance_Text(symbol: sellToken.symbol)
            }
        }
        if swapEstimate.toAmount == 0 && swapEstimate.isEnoughNative == false {
            swapError = WStrings.InsufficientBalance_Text(symbol: sellToken.symbol.uppercased())
        }
        if swapEstimate.isEnoughNative == false && (swapEstimate.isDiesel != true || swapEstimate.dieselStatus?.canContinue != true) {
            if swapEstimate.isDiesel == true, let swapDieselError = swapEstimate.dieselStatus?.errorString {
                swapError = swapDieselError
            } else {
                swapError = WStrings.InsufficientBalance_Text(symbol: sellToken.chain.uppercased())
            }
        }
        if let fromMin = swapEstimate.fromMin {
            if swapEstimate.fromAmount < fromMin {
                swapError = "\(lang("Minimum")) \(fromMin) \(tokensSelector.sellingToken.symbol)"
            }
        }
        if let fromMax = swapEstimate.fromMax, fromMax > 0 {
            if swapEstimate.fromAmount > fromMax {
                swapError = "\(lang("Maximum")) \(fromMax) \(tokensSelector.sellingToken.symbol)"
            }
        }
        if let toMin = swapEstimate.toMin {
            if swapEstimate.toAmount < toMin {
                swapError = "\(lang("Maximum")) \(toMin) \(tokensSelector.buyingToken.symbol)"
            }
        }
        if let toMax = swapEstimate.toMax, toMax > 0 {
            if swapEstimate.toAmount > toMax {
                swapError = "\(lang("Maximum")) \(toMax) \(tokensSelector.buyingToken.symbol)"
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
    
    func swapNow(sellingToken: ApiToken, buyingToken: ApiToken, passcode: String, onTaskDone: @escaping (ApiActivity?, BridgeCallError?) -> Void) {
        switch swapType {
        case .inChain:
            swapInChain(sellingToken: sellingToken, buyingToken: buyingToken, passcode: passcode, onTaskDone: onTaskDone)
        case .crossChainToTon:
            crossChainToTonSwap(sellingToken: sellingToken, buyingToken: buyingToken, passcode: passcode, onTaskDone: onTaskDone)
        case .crossChainFromTon:
            crossChainFromTonSwap(sellingToken: sellingToken, buyingToken: buyingToken, passcode: passcode, onTaskDone: onTaskDone)
        @unknown default:
            onTaskDone(nil, .unknown())
        }
    }
    
    // MARK: - On-Chain swap
    private func onChainSwap(passcode: String) async throws {
        let swapEstimate = try self.swapEstimate.orThrow()
        let fromAddress = try (AccountStore.account?.tonAddress).orThrow()
        let walletVersion = AccountStore.account?.version
        let shouldTryDiesel = swapEstimate.networkFee.value > 0 &&
            BalanceStore.currentAccountBalances["toncoin"] ?? 0 < BigInt((swapEstimate.networkFee.value + 0.015) * 1e9) && swapEstimate.dieselStatus == .available
        
        let swapBuildRequest = Api.SwapBuildRequest(
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
            networkFee: swapEstimate.realNetworkFee,
            swapFee: swapEstimate.swapFee,
            ourFee: swapEstimate.ourFee,
            dieselFee: swapEstimate.dieselFee
        )
        let accountId = try AccountStore.accountId.orThrow()
        let transferData = try await Api.swapBuildTransfer(accountId: accountId, password: passcode, request: swapBuildRequest)
        let historyItem = Api.makeSwapHistoryItem(swapBuildRequest: swapBuildRequest, swapTransferData: transferData)
        let result = try await Api.swapSubmit(accountId: accountId, password: passcode, transfers: transferData.transfers, historyItem: historyItem, isGasless: shouldTryDiesel)
        print(result)
    }
    
    // MARK: - Cross-Chain to ton swap
    private func crossChainToTonSwap(sellingToken: ApiToken, buyingToken: ApiToken, passcode: String, onTaskDone: @escaping (ApiActivity?, BridgeCallError?) -> Void) {
        guard let swapEstimate = self.cexEstimate else {
            return
        }
        if let account = AccountStore.account {
            let fromAddress = account.addressByChain[sellingToken.chain]
            let toAddress = account.addressByChain[buyingToken.chain]
            let swapCexParams = Api.SwapCexParams(
                from: sellingToken.swapIdentifier,
                fromAmount: String(swapEstimate.fromAmount),
                fromAddress: fromAddress ?? "",
                to: buyingToken.swapIdentifier,
                toAddress: toAddress ?? "",
                swapFee: String(swapEstimate.swapFee),
                networkFee: String(0)
            )
            Api.swapCexCreateTransaction(sellingToken: sellingToken,
                                         params: swapCexParams,
                                         shouldTransfer: AccountStore.account?.supports(chain: sellingToken.chain) == true,
                                         passcode: passcode) { res in
                DispatchQueue.main.async {
                    switch res {
                    case .success(let success):
                        onTaskDone(success, nil)
                    case .failure(let failure):
                        onTaskDone(nil, failure)
                    }
                }
            }
        }
    }
    
    // MARK: - Cross-Chain from ton swap
    private func crossChainFromTonSwap(sellingToken: ApiToken, buyingToken: ApiToken, passcode: String, onTaskDone: @escaping (ApiActivity?, BridgeCallError?) -> Void) {
        guard let swapEstimate = self.cexEstimate else {
            return
        }
        if let account = AccountStore.account {
            let fromAddress = account.addressByChain[sellingToken.chain]
            let toAddress = account.addressByChain[buyingToken.chain]
            let cexFromTonSwapParams = Api.SwapCexParams(
                from: sellingToken.swapIdentifier,
                fromAmount: String(swapEstimate.fromAmount),
                fromAddress: fromAddress ?? "",
                to: buyingToken.swapIdentifier,
                toAddress: toAddress ?? "",
                swapFee: String(swapEstimate.swapFee),
                networkFee: String(0)
            )
            Api.swapCexCreateTransaction(sellingToken: sellingToken,
                                         params: cexFromTonSwapParams,
                                         shouldTransfer: true,
                                         passcode: passcode) { res in
                switch res {
                case .success(_):
                    onTaskDone(nil, nil)
                    break
                case .failure(let failure):
                    onTaskDone(nil, failure)
                }
            }
        }
    }

}
