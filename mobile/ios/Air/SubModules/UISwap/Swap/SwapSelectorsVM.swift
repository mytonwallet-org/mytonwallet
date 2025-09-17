//
//  SwapTokenSelectorsView.swift
//  UISwap
//
//  Created by Sina on 5/10/24.
//

import Combine
import SwiftUI
import UIKit
import UIComponents
import WalletCore
import WalletContext

enum SwapSide {
    case selling
    case buying
}


@MainActor protocol SwapSelectorsDelegate: UIViewController {
    func swapDataChanged(swapSide: SwapSide, selling: TokenAmount, buying: TokenAmount)
    func maxAmountPressed(maxAmount: BigInt?)
}


@MainActor
final class SwapSelectorsVM: ObservableObject {
    
    @Published var sellingAmount: BigInt?
    var isUsingMax: Bool = false
    @Published var sellingToken: ApiToken
    
    @Published var buyingAmount: BigInt?
    @Published var buyingToken: ApiToken
    
    var sellingTokenAmount: TokenAmount? {
        if let sellingAmount {
            return TokenAmount(sellingAmount, sellingToken)
        }
        return nil
    }
    var buyingTokenAmount: TokenAmount? {
        if let buyingAmount {
            return TokenAmount(buyingAmount, buyingToken)
        }
        return nil
    }

    @Published var maxAmount: BigInt?
    
    @Published var sellingFocused: Bool = false
    @Published var buyingFocused: Bool = false
    
    var onUseAll: () -> () = { }
    var onReverse: () -> () = { }
    var onSellingTokenPicker: () -> () = { }
    var onBuyingTokenPicker: () -> () = { }
    
    weak var delegate: SwapSelectorsDelegate? = nil

    private var lastEdited: SwapSide = .selling
    private var currentSelector: SwapSide? = nil
    struct LastEffectiveExchangeRate {
        var sellingToken: ApiToken
        var buyingToken: ApiToken
        var exchangeRate: Double
    }
    private var lastEffectiveExchangeRate: LastEffectiveExchangeRate? = nil
    private var suspendUpdates = false
    private var observables: Set<AnyCancellable> = []
    
    private var localExchangeRate: Double? {
        let selling = sellingToken.price ?? 0
        let buying = buyingToken.price ?? 0
        guard selling > 0, buying > 0 else { return nil }
        return selling / buying
    }

    init(sellingAmount: BigInt?, sellingToken: ApiToken, buyingAmount: BigInt?, buyingToken: ApiToken, maxAmount: BigInt?) {
        self.sellingAmount = sellingAmount
        self.sellingToken = sellingToken
        self.buyingAmount = buyingAmount
        self.buyingToken = buyingToken
        self.maxAmount = maxAmount
        
        setupObservers()
        setupCallbacks()
    }
    
    private func setupObservers() {
        
        Publishers.CombineLatest3($sellingFocused, $sellingAmount, $sellingToken)
            .filter { (isFocused, _, _) in isFocused } // only receive updates when user is editing
            .removeDuplicates(by: { $0 == $1 })
            .sink { [weak self] (isFocused, amount, token) in
                guard let self, suspendUpdates == false else { return }
                lastEdited = .selling
                updateLocal(amount: amount, token: token, side: .selling)
            }
            .store(in: &observables)
        
        Publishers.CombineLatest3($buyingFocused, $buyingAmount, $buyingToken)
            .filter { (isFocused, _, _) in isFocused }
            .removeDuplicates(by: { $0 == $1 })
            .sink { [weak self] (isFocused, amount, token) in
                guard let self, suspendUpdates == false else { return }
                lastEdited = .buying
                updateLocal(amount: amount, token: token, side: .buying)
            }
            .store(in: &observables)
    }
    
    private func setupCallbacks() {
        onUseAll = { [weak self] in
            guard let self else { return }
            self.delegate?.maxAmountPressed(maxAmount: maxAmount)
            sellingAmount = maxAmount
            isUsingMax = true
            topViewController()?.view.endEditing(true)
        }
        
        onReverse = { [weak self] in
            guard let self else { return }
            suspendUpdates = true
            defer { suspendUpdates = false }
            let lastEdited = self.lastEdited
            let tmp = (sellingAmount ?? 0, buyingAmount ?? 0, sellingToken, buyingToken)
            (buyingAmount, sellingAmount, buyingToken, sellingToken) = tmp
            self.lastEdited = lastEdited
            if AccountStore.account?.supports(chain: sellingToken.chain) == true {
                self.updateMaxAmount(sellingToken, amount: BalanceStore.currentAccountBalances[sellingToken.slug] ?? 0)
            } else {
                self.updateMaxAmount(nil, amount: nil)
            }
            updateLocal(amount: sellingAmount ?? 0, token: sellingToken, side: .selling)
        }
        
        onSellingTokenPicker = { [weak self] in
            guard let self else { return }
            self.currentSelector = .selling
            let swapTokenSelectionVC = TokenSelectionVC(
                forceAvailable: sellingToken.slug,
                otherSymbolOrMinterAddress: nil,
                title: lang("You sell"),
                delegate: self,
                isModal: true,
                onlyTonChain: false
            )
            let nc = WNavigationController(rootViewController: swapTokenSelectionVC)
            topViewController()?.present(nc, animated: true)
        }

        onBuyingTokenPicker = { [weak self] in
            guard let self else { return }
            self.currentSelector = .buying
            let swapTokenSelectionVC = TokenSelectionVC(
                forceAvailable: buyingToken.slug,
                otherSymbolOrMinterAddress: nil,
                title: lang("You buy"),
                delegate: self,
                isModal: true,
                onlyTonChain: false
            )
            let nc = WNavigationController(rootViewController: swapTokenSelectionVC)
            topViewController()?.present(nc, animated: true)
        }
    }
    
    private func updateLocal(amount: BigInt?, token: ApiToken, side: SwapSide) {
        suspendUpdates = true
        defer { suspendUpdates = false }
        switch side {
        case .selling:
            if let amount {
                if amount != maxAmount {
                    self.isUsingMax = false
                }
                let selling = DecimalAmount(amount, token)
                
                var exchangeRate: Double?
                if let lastEffectiveExchangeRate,
                    lastEffectiveExchangeRate.sellingToken == token,
                    lastEffectiveExchangeRate.buyingToken == buyingToken {
                    
                    exchangeRate = lastEffectiveExchangeRate.exchangeRate
                } else if let localExchangeRate{
                    exchangeRate = localExchangeRate
                }
                if let exchangeRate {
                    let buying = selling.convertTo(buyingToken, exchangeRate: exchangeRate).roundedForSwap
                    self.buyingAmount = buying.amount
                }
            }
            updateRemote(amount: amount, token: token, side: .selling)
        case .buying:
            self.isUsingMax = false
            if let amount {
                let buying = DecimalAmount(amount, token)
                
                var exchangeRate: Double?
                if let lastEffectiveExchangeRate,
                    lastEffectiveExchangeRate.buyingToken == buyingToken,
                    lastEffectiveExchangeRate.sellingToken == token {
                    
                    exchangeRate = 1 / lastEffectiveExchangeRate.exchangeRate
                } else if let localExchangeRate {
                    exchangeRate = 1 / localExchangeRate
                }
                if let exchangeRate {
                    let selling = buying.convertTo(sellingToken, exchangeRate: exchangeRate).roundedForSwap
                    self.sellingAmount = selling.amount
                }
            }
            updateRemote(amount: amount, token: token, side: .buying)
        }
    }
    
    private func updateRemote(amount: BigInt?, token: ApiToken, side: SwapSide) {
        switch side {
        case .selling:
            delegate?.swapDataChanged(
                swapSide: lastEdited,
                selling: TokenAmount(amount ?? 0, token),
                buying: TokenAmount(buyingAmount ?? 0, buyingToken)
            )
        case .buying:
            delegate?.swapDataChanged(
                swapSide: lastEdited,
                selling: TokenAmount(sellingAmount ?? 0, sellingToken),
                buying: TokenAmount(amount ?? 0, token)
            )
        }
    }
    
    func updateMaxAmount(_ token: ApiToken?, amount: BigInt?) {
        let token = token ?? sellingToken
        let balance = amount ?? BalanceStore.currentAccountBalances[token.slug]
        self.maxAmount = balance.flatMap { max(0, $0) }
        if (isUsingMax) {
            if let amount, let sellingAmount, sellingAmount != amount {
                self.sellingAmount = amount
                updateLocal(amount: amount, token: sellingToken, side: .selling)
            }
        }
    }
    
    struct Estimate {
        var fromAmount: Double
        var toAmount: Double
        var maxAmount: BigInt?
    }
    
    func updateWithEstimate(_ swapEstimate: Estimate) {
        suspendUpdates = true
        defer { suspendUpdates = false }
        if let t = TokenStore.tokens[sellingToken.slug], t != sellingToken {
            self.sellingToken = t
        }
        if let t = TokenStore.tokens[buyingToken.slug], t != buyingToken {
            self.buyingToken = t
        }
        if lastEdited != .selling && !sellingFocused && swapEstimate.fromAmount > 0 { // if it's zero, keep local estimate
            sellingAmount = DecimalAmount.fromDouble(swapEstimate.fromAmount, sellingToken).roundedForSwap.amount
        }
        if !buyingFocused && swapEstimate.toAmount > 0 {
            buyingAmount = DecimalAmount.fromDouble(swapEstimate.toAmount, buyingToken).roundedForSwap.amount
        }
        if swapEstimate.toAmount > 0, swapEstimate.fromAmount > 0 {
            let effectiveExchangeRate = swapEstimate.toAmount / swapEstimate.fromAmount
            lastEffectiveExchangeRate = .init(sellingToken: sellingToken, buyingToken: buyingToken, exchangeRate: effectiveExchangeRate)
        }
        if let maxAmount = swapEstimate.maxAmount {
            updateMaxAmount(nil, amount: maxAmount)
        }
    }
}


extension SwapSelectorsVM: TokenSelectionVCDelegate {
    func didSelect(token: MTokenBalance) {
        topViewController()?.dismiss(animated: true)
        if let newToken = TokenStore.tokens[token.tokenSlug] {
            _didSelect(newToken)
        }
    }
    
    func didSelect(token newToken: ApiToken) {
        topViewController()?.dismiss(animated: true)
        _didSelect(newToken)
    }
    
    func _didSelect(_ newToken: ApiToken) {
        if currentSelector == .selling {
            if newToken == buyingToken {
                onReverse()
                return
            }
            let newAmount: BigInt? = if let sellingAmount, sellingAmount > 0 {
                TokenAmount(sellingAmount, sellingToken).switchKeepingDecimalValue(newType: newToken).amount
            } else {
                nil
            }
            sellingAmount = newAmount
            sellingToken = newToken
            lastEdited = .selling
            maxAmount = BalanceStore.currentAccountBalances[newToken.slug]
            updateLocal(amount: newAmount, token: sellingToken, side: .selling)
        } else {
            if newToken.slug == sellingToken.slug {
                onReverse()
                return
            }
            buyingToken = newToken
            if buyingFocused { buyingFocused = false }
            lastEdited = .selling
            updateLocal(amount: sellingAmount, token: sellingToken, side: .selling)
        }
    }
}
