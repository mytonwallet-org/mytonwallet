import WalletCore
import WalletContext
import Perception

enum SwapSide: Sendable {
    case selling
    case buying

    var swapMode: ApiSwapMode {
        switch self {
        case .selling:
            .exactIn
        case .buying:
            .exactOut
        }
    }
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
        source: SwapInputChangeSource
    )
    func swapCommandRequested(_ command: SwapCommand)
}

@Perceptible
@MainActor final class SwapInputModel {
    
    var sellingAmount: BigInt?
    private var sellingTokenProvider: TokenProvider?
    var sellingToken: ApiToken? {
        get { sellingTokenProvider?.token }
        set {
            if let newValue {
                if sellingTokenProvider == nil {
                    sellingTokenProvider = TokenProvider(tokenSlug: newValue.slug)
                }
                sellingTokenProvider?.token = newValue
            } else {
                sellingTokenProvider = nil
            }
        }
    }
    
    @PerceptionIgnored
    var isUsingMax: Bool = false
    
    var buyingAmount: BigInt?
    private var buyingTokenProvider: TokenProvider?
    var buyingToken: ApiToken? {
        get { buyingTokenProvider?.token }
        set {
            if let newValue {
                if buyingTokenProvider == nil {
                    buyingTokenProvider = TokenProvider(tokenSlug: newValue.slug)
                }
                buyingTokenProvider?.token = newValue
            } else {
                buyingTokenProvider = nil
            }
        }
    }
    
    var sellingTokenAmount: TokenAmount? {
        sellingToken.map { TokenAmount(sellingAmount ?? 0, $0) }
    }
    var buyingTokenAmount: TokenAmount? {
        buyingToken.map { TokenAmount(buyingAmount ?? 0, $0) }
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
    private var backendMaxAmount: BigInt?
    @PerceptionIgnored
    @AccountContext var account: MAccount

    init(sellingTokenSlug: String?, buyingTokenSlug: String?, tokenBalance: BigInt?, accountContext: AccountContext) {
        self.sellingTokenProvider = sellingTokenSlug.map { TokenProvider(tokenSlug: $0) }
        self.buyingTokenProvider = buyingTokenSlug.map { TokenProvider(tokenSlug: $0) }
        self.tokenBalance = tokenBalance
        self._account = accountContext
    }

    func userTappedUseAll() {
        isUsingMax = true
        let amount = maxAmount ?? tokenBalance
        sellingFocused = false
        buyingFocused = false
        sellingAmount = amount
        updateLocal(amount: amount, side: .selling)
        delegate?.swapCommandRequested(.dismissKeyboard)
    }

    func userTappedReverse() {
        isUsingMax = false
        let tmp = (sellingAmount ?? 0, buyingAmount ?? 0, sellingToken, buyingToken)
        (buyingAmount, sellingAmount, buyingToken, sellingToken) = tmp
        clearBackendMaxAmount()
        refreshTokenBalanceFromAccount()
        let side: SwapSide = sellingToken == nil && buyingToken != nil ? .buying : .selling
        updateLocal(amount: side == .selling ? sellingAmount : buyingAmount, side: side)
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
            updateLocal(amount: amount, side: .selling)
        case .buying:
            buyingAmount = amount
            updateLocal(amount: amount, side: .buying)
        }
    }
    
    private func updateLocal(amount: BigInt?, side: SwapSide) {
        inputSource = side
        switch side {
        case .selling:
            if amount != maxAmount {
                self.isUsingMax = false
            }
            updateRemote(side: .selling)
        case .buying:
            self.isUsingMax = false
            updateRemote(side: .buying)
        }
    }
    
    private func updateRemote(side: SwapSide, source: SwapInputChangeSource = .user) {
        delegate?.swapDataChanged(swapSide: side, source: source)
    }

    func refreshTokenBalanceFromAccount() {
        if let sellingToken, account.supports(chain: sellingToken.chain) {
            updateTokenBalance($account.balances[sellingToken.slug] ?? 0)
        } else {
            updateTokenBalance(nil)
        }
    }

    func updateTokenBalance(_ balance: BigInt?) {
        tokenBalance = balance.flatMap { max(0, $0) }
        recalculateMaxAmount()
    }

    func updateMaxAmountContext(swapType: SwapType, fullNetworkFee: MFee.FeeTerms?, notifyAmountChange: Bool = true) {
        self.swapType = swapType
        self.fullNetworkFee = fullNetworkFee
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
        guard let sellingToken else {
            maxAmount = nil
            return
        }
        maxAmount = getMaxSwapAmount(.init(
            swapType: swapType,
            tokenBalance: tokenBalance,
            tokenIn: sellingToken,
            fullNetworkFee: fullNetworkFee,
            maxAmountFromBackend: backendMaxAmount
        ))
        if isUsingMax, let targetAmount = maxAmount ?? tokenBalance, sellingAmount != targetAmount {
            sellingAmount = targetAmount
            if notifyAmountChange {
                updateRemote(
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
        guard let sellingToken, let buyingToken else { return }
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
            let wasEmpty = sellingToken == nil
            if newToken == buyingToken {
                userTappedReverse()
                return
            }
            isUsingMax = false
            let newAmount: BigInt? = if let sellingTokenAmount, sellingTokenAmount.amount > 0 {
                sellingTokenAmount.switchKeepingDecimalValue(newType: newToken).amount
            } else {
                nil
            }
            sellingAmount = newAmount
            sellingToken = newToken
            clearBackendMaxAmount()
            updateTokenBalance($account.balances[newToken.slug])
            if wasEmpty, inputSource == .buying {
                updateLocal(amount: buyingAmount, side: .buying)
            } else {
                updateLocal(amount: newAmount, side: .selling)
            }
        case .buying:
            if newToken.slug == sellingToken?.slug {
                userTappedReverse()
                return
            }
            let newAmount: BigInt? = if let buyingTokenAmount, buyingTokenAmount.amount > 0 {
                buyingTokenAmount.switchKeepingDecimalValue(newType: newToken).amount
            } else {
                nil
            }
            buyingToken = newToken
            buyingAmount = newAmount
            if buyingFocused { buyingFocused = false }
            clearBackendMaxAmount()
            if sellingToken == nil {
                updateLocal(amount: newAmount, side: .buying)
            } else {
                updateLocal(amount: sellingAmount, side: .selling)
            }
        }
    }
}
