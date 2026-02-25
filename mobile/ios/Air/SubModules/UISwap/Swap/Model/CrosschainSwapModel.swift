import Foundation
import WalletCore
import WalletContext
import Perception

@MainActor protocol CrosschainSwapModelDelegate: AnyObject {
    func receivedCrosschainEstimate(swapEstimate: ApiSwapCexEstimateResponse)
}

@Perceptible 
@MainActor final class CrosschainSwapModel {
    private(set) var cexEstimate: ApiSwapCexEstimateResponse?

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

    func updateEstimate(changedFrom: SwapSide, selling: TokenAmount, buying: TokenAmount, swapType: SwapType) async throws {
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
        if var swapEstimate {
            if swapType != .crosschainToWallet {
                if let feeData = try? await fetchNetworkFee(sellingToken: selling.token) {
                    swapEstimate.networkFee = feeData.networkFee
                    swapEstimate.realNetworkFee = feeData.realNetworkFee
                }
            }
            let props = ApiSwapCexEstimateResponse.calculateLateInitProperties(
                selling: selling,
                swapType: swapType,
                balances: $account.balances,
                networkFee: swapEstimate.networkFee?.value,
                dieselFee: nil,
                ourFeePercent: nil
            )
            swapEstimate.isEnoughNative = props.isEnoughNative
            swapEstimate.isDiesel = props.isDiesel
            updateCexEstimate(swapEstimate)
        } else {
            throw NilError()
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
                swapError = lang("Minimum amount", arg1: "\(fromMin) \(inputModel.sellingToken.symbol)")
            }
        }
        if let fromMax = swapEstimate.fromMax, fromMax > 0 {
            if swapEstimate.fromAmount > fromMax {
                swapError = lang("Maximum amount", arg1: "\(fromMax) \(inputModel.sellingToken.symbol)")
            }
        }
        if let toMin = swapEstimate.toMin {
            if swapEstimate.toAmount < toMin {
                swapError = lang("Minimum amount", arg1: "\(toMin) \(inputModel.buyingToken.symbol)")
            }
        }
        if let toMax = swapEstimate.toMax, toMax > 0 {
            if swapEstimate.toAmount > toMax {
                swapError = lang("Maximum amount", arg1: "\(toMax) \(inputModel.buyingToken.symbol)")
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

    private func updateCexEstimate(_ swapEstimate: ApiSwapCexEstimateResponse) {
        cexEstimate = swapEstimate
        delegate?.receivedCrosschainEstimate(swapEstimate: swapEstimate)
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
        let networkFee = draft.fee.flatMap { MDouble.forBigInt($0, decimals: decimals) }
        let realNetworkFee = draft.realFee.flatMap { MDouble.forBigInt($0, decimals: decimals) }
        return (networkFee, realNetworkFee)
    }
}
