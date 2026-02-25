import SwiftUI
import UIKit
import UIComponents
import WalletCore
import WalletContext
import Perception
import SwiftNavigation

enum SwapSide {
    case selling
    case buying
}

@MainActor protocol SwapInputModelDelegate: AnyObject {
    func swapDataChanged(swapSide: SwapSide, selling: TokenAmount, buying: TokenAmount)
    func maxAmountPressed(maxAmount: BigInt?)
}

@Perceptible
@MainActor final class SwapInputModel {
    
    var sellingAmount: BigInt?
    @PerceptionIgnored
    @TokenProvider var sellingToken: ApiToken
    
    @PerceptionIgnored
    var isUsingMax: Bool = false
    
    var buyingAmount: BigInt?
    @PerceptionIgnored
    @TokenProvider var buyingToken: ApiToken
    
    var sellingTokenAmount: TokenAmount {
        TokenAmount(sellingAmount ?? 0, sellingToken)
    }
    var buyingTokenAmount: TokenAmount {
        TokenAmount(buyingAmount ?? 0, buyingToken)
    }

    var maxAmount: BigInt?
    
    var sellingFocused: Bool = false
    var buyingFocused: Bool = false
    
    @PerceptionIgnored
    var onUseAll: () -> () = { }
    @PerceptionIgnored
    var onReverse: () -> () = { }
    @PerceptionIgnored
    var onSellingTokenPicker: () -> () = { }
    @PerceptionIgnored
    var onBuyingTokenPicker: () -> () = { }
    
    @PerceptionIgnored
    weak var delegate: SwapInputModelDelegate? = nil

    @PerceptionIgnored
    private var lastEdited: SwapSide = .selling
    @PerceptionIgnored
    private var currentSelector: SwapSide? = nil
    struct LastEffectiveExchangeRate {
        var sellingToken: ApiToken
        var buyingToken: ApiToken
        var exchangeRate: Double
    }
    @PerceptionIgnored
    private var lastEffectiveExchangeRate: LastEffectiveExchangeRate? = nil
    @PerceptionIgnored
    private var suspendUpdates = false
    @PerceptionIgnored
    private var observeTokens: [ObserveToken] = []
    @PerceptionIgnored
    @AccountContext var account: MAccount
    
    private var localExchangeRate: Double? {
        let selling = sellingToken.price ?? 0
        let buying = buyingToken.price ?? 0
        guard selling > 0, buying > 0 else { return nil }
        return selling / buying
    }

    init(sellingTokenSlug: String, buyingTokenSlug: String, maxAmount: BigInt?, accountContext: AccountContext) {
        self._sellingToken = TokenProvider(tokenSlug: sellingTokenSlug)
        self._buyingToken = TokenProvider(tokenSlug: buyingTokenSlug)
        self.maxAmount = maxAmount
        self._account = accountContext
        
        setupObservers()
        setupCallbacks()
    }
    
    private func setupObservers() {
        observeTokens += observe { [weak self] in
            guard let self, suspendUpdates == false, sellingFocused else { return }
            let sellingAmount = self.sellingAmount
            let sellingToken = self.sellingToken
            Task {
                self.lastEdited = .selling
                self.updateLocal(amount: sellingAmount, token: sellingToken, side: .selling)
            }
        }
        
        observeTokens += observe { [weak self] in
            guard let self, suspendUpdates == false, buyingFocused else { return }
            let buyingAmount = self.buyingAmount
            let buyingToken = self.buyingToken
            Task {
                self.lastEdited = .buying
                self.updateLocal(amount: buyingAmount, token: buyingToken, side: .buying)
            }
        }

        observeTokens += observe { [weak self] in
            guard let self else { return }
            let sellingToken = self.sellingToken
            let balance = $account.balances[sellingToken.slug]
            self.updateMaxAmount(sellingToken, amount: balance)
        }
    }
    
    private func setupCallbacks() {
        onUseAll = { [weak self] in
            guard let self else { return }
            isUsingMax = true
            self.delegate?.maxAmountPressed(maxAmount: maxAmount)
            sellingAmount = maxAmount
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
            if account.supports(chain: sellingToken.chain) {
                self.updateMaxAmount(sellingToken, amount: $account.balances[sellingToken.slug] ?? 0)
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
                onlySupportedChains: false
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
                onlySupportedChains: false
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
                buying: buyingTokenAmount,
            )
        case .buying:
            delegate?.swapDataChanged(
                swapSide: lastEdited,
                selling: sellingTokenAmount,
                buying: TokenAmount(amount ?? 0, token),
            )
        }
    }
    
    func updateMaxAmount(_ token: ApiToken?, amount: BigInt?) {
        let token = token ?? sellingToken
        let balance = amount ?? $account.balances[token.slug]
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
        if lastEdited != .selling && !sellingFocused && swapEstimate.fromAmount > 0 { // if it's zero, keep local estimate
            sellingAmount = DecimalAmount.fromDouble(swapEstimate.fromAmount, sellingToken).roundedForSwap.amount
        }
        if lastEdited != .buying && !buyingFocused && swapEstimate.toAmount > 0 {
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


extension SwapInputModel: TokenSelectionVCDelegate {
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
            let newAmount: BigInt? = if sellingTokenAmount.amount > 0 {
                sellingTokenAmount.switchKeepingDecimalValue(newType: newToken).amount
            } else {
                nil
            }
            sellingAmount = newAmount
            sellingToken = newToken
            lastEdited = .selling
            maxAmount = $account.balances[newToken.slug]
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
