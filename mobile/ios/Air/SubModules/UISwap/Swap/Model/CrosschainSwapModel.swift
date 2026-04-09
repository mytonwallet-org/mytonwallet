import Foundation
import WalletCore
import WalletContext
import Perception

@MainActor protocol CrosschainSwapModelDelegate: AnyObject {
    func receivedCrosschainEstimate(changedFrom: SwapSide, swapEstimate: ApiSwapCexEstimateResponse?)
}

@Perceptible
@MainActor final class CrosschainSwapModel {
    private(set) var cexEstimate: ApiSwapCexEstimateResponse?
    private(set) var estimateErrorMessage: String?

    @PerceptionIgnored
    weak var delegate: CrosschainSwapModelDelegate?
    @PerceptionIgnored
    private weak var inputModel: SwapInputModel?
    @PerceptionIgnored
    @AccountContext var account: MAccount

    init(inputModel: SwapInputModel, accountContext: AccountContext) {
        self.inputModel = inputModel
        self._account = accountContext
    }

    func updateEstimate(changedFrom: SwapSide, selling: TokenAmount, buying: TokenAmount, swapType: SwapType) async {
        do {
            let options: ApiSwapCexEstimateOptions
            if changedFrom == .selling {
                options = ApiSwapCexEstimateOptions(
                    from: selling.token.swapIdentifier,
                    to: buying.token.swapIdentifier,
                    fromAmount: String(selling.amount.doubleAbsRepresentation(decimals: selling.token.decimals))
                )
            } else {
                options = ApiSwapCexEstimateOptions(
                    from: buying.token.swapIdentifier,
                    to: selling.token.swapIdentifier,
                    fromAmount: String(buying.amount.doubleAbsRepresentation(decimals: buying.token.decimals))
                )
            }
            var swapEstimate = try await Api.swapCexEstimate(swapEstimateOptions: options)
            try Task.checkCancellation()

            if changedFrom == .buying {
                swapEstimate?.reverse()
            }
            guard var swapEstimate else {
                updateEstimate(changedFrom: changedFrom, nil, estimateErrorMessage: lang("Invalid Pair"))
                return
            }

            if swapType != .crosschainToWallet {
                if let feeData = try? await fetchNetworkFee(sellingToken: selling.token) {
                    swapEstimate.networkFee = feeData.networkFee
                    swapEstimate.realNetworkFee = feeData.realNetworkFee
                }
            }
            let resolvedSelling = TokenAmount(
                DecimalAmount.fromDouble(swapEstimate.fromAmount.value, selling.token).roundedForSwap.amount,
                selling.token
            )
            swapEstimate.isEnoughNative = isEnoughNativeForCrosschain(
                selling: resolvedSelling,
                swapType: swapType,
                networkFee: swapEstimate.networkFee?.value
            )
            swapEstimate.dieselStatus = .notAvailable
            updateEstimate(changedFrom: changedFrom, swapEstimate)
        } catch {
            if !Task.isCancelled {
                updateEstimate(changedFrom: changedFrom, nil, estimateErrorMessage: mapEstimateError(error))
            }
        }
    }

    func checkSwapError() -> String? {
        guard let inputModel, let swapEstimate = cexEstimate else {
            return nil
        }
        var swapError: String? = nil
        let sellingToken = inputModel.sellingToken
        var balanceIn = $account.balances[sellingToken.slug] ?? 0
        if sellingToken.slug == TRX_SLUG && account.supports(chain: .tron) {
            balanceIn -= 1
        }
        if account.supports(chain: sellingToken.chain) {
            if let sellingAmount = inputModel.sellingAmount, balanceIn < sellingAmount {
                swapError = lang("Insufficient Balance")
            }
        }
        if swapEstimate.isEnoughNative == false {
            swapError = lang("Insufficient Balance")
        }
        if let fromMin = swapEstimate.fromMin {
            if swapEstimate.fromAmount < fromMin {
                swapError = lang("Minimum amount", arg1: "\(fromMin) \(inputModel.sellingToken.symbol)")
            }
        }
        if let fromMax = swapEstimate.fromMax, fromMax > 0 {
            if swapEstimate.fromAmount > fromMax {
                swapError = lang("Maximum amount", arg1: "\(fromMax) \(inputModel.sellingToken.symbol)")
            }
        }
        return swapError
    }

    func performSwap(swapType: SwapType, sellingToken: ApiToken, buyingToken: ApiToken, passcode: String) async throws -> ApiActivity? {
        guard let swapEstimate = cexEstimate else {
            return nil
        }
        switch swapType {
        case .crosschainFromWallet:
            return try await performFromWalletSwap(swapEstimate: swapEstimate, sellingToken: sellingToken, buyingToken: buyingToken, passcode: passcode)
        case .crosschainInsideWallet, .crosschainToWallet:
            return try await performToWalletSwap(swapEstimate: swapEstimate, sellingToken: sellingToken, buyingToken: buyingToken, passcode: passcode)
        case .onChain:
            return nil
        }
    }

    private func performToWalletSwap(swapEstimate: ApiSwapCexEstimateResponse, sellingToken: ApiToken, buyingToken: ApiToken, passcode: String) async throws -> ApiActivity? {
        let fromAddress = account.crosschainIdentifyingFromAddress
        let toAddress = account.getAddress(chain: buyingToken.chain)
        let networkFee = swapEstimate.realNetworkFee ?? swapEstimate.networkFee
        let params = ApiSwapCexCreateTransactionParams(
            from: sellingToken.swapIdentifier,
            fromAmount: swapEstimate.fromAmount,
            fromAddress: fromAddress ?? "",
            to: buyingToken.swapIdentifier,
            toAddress: toAddress ?? "",
            swapFee: swapEstimate.swapFee,
            networkFee: networkFee
        )
        return try await SwapCexSupport.swapCexCreateTransaction(
            accountId: account.id,
            sellingToken: sellingToken,
            params: params,
            shouldTransfer: account.supports(chain: sellingToken.chain),
            passcode: passcode
        )
    }

    private func performFromWalletSwap(swapEstimate: ApiSwapCexEstimateResponse, sellingToken: ApiToken, buyingToken: ApiToken, passcode: String) async throws -> ApiActivity? {
        let fromAddress = account.getAddress(chain: sellingToken.chain)
        let toAddress = account.getAddress(chain: buyingToken.chain)
        let networkFee = swapEstimate.realNetworkFee ?? swapEstimate.networkFee
        let params = ApiSwapCexCreateTransactionParams(
            from: sellingToken.swapIdentifier,
            fromAmount: swapEstimate.fromAmount,
            fromAddress: fromAddress ?? "",
            to: buyingToken.swapIdentifier,
            toAddress: toAddress ?? "",
            swapFee: swapEstimate.swapFee,
            networkFee: networkFee
        )
        return try await SwapCexSupport.swapCexCreateTransaction(
            accountId: account.id,
            sellingToken: sellingToken,
            params: params,
            shouldTransfer: true,
            passcode: passcode
        )
    }

    private func updateEstimate(changedFrom: SwapSide, _ swapEstimate: ApiSwapCexEstimateResponse?, estimateErrorMessage: String? = nil) {
        cexEstimate = swapEstimate
        self.estimateErrorMessage = estimateErrorMessage
        delegate?.receivedCrosschainEstimate(changedFrom: changedFrom, swapEstimate: swapEstimate)
    }

    private func isEnoughNativeForCrosschain(selling: TokenAmount, swapType: SwapType, networkFee: Double?) -> Bool? {
        if swapType == .crosschainToWallet {
            return true
        }
        guard
            account.supports(chain: selling.token.chain),
            let tokenBalance = $account.balances[selling.token.slug],
            let nativeToken = TokenStore.tokens[selling.token.nativeTokenSlug],
            let nativeTokenBalance = $account.balances[nativeToken.slug],
            let networkFee,
            let networkFeeData = FeeEstimationHelpers.networkFeeBigInt(
                sellToken: selling.token,
                swapType: swapType,
                networkFee: networkFee
            ),
            let maxAmount = getMaxSwapAmount(.init(
                swapType: swapType,
                tokenBalance: tokenBalance,
                tokenIn: selling.token,
                fullNetworkFee: .init(token: nil, native: networkFeeData.fee, stars: nil),
                ourFeePercent: 0,
                maxAmountFromBackend: nil
            ))
        else {
            return nil
        }

        return selling.amount <= maxAmount && networkFeeData.fee <= nativeTokenBalance
    }

    private func fetchNetworkFee(sellingToken: ApiToken) async throws -> (networkFee: MDouble?, realNetworkFee: MDouble?) {
        let chain = sellingToken.chain
        let options = ApiCheckTransactionDraftOptions(
            accountId: account.id,
            toAddress: getChainConfig(chain: chain).feeCheckAddress,
            amount: nil,
            payload: nil,
            stateInit: nil,
            tokenAddress: sellingToken.tokenAddress,
            allowGasless: false
        )
        let draft = try await Api.checkTransactionDraft(chain: chain, options: options)
        let decimals = chain.nativeToken.decimals
        let networkFee = draft.fullNativeFee.flatMap { MDouble.forBigInt($0, decimals: decimals) }
        let realNetworkFee = draft.realNativeFee.flatMap { MDouble.forBigInt($0, decimals: decimals) }
        return (networkFee, realNetworkFee)
    }

    private func mapEstimateError(_ error: Error) -> String {
        if let bridgeError = error as? BridgeCallError {
            switch bridgeError {
            case .apiReturnedError(let error, _):
                return mapEstimateErrorMessage(error)
            case .customMessage(let message, _):
                return mapEstimateErrorMessage(message)
            case .message(let message, _):
                return mapEstimateErrorMessage(message.rawValue)
            case .unknown(let baseError):
                if let baseError = baseError as? BridgeCallError {
                    return mapEstimateError(baseError)
                }
            }
        }
        return lang("Unexpected Error")
    }

    private func mapEstimateErrorMessage(_ message: String) -> String {
        switch message.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "Insufficient liquidity":
            return lang("Insufficient liquidity")
        case "Tokens must be different", "Asset not found", "Pair not found":
            return lang("Invalid Pair")
        case "Too small amount":
            return lang("$swap_too_small_amount")
        default:
            return lang("Unexpected Error")
        }
    }
}
