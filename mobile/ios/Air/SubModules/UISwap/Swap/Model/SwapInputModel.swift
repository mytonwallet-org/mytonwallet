import WalletCore
import WalletContext
import Perception

enum SwapSide: Sendable {
    case selling
    case buying
}

enum SwapInputChangeSource: Sendable {
    case user
    case maxAmountRecalculation
}

enum SwapCommand {
    case dismissKeyboard
    case showTokenSelector(SwapSide)
    case showBuyingAmountDisabledToast
}

@MainActor protocol SwapInputModelDelegate: AnyObject {
    func swapDataChanged(
        swapSide: SwapSide,
        selling: TokenAmount,
        buying: TokenAmount,
        source: SwapInputChangeSource
    )
    func swapCommandRequested(_ command: SwapCommand)
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
    weak var delegate: SwapInputModelDelegate? = nil

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
    }

    func userTappedUseAll() {
        isUsingMax = true
        let amount = maxAmount ?? tokenBalance
        sellingFocused = false
        buyingFocused = false
        sellingAmount = amount
        updateLocal(amount: amount, token: sellingToken, side: .selling)
        delegate?.swapCommandRequested(.dismissKeyboard)
    }

    func userTappedReverse() {
        isUsingMax = false
        let tmp = (sellingAmount ?? 0, buyingAmount ?? 0, sellingToken, buyingToken)
        (buyingAmount, sellingAmount, buyingToken, sellingToken) = tmp
        clearBackendMaxAmount()
        refreshTokenBalanceFromAccount()
        updateLocal(amount: sellingAmount ?? 0, token: sellingToken, side: .selling)
    }

    func userTappedTokenPicker(side: SwapSide) {
        delegate?.swapCommandRequested(.showTokenSelector(side))
    }

    func userTappedBuyingAmountDisabled() {
        buyingFocused = false
        delegate?.swapCommandRequested(.showBuyingAmountDisabledToast)
    }

    func userEditedAmount(_ amount: BigInt?, side: SwapSide) {
        switch side {
        case .selling:
            sellingAmount = amount
            updateLocal(amount: amount, token: sellingToken, side: .selling)
        case .buying:
            buyingAmount = amount
            updateLocal(amount: amount, token: buyingToken, side: .buying)
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
    
    func refreshTokenBalanceFromAccount() {
        if account.supports(chain: sellingToken.chain) {
            updateTokenBalance($account.balances[sellingToken.slug] ?? 0)
        } else {
            updateTokenBalance(nil)
        }
    }

    func updateTokenBalance(_ balance: BigInt?) {
        tokenBalance = balance.flatMap { max(0, $0) }
        recalculateMaxAmount()
    }

    func updateMaxAmountContext(swapType: SwapType, fullNetworkFee: MFee.FeeTerms?, ourFeePercent: Double?, notifyAmountChange: Bool = true) {
        self.swapType = swapType
        self.fullNetworkFee = fullNetworkFee
        self.ourFeePercent = ourFeePercent
        recalculateMaxAmount(notifyAmountChange: notifyAmountChange)
    }

    func setBackendMaxAmount(_ amount: BigInt?) {
        backendMaxAmount = amount
        recalculateMaxAmount(notifyAmountChange: false)
    }

    func clearBackendMaxAmount() {
        backendMaxAmount = nil
        recalculateMaxAmount(notifyAmountChange: false)
    }

    private func recalculateMaxAmount(notifyAmountChange: Bool = true) {
        maxAmount = getMaxSwapAmount(.init(
            swapType: swapType,
            tokenBalance: tokenBalance,
            tokenIn: sellingToken,
            fullNetworkFee: fullNetworkFee,
            ourFeePercent: ourFeePercent,
            maxAmountFromBackend: backendMaxAmount
        ))
        if isUsingMax, let targetAmount = maxAmount ?? tokenBalance, sellingAmount != targetAmount {
            sellingAmount = targetAmount
            if notifyAmountChange {
                updateRemote(
                    amount: targetAmount,
                    token: sellingToken,
                    side: .selling,
                    source: .maxAmountRecalculation
                )
            }
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

    func userSelectedToken(_ newToken: ApiToken, side: SwapSide) {
        switch side {
        case .selling:
            if newToken == buyingToken {
                userTappedReverse()
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
        case .buying:
            if newToken.slug == sellingToken.slug {
                userTappedReverse()
                return
            }
            let newAmount: BigInt? = if buyingTokenAmount.amount > 0 {
                buyingTokenAmount.switchKeepingDecimalValue(newType: newToken).amount
            } else {
                nil
            }
            buyingToken = newToken
            buyingAmount = newAmount
            if buyingFocused { buyingFocused = false }
            clearBackendMaxAmount()
            updateLocal(amount: sellingAmount, token: sellingToken, side: .selling)
        }
    }
}
