import Foundation
import WalletCore
import WalletContext
import Dependencies
import Perception

@MainActor protocol SwapModelDelegate: AnyObject {
    func applyButtonConfiguration(_ config: SwapButtonConfiguration)
}

@Perceptible
@MainActor final class SwapModel {

    private(set) var isValidPair = true
    private(set) var swapType = SwapType.onChain

    let onchain: OnchainSwapModel
    let crosschain: CrosschainSwapModel
    let input: SwapInputModel
    let detailsVM: SwapDetailsVM
    let buttonModel = SwapButtonModel()
    private let contextModel = SwapContextModel()

    @PerceptionIgnored
    private weak var delegate: SwapModelDelegate?

    @PerceptionIgnored
    private var estimateLoopTask: Task<Void, Never>?
    @PerceptionIgnored
    private var estimateLoopGeneration = 0
    @PerceptionIgnored
    @AccountContext var account: MAccount

    deinit {
        estimateLoopTask?.cancel()
    }

    init(
        delegate: SwapModelDelegate,
        defaultSellingToken: String?,
        defaultBuyingToken: String?,
        defaultSellingAmount: Double?,
        accountContext: AccountContext
    ) {
        self.delegate = delegate
        self._account = accountContext

        @Dependency(\.tokenStore) var tokenStore
        let sellingToken = tokenStore.getToken(slugOrAddress: defaultSellingToken ?? TONCOIN_SLUG) ?? tokenStore.tokens[TONCOIN_SLUG]!
        let buyingToken = tokenStore.getToken(slugOrAddress: defaultBuyingToken ?? TON_USDT_SLUG) ?? tokenStore.tokens[TON_USDT_SLUG]!
        let tokenBalance = accountContext.balances[sellingToken.slug] ?? 0

        let inputModel = SwapInputModel(
            sellingTokenSlug: sellingToken.slug,
            buyingTokenSlug: buyingToken.slug,
            tokenBalance: tokenBalance,
            accountContext: accountContext
        )
        inputModel.sellingAmount = defaultSellingAmount.flatMap { doubleToBigInt($0, decimals: sellingToken.decimals) }
        let onChain = OnchainSwapModel(inputModel: inputModel, accountContext: accountContext)
        let crosschain = CrosschainSwapModel(inputModel: inputModel, accountContext: accountContext)
        let detailsVM = SwapDetailsVM(onchainModel: onChain, inputModel: inputModel)

        self.input = inputModel
        self.onchain = onChain
        self.crosschain = crosschain
        self.detailsVM = detailsVM
        self.swapType = contextModel.updateSwapType(
            selling: inputModel.sellingToken,
            buying: inputModel.buyingToken,
            accountChains: accountContext.account.supportedChains
        )
        self.input.updateBuyingAmountInputDisabled(
            contextModel.currentBuyAmountInputDisabled(
                selling: inputModel.sellingToken,
                buying: inputModel.buyingToken,
                accountChains: accountContext.account.supportedChains
            )
        )
        self.refreshInputMaxAmountContext()

        self.input.delegate = self
        self.onchain.delegate = self
        self.crosschain.delegate = self
        self.detailsVM.onSlippageChanged = { [weak self] slippage in
            guard let self else { return }
            self.onchain.updateSlippage(slippage)
            self.restartOnchainEstimateIfNeeded()
        }
    }

    func updateSwapType(selling: TokenAmount, buying: TokenAmount) {
        swapType = contextModel.updateSwapType(selling: selling.token, buying: buying.token, accountChains: account.supportedChains)
        input.updateBuyingAmountInputDisabled(
            contextModel.currentBuyAmountInputDisabled(
                selling: selling.token,
                buying: buying.token,
                accountChains: account.supportedChains
            )
        )
        refreshInputMaxAmountContext()
    }

    private func requestEstimate(changedFrom: SwapSide, selling: TokenAmount, buying: TokenAmount) async throws {
        let context = try await contextModel.updateContext(selling: selling.token, buying: buying.token, accountChains: account.supportedChains)
        swapType = context.swapType
        isValidPair = context.isValidPair
        input.updateBuyingAmountInputDisabled(context.isBuyAmountInputDisabled)
        let effectiveChangedFrom: SwapSide = context.isBuyAmountInputDisabled && changedFrom == .buying ? .selling : changedFrom
        if !isValidPair {
            finishEstimating()
            return
        }

        if selling.amount <= 0 && buying.amount <= 0 {
            finishEstimating()
            return
        }

        if swapType == .onChain {
            await onchain.updateEstimate(changedFrom: effectiveChangedFrom, selling: selling, buying: buying)
        } else {
            await crosschain.updateEstimate(changedFrom: effectiveChangedFrom, selling: selling, buying: buying, swapType: swapType)
        }
    }

    func swapNow(sellingToken: ApiToken, buyingToken: ApiToken, passcode: String) async throws -> ApiActivity? {
        switch swapType {
        case .onChain:
            try await onchain.performSwap(passcode: passcode)
            return nil
        case .crosschainInsideWallet, .crosschainToWallet, .crosschainFromWallet:
            return try await crosschain.performSwap(swapType: swapType, sellingToken: sellingToken, buyingToken: buyingToken, passcode: passcode)
        }
    }
}

extension SwapModel: OnchainSwapModelDelegate {
    func receivedOnchainEstimate(changedFrom: SwapSide, swapEstimate: ApiSwapEstimateResponse?, lateInit: OnchainSwapLateInit?) {
        finishEstimating(applyButtonConfiguration: false)
        guard isValidPair else {
            applyCurrentButtonConfiguration()
            return
        }

        if let swapEstimate {
            applyDisplayedOnchainEstimate(changedFrom: changedFrom, swapEstimate: swapEstimate)
        } else {
            input.clearEstimatedAmount(changedFrom: changedFrom)
        }
        refreshInputMaxAmountContext()
        applyCurrentButtonConfiguration()
    }
}

extension SwapModel: CrosschainSwapModelDelegate {
    func receivedCrosschainEstimate(changedFrom: SwapSide, swapEstimate: ApiSwapCexEstimateResponse?) {
        finishEstimating(applyButtonConfiguration: false)
        guard isValidPair else {
            applyCurrentButtonConfiguration()
            return
        }

        if let swapEstimate {
            input.updateWithEstimate(.init(changedFrom: changedFrom, fromAmount: swapEstimate.fromAmount.value, toAmount: swapEstimate.toAmount.value))
        } else {
            input.clearEstimatedAmount(changedFrom: changedFrom)
        }
        refreshInputMaxAmountContext()
        applyCurrentButtonConfiguration()
    }
}

extension SwapModel: SwapInputModelDelegate {
    func swapDataChanged(
        swapSide: SwapSide,
        selling: TokenAmount,
        buying: TokenAmount,
        source: SwapInputChangeSource
    ) {
        updateSwapType(selling: selling, buying: buying)
        if (swapSide == .selling && selling.amount <= 0) || (swapSide == .buying && buying.amount <= 0) {
            estimateLoopTask?.cancel()
            estimateLoopTask = nil
            input.clearEstimatedAmount(changedFrom: swapSide)
            finishEstimating()
            delegate?.applyButtonConfiguration(buttonModel.configurationForEmptyAmounts(
                isValidPair: isValidPair,
                sellingToken: input.sellingToken,
                buyingToken: input.buyingToken
            ))
            return
        }

        switch source {
        case .user:
            restartEstimateLoop(changedFrom: swapSide)
        case .maxAmountRecalculation:
            if estimateLoopTask == nil {
                restartEstimateLoop(changedFrom: swapSide)
            } else {
                applyCurrentButtonConfiguration()
            }
        }
    }
}

private extension SwapModel {
    func restartEstimateLoop(changedFrom: SwapSide) {
        estimateLoopTask?.cancel()
        estimateLoopGeneration += 1
        let generation = estimateLoopGeneration
        beginEstimating(changedFrom: changedFrom)
        estimateLoopTask = Task { [weak self] in
            defer {
                if self?.estimateLoopGeneration == generation {
                    self?.estimateLoopTask = nil
                }
            }
            while !Task.isCancelled {
                guard let self else { return }
                let selling = self.input.sellingTokenAmount
                let buying = self.input.buyingTokenAmount
                if (changedFrom == .selling && selling.amount <= 0) || (changedFrom == .buying && buying.amount <= 0) {
                    self.finishEstimating()
                    return
                }

                do {
                    try await self.requestEstimate(changedFrom: changedFrom, selling: selling, buying: buying)
                    if !self.isValidPair {
                        return
                    }
                } catch {
                    if !Task.isCancelled {
                        self.finishEstimating()
                    }
                }

                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func beginEstimating(changedFrom: SwapSide) {
        input.startEstimating(changedFrom: changedFrom)
        applyCurrentButtonConfiguration()
    }

    func finishEstimating(applyButtonConfiguration: Bool = true) {
        input.finishEstimating()
        if applyButtonConfiguration {
            applyCurrentButtonConfiguration()
        }
    }

    func applyDisplayedOnchainEstimate(changedFrom: SwapSide, swapEstimate: ApiSwapEstimateResponse) {
        input.updateWithEstimate(.init(
            changedFrom: changedFrom,
            fromAmount: swapEstimate.fromAmount?.value ?? 0,
            toAmount: swapEstimate.toAmount?.value ?? 0
        ))
        let backendMaxAmount = input.isUsingMax ? swapEstimate.fromAmount.flatMap {
            DecimalAmount.fromDouble($0.value, input.sellingToken).roundedForSwap.amount
        } : nil
        input.setBackendMaxAmount(backendMaxAmount)
    }

    func restartOnchainEstimateIfNeeded() {
        guard swapType == .onChain else { return }
        let changedFrom = input.inputSource
        let currentAmount: BigInt? = switch changedFrom {
        case .selling:
            input.sellingAmount
        case .buying:
            input.buyingAmount
        }
        guard let currentAmount, currentAmount > 0 else { return }
        restartEstimateLoop(changedFrom: changedFrom)
    }

    func refreshInputMaxAmountContext() {
        let sellingToken = input.sellingToken
        guard let nativeToken = TokenStore.tokens[sellingToken.nativeTokenSlug] else {
            input.updateMaxAmountContext(swapType: swapType, fullNetworkFee: nil, ourFeePercent: nil)
            return
        }

        let nativeTokenInBalance = $account.balances[nativeToken.slug]
        switch swapType {
        case .onChain:
            let explainedFee = explainSwapFee(.init(
                swapType: .onChain,
                tokenIn: sellingToken,
                networkFee: onchain.swapEstimate?.networkFee,
                realNetworkFee: onchain.swapEstimate?.realNetworkFee,
                ourFee: onchain.swapEstimate?.ourFee,
                dieselStatus: onchain.swapEstimate?.dieselStatus,
                dieselFee: onchain.swapEstimate?.dieselFee,
                nativeTokenInBalance: nativeTokenInBalance
            ))
            input.updateMaxAmountContext(
                swapType: .onChain,
                fullNetworkFee: explainedFee.fullFee?.networkTerms,
                ourFeePercent: onchain.swapEstimate?.ourFeePercent
            )
        case .crosschainInsideWallet, .crosschainFromWallet, .crosschainToWallet:
            let explainedFee = explainSwapFee(.init(
                swapType: swapType,
                tokenIn: sellingToken,
                networkFee: crosschain.cexEstimate?.networkFee,
                realNetworkFee: crosschain.cexEstimate?.realNetworkFee,
                ourFee: nil,
                dieselStatus: nil,
                dieselFee: nil,
                nativeTokenInBalance: nativeTokenInBalance
            ))
            input.updateMaxAmountContext(
                swapType: swapType,
                fullNetworkFee: explainedFee.fullFee?.networkTerms,
                ourFeePercent: nil
            )
        }
    }

    func applyCurrentButtonConfiguration() {
        let sellingToken = input.sellingToken
        let buyingToken = input.buyingToken

        if input.sellingAmount == nil && input.buyingAmount == nil {
            delegate?.applyButtonConfiguration(buttonModel.configurationForEmptyAmounts(
                isValidPair: isValidPair,
                sellingToken: sellingToken,
                buyingToken: buyingToken
            ))
            return
        }

        switch swapType {
        case .onChain:
            let shouldShowContinue = false
            let swapError = onchain.estimateErrorMessage ?? onchain.checkSwapError()
            if let config = buttonModel.configurationForOnchain(
                isValidPair: isValidPair,
                swapEstimate: onchain.swapEstimate,
                lateInit: onchain.lateInit,
                swapError: swapError,
                shouldShowContinue: shouldShowContinue,
                isEstimating: input.isEstimating,
                sellingToken: sellingToken,
                buyingToken: buyingToken
            ) {
                delegate?.applyButtonConfiguration(config)
            } else {
                delegate?.applyButtonConfiguration(buttonModel.configurationForEmptyAmounts(
                    isValidPair: isValidPair,
                    sellingToken: sellingToken,
                    buyingToken: buyingToken
                ))
            }
        case .crosschainInsideWallet, .crosschainToWallet, .crosschainFromWallet:
            let shouldShowContinue = swapType == .crosschainFromWallet && account.supports(chain: buyingToken.chain) == false
            let swapError = crosschain.estimateErrorMessage ?? crosschain.checkSwapError()
            if let config = buttonModel.configurationForCrosschain(
                isValidPair: isValidPair,
                swapEstimate: crosschain.cexEstimate,
                swapError: swapError,
                shouldShowContinue: shouldShowContinue,
                isEstimating: input.isEstimating,
                sellingToken: sellingToken,
                buyingToken: buyingToken
            ) {
                delegate?.applyButtonConfiguration(config)
            } else {
                delegate?.applyButtonConfiguration(buttonModel.configurationForEmptyAmounts(
                    isValidPair: isValidPair,
                    sellingToken: sellingToken,
                    buyingToken: buyingToken
                ))
            }
        }
    }
}
