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
    private var enqueueTask: (() -> ())?
    @PerceptionIgnored
    private var updateTask: Task<Void, Never>?
    @PerceptionIgnored
    @AccountContext var account: MAccount

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
        let maxAmount = accountContext.balances[sellingToken.slug] ?? 0

        let inputModel = SwapInputModel(
            sellingTokenSlug: sellingToken.slug,
            buyingTokenSlug: buyingToken.slug,
            maxAmount: maxAmount,
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

        self.input.delegate = self
        self.onchain.delegate = self
        self.crosschain.delegate = self
        self.detailsVM.onSlippageChanged = { [weak self] slippage in
            self?.onchain.updateSlippage(slippage)
        }
        self.detailsVM.onPreferredDexChanged = { [weak self] pref in
            self?.onchain.updateDexPreference(pref)
        }
    }

    func updateSwapType(selling: TokenAmount, buying: TokenAmount) {
        swapType = contextModel.updateSwapType(selling: selling.token, buying: buying.token, accountChains: account.supportedChains)
    }

    func swapDataChanged(changedFrom: SwapSide, selling: TokenAmount, buying: TokenAmount) async throws {

        let context = try await contextModel.updateContext(selling: selling.token, buying: buying.token, accountChains: account.supportedChains)
        swapType = context.swapType
        isValidPair = context.isValidPair
        if !isValidPair {
            let config = buttonModel.configurationForEmptyAmounts(
                isValidPair: isValidPair,
                sellingToken: selling.token,
                buyingToken: buying.token
            )
            delegate?.applyButtonConfiguration(config)
            return
        }

        if selling.amount <= 0 && buying.amount <= 0 {
            return
        }

        if swapType == .onChain {
            await onchain.updateEstimate(changedFrom: changedFrom, selling: selling, buying: buying)
        } else {
            try await crosschain.updateEstimate(changedFrom: changedFrom, selling: selling, buying: buying, swapType: swapType)
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
    func receivedOnchainEstimate(swapEstimate: ApiSwapEstimateResponse?, selectedDex _: ApiSwapDexLabel?, lateInit: ApiSwapCexEstimateResponse.LateInitProperties?) {
        guard isValidPair else {
            let config = buttonModel.configurationForEmptyAmounts(
                isValidPair: isValidPair,
                sellingToken: input.sellingToken,
                buyingToken: input.buyingToken
            )
            delegate?.applyButtonConfiguration(config)
            return
        }

        let swapError = onchain.estimateErrorMessage ?? onchain.checkSwapError()
        if let swapEstimate, let lateInit {
            let displayEstimate = swapEstimate.displayEstimate(selectedDex: onchain.dex)
            let estimate = SwapInputModel.Estimate(
                fromAmount: displayEstimate.fromAmount?.value ?? 0,
                toAmount: displayEstimate.toAmount?.value ?? 0,
                maxAmount: lateInit.maxAmount
            )
            input.updateWithEstimate(estimate)
        }
        let shouldShowContinue = swapType == .crosschainFromWallet && account.supports(chain: input.buyingToken.chain) == false
        if let config = buttonModel.configurationForOnchain(
            isValidPair: isValidPair,
            swapEstimate: swapEstimate,
            lateInit: lateInit,
            swapError: swapError,
            shouldShowContinue: shouldShowContinue,
            sellingToken: input.sellingToken,
            buyingToken: input.buyingToken
        ) {
            delegate?.applyButtonConfiguration(config)
        } else {
            let config = buttonModel.configurationForEmptyAmounts(
                isValidPair: isValidPair,
                sellingToken: input.sellingToken,
                buyingToken: input.buyingToken
            )
            delegate?.applyButtonConfiguration(config)
        }
    }
}

extension SwapModel: CrosschainSwapModelDelegate {
    func receivedCrosschainEstimate(swapEstimate: ApiSwapCexEstimateResponse) {
        guard isValidPair else {
            let config = buttonModel.configurationForEmptyAmounts(
                isValidPair: isValidPair,
                sellingToken: input.sellingToken,
                buyingToken: input.buyingToken
            )
            delegate?.applyButtonConfiguration(config)
            return
        }

        input.updateWithEstimate(.init(fromAmount: swapEstimate.fromAmount.value, toAmount: swapEstimate.toAmount.value))

        let swapError = crosschain.checkSwapError()
        let shouldShowContinue = swapType == .crosschainFromWallet && account.supports(chain: input.buyingToken.chain) == false
        if let config = buttonModel.configurationForCrosschain(
            isValidPair: isValidPair,
            swapEstimate: swapEstimate,
            swapError: swapError,
            shouldShowContinue: shouldShowContinue,
            sellingToken: input.sellingToken,
            buyingToken: input.buyingToken
        ) {
            delegate?.applyButtonConfiguration(config)
        } else {
            let config = buttonModel.configurationForEmptyAmounts(
                isValidPair: isValidPair,
                sellingToken: input.sellingToken,
                buyingToken: input.buyingToken
            )
            delegate?.applyButtonConfiguration(config)
        }
    }
}

extension SwapModel: SwapInputModelDelegate {
    func swapDataChanged(swapSide: SwapSide, selling: TokenAmount, buying: TokenAmount) {

        updateSwapType(selling: selling, buying: buying)

        enqueueTask = { [weak self] in
            guard let self else { return }
            updateTask?.cancel()
            updateTask = Task { [weak self] in
                do {
                    try await self?.swapDataChanged(changedFrom: swapSide, selling: selling, buying: buying)
                } catch {
                }
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else {
                    return
                }
                self?.enqueueTask?()
            }
        }

        enqueueTask?()

        if (swapSide == .selling && selling.amount <= 0) || (swapSide == .buying && buying.amount <= 0) {
            let config = buttonModel.configurationForEmptyAmounts(
                isValidPair: isValidPair,
                sellingToken: input.sellingToken,
                buyingToken: input.buyingToken
            )
            delegate?.applyButtonConfiguration(config)
            return
        }
    }

    func maxAmountPressed(maxAmount: BigInt?) {
        var maxAmount = maxAmount ?? $account.balances[input.sellingToken.slug] ?? 0
        let networkFee: Double?
        switch swapType {
        case .onChain:
            networkFee = onchain.swapEstimate?.networkFee.value
        case .crosschainInsideWallet, .crosschainFromWallet:
            networkFee = crosschain.cexEstimate?.networkFee?.value
        case .crosschainToWallet:
            networkFee = nil
        }
        let feeData = FeeEstimationHelpers.networkFeeBigInt(
            sellToken: input.sellingToken,
            swapType: swapType,
            networkFee: networkFee
        )
        if feeData?.isNativeIn == true {
            maxAmount -= feeData!.fee

            if swapType == .onChain {
                let amountForNextSwap = feeData?.chain?.gas.maxSwap ?? 0
                let amountIn = input.sellingAmount ?? 0
                let shouldIgnoreNextSwap = amountIn > 0 && (maxAmount - amountIn) <= amountForNextSwap
                if !shouldIgnoreNextSwap && maxAmount > amountForNextSwap {
                    maxAmount -= amountForNextSwap
                }
            }
        }
        input.sellingAmount = max(0, maxAmount)
        swapDataChanged(
            swapSide: .selling,
            selling: input.sellingTokenAmount,
            buying: input.buyingTokenAmount,
        )
    }
}
