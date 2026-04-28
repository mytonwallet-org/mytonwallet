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

enum SwapInputChangeSource {
    case user
    case maxAmountRecalculation
}

@MainActor protocol SwapInputModelDelegate: AnyObject {
    func swapDataChanged(
        swapSide: SwapSide,
        selling: TokenAmount,
        buying: TokenAmount,
        source: SwapInputChangeSource
    )
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

    var tokenBalance: BigInt?
    var maxAmount: BigInt?
    var isEstimating = false
    var inputSource: SwapSide = .selling
    var staleAmountSide: SwapSide? {
        guard isEstimating else { return nil }
        return inputSource == .selling ? .buying : .selling
    }
    
    var sellingFocused: Bool = false
    var buyingFocused: Bool = false
    var buyingAmountInputDisabled: Bool = false
    
    @PerceptionIgnored
    var onUseAll: () -> () = { }
    @PerceptionIgnored
    var onReverse: () -> () = { }
    @PerceptionIgnored
    var onSellingTokenPicker: () -> () = { }
    @PerceptionIgnored
    var onBuyingTokenPicker: () -> () = { }
    @PerceptionIgnored
    var onBuyingAmountDisabledTap: () -> () = { }
    
    @PerceptionIgnored
    weak var delegate: SwapInputModelDelegate? = nil

    @PerceptionIgnored
    private var currentSelector: SwapSide? = nil
    @PerceptionIgnored
    private var suspendUpdates = false
    @PerceptionIgnored
    private var observeTokens: [ObserveToken] = []
    @PerceptionIgnored
    private var swapType: SwapType = .onChain
    @PerceptionIgnored
    private var fullNetworkFee: MFee.FeeTerms?
    @PerceptionIgnored
    private var ourFeePercent: Double?
    @PerceptionIgnored
    private var backendMaxAmount: BigInt?
    @PerceptionIgnored
    @AccountContext var account: MAccount

    init(sellingTokenSlug: String, buyingTokenSlug: String, tokenBalance: BigInt?, accountContext: AccountContext) {
        self._sellingToken = TokenProvider(tokenSlug: sellingTokenSlug)
        self._buyingToken = TokenProvider(tokenSlug: buyingTokenSlug)
        self.tokenBalance = tokenBalance
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
                self.updateLocal(amount: sellingAmount, token: sellingToken, side: .selling)
            }
        }
        
        observeTokens += observe { [weak self] in
            guard let self, suspendUpdates == false, buyingFocused else { return }
            let buyingAmount = self.buyingAmount
            let buyingToken = self.buyingToken
            Task {
                self.updateLocal(amount: buyingAmount, token: buyingToken, side: .buying)
            }
        }

        observeTokens += observe { [weak self] in
            guard let self else { return }
            let sellingToken = self.sellingToken
            let balance = $account.balances[sellingToken.slug]
            self.updateTokenBalance(balance)
        }
    }
    
    private func setupCallbacks() {
        onUseAll = { [weak self] in
            guard let self else { return }
            isUsingMax = true
            let amount = maxAmount ?? tokenBalance
            sellingFocused = false
            buyingFocused = false
            sellingAmount = amount
            updateLocal(amount: amount, token: sellingToken, side: .selling)
            topViewController()?.view.endEditing(true)
        }
        
        onReverse = { [weak self] in
            guard let self else { return }
            suspendUpdates = true
            defer { suspendUpdates = false }
            isUsingMax = false
            let tmp = (sellingAmount ?? 0, buyingAmount ?? 0, sellingToken, buyingToken)
            (buyingAmount, sellingAmount, buyingToken, sellingToken) = tmp
            clearBackendMaxAmount()
            if account.supports(chain: sellingToken.chain) {
                self.updateTokenBalance($account.balances[sellingToken.slug] ?? 0)
            } else {
                self.updateTokenBalance(nil)
            }
            updateLocal(amount: sellingAmount ?? 0, token: sellingToken, side: .selling)
        }
        
        onSellingTokenPicker = { [weak self] in
            guard let self else { return }
            self.currentSelector = .selling
            let swapTokenSelectionVC = TokenSelectionVC(
                forceAvailable: sellingToken.slug,
                otherSymbolOrMinterAddress: nil,
                myAssetsDisplayMode: .swap,
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
                extraWalletTokenSlugs: ApiChain.allCases
                    .filter(\.isOnchainSwapSupported)
                    .map(\.nativeToken.slug),
                otherSymbolOrMinterAddress: nil,
                myAssetsDisplayMode: .swap,
                title: lang("You buy"),
                delegate: self,
                isModal: true,
                onlySupportedChains: false
            )
            let nc = WNavigationController(rootViewController: swapTokenSelectionVC)
            topViewController()?.present(nc, animated: true)
        }

        onBuyingAmountDisabledTap = { [weak self] in
            guard let self else { return }
            Haptics.play(.lightTap)
            self.buyingFocused = false
            AppActions.showToast(message: lang("$swap_reverse_prohibited"))
        }
    }
    
    private func updateLocal(amount: BigInt?, token: ApiToken, side: SwapSide) {
        inputSource = side
        switch side {
        case .selling:
            if amount != maxAmount {
                self.isUsingMax = false
            }
            updateRemote(amount: amount, token: token, side: .selling)
        case .buying:
            self.isUsingMax = false
            updateRemote(amount: amount, token: token, side: .buying)
        }
    }
    
    private func updateRemote(
        amount: BigInt?,
        token: ApiToken,
        side: SwapSide,
        source: SwapInputChangeSource = .user
    ) {
        switch side {
        case .selling:
            delegate?.swapDataChanged(
                swapSide: .selling,
                selling: TokenAmount(amount ?? 0, token),
                buying: buyingTokenAmount,
                source: source
            )
        case .buying:
            delegate?.swapDataChanged(
                swapSide: .buying,
                selling: sellingTokenAmount,
                buying: TokenAmount(amount ?? 0, token),
                source: source
            )
        }
    }
    
    func updateTokenBalance(_ balance: BigInt?) {
        tokenBalance = balance.flatMap { max(0, $0) }
        recalculateMaxAmount()
    }

    func updateMaxAmountContext(swapType: SwapType, fullNetworkFee: MFee.FeeTerms?, ourFeePercent: Double?) {
        self.swapType = swapType
        self.fullNetworkFee = fullNetworkFee
        self.ourFeePercent = ourFeePercent
        recalculateMaxAmount()
    }

    func setBackendMaxAmount(_ amount: BigInt?) {
        backendMaxAmount = amount
        recalculateMaxAmount()
    }

    func clearBackendMaxAmount() {
        backendMaxAmount = nil
        recalculateMaxAmount()
    }

    private func recalculateMaxAmount() {
        maxAmount = getMaxSwapAmount(.init(
            swapType: swapType,
            tokenBalance: tokenBalance,
            tokenIn: sellingToken,
            fullNetworkFee: fullNetworkFee,
            ourFeePercent: ourFeePercent,
            maxAmountFromBackend: backendMaxAmount
        ))
        if isUsingMax, let targetAmount = maxAmount ?? tokenBalance, sellingAmount != targetAmount {
            suspendUpdates = true
            sellingAmount = targetAmount
            suspendUpdates = false
            updateRemote(
                amount: targetAmount,
                token: sellingToken,
                side: .selling,
                source: .maxAmountRecalculation
            )
        }
    }

    func updateBuyingAmountInputDisabled(_ isDisabled: Bool) {
        buyingAmountInputDisabled = isDisabled
        if isDisabled {
            buyingFocused = false
        }
    }
    
    struct Estimate {
        var changedFrom: SwapSide
        var fromAmount: Double
        var toAmount: Double
    }
    
    func startEstimating(changedFrom: SwapSide) {
        inputSource = changedFrom
        isEstimating = true
    }

    func finishEstimating() {
        isEstimating = false
    }

    func updateWithEstimate(_ swapEstimate: Estimate) {
        suspendUpdates = true
        defer { suspendUpdates = false }

        switch swapEstimate.changedFrom {
        case .selling:
            if !buyingFocused {
                buyingAmount = DecimalAmount.fromDouble(swapEstimate.toAmount, buyingToken).roundedForSwap.amount
            }
            if isUsingMax {
                sellingAmount = DecimalAmount.fromDouble(swapEstimate.fromAmount, sellingToken).roundedForSwap.amount
            }
        case .buying:
            if !sellingFocused {
                sellingAmount = DecimalAmount.fromDouble(swapEstimate.fromAmount, sellingToken).roundedForSwap.amount
            }
        }
    }

    func clearEstimatedAmount(changedFrom: SwapSide) {
        suspendUpdates = true
        defer { suspendUpdates = false }

        switch changedFrom {
        case .selling:
            if !buyingFocused {
                buyingAmount = nil
            }
        case .buying:
            if !sellingFocused {
                sellingAmount = nil
            }
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
            isUsingMax = false
            let newAmount: BigInt? = if sellingTokenAmount.amount > 0 {
                sellingTokenAmount.switchKeepingDecimalValue(newType: newToken).amount
            } else {
                nil
            }
            sellingAmount = newAmount
            sellingToken = newToken
            clearBackendMaxAmount()
            updateTokenBalance($account.balances[newToken.slug])
            updateLocal(amount: newAmount, token: sellingToken, side: .selling)
        } else {
            if newToken.slug == sellingToken.slug {
                onReverse()
                return
            }
            buyingToken = newToken
            if buyingFocused { buyingFocused = false }
            clearBackendMaxAmount()
            updateLocal(amount: sellingAmount, token: sellingToken, side: .selling)
        }
    }
}
