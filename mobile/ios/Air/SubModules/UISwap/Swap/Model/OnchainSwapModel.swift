import Foundation
import WalletCore
import WalletContext
import Perception

private let log = Log("OnchainSwapModel")

@MainActor protocol OnchainSwapModelDelegate: AnyObject {
    func receivedOnchainEstimate(swapEstimate: ApiSwapEstimateResponse?, selectedDex: ApiSwapDexLabel?, lateInit: ApiSwapCexEstimateResponse.LateInitProperties?)
}

@Perceptible
@MainActor final class OnchainSwapModel {
    private(set) var swapEstimate: ApiSwapEstimateResponse?
    private(set) var lateInit: ApiSwapCexEstimateResponse.LateInitProperties?
    private(set) var estimateErrorMessage: String?
    private(set) var dex: ApiSwapDexLabel?
    private(set) var slippage: Double = 5.0

    @PerceptionIgnored
    weak var delegate: OnchainSwapModelDelegate?
    @PerceptionIgnored
    private weak var inputModel: SwapInputModel?
    @PerceptionIgnored
    @AccountContext var account: MAccount

    init(inputModel: SwapInputModel, accountContext: AccountContext) {
        self.inputModel = inputModel
        self._account = accountContext
    }

    func updateDexPreference(_ dex: ApiSwapDexLabel?) {
        self.dex = dex
        delegate?.receivedOnchainEstimate(swapEstimate: swapEstimate, selectedDex: dex, lateInit: lateInit)
    }

    func updateSlippage(_ slippage: Double) {
        self.slippage = slippage
    }

    func updateEstimate(changedFrom: SwapSide, selling: TokenAmount, buying: TokenAmount) async {
        let props = ApiSwapCexEstimateResponse.calculateLateInitProperties(
            selling: selling,
            swapType: .onChain,
            balances: $account.balances,
            networkFee: swapEstimate?.networkFee.value,
            dieselFee: swapEstimate?.dieselFee?.value,
            ourFeePercent: swapEstimate?.ourFeePercent
        )
        do {
            let fromAddress = try account.getAddress(chain: selling.token.chain).orThrow()
            let shouldTryDiesel = props.isEnoughNative == false
            let toncoinBalance = $account.balances["toncoin"].flatMap { MDouble.forBigInt($0, decimals: 9) }
            let walletVersion = account.version
            let isFromAmountMax = changedFrom == .selling && inputModel?.isUsingMax == true
            let swapEstimateRequest = ApiSwapEstimateRequest(
                from: selling.token.swapIdentifier,
                to: buying.token.swapIdentifier,
                slippage: slippage,
                fromAmount: changedFrom == .selling ? MDouble.forBigInt(selling.amount, decimals: selling.token.decimals) : nil,
                toAmount: changedFrom == .buying ? MDouble.forBigInt(buying.amount, decimals: buying.token.decimals) : nil,
                fromAddress: fromAddress,
                shouldTryDiesel: shouldTryDiesel,
                swapVersion: nil,
                toncoinBalance: toncoinBalance,
                walletVersion: walletVersion,
                isFromAmountMax: isFromAmountMax
            )

            let swapEstimate = try await Api.swapEstimate(accountId: account.id, request: swapEstimateRequest)
            try Task.checkCancellation()
            let lateInit = ApiSwapCexEstimateResponse.calculateLateInitProperties(
                selling: selling,
                swapType: .onChain,
                balances: $account.balances,
                networkFee: swapEstimate.networkFee.value,
                dieselFee: swapEstimate.dieselFee?.value,
                ourFeePercent: swapEstimate.ourFeePercent
            )
            updateEstimate(swapEstimate, lateInit: lateInit)
        } catch {
            if !Task.isCancelled {
                log.error("swapEstimate error \(error, .public)")
                updateEstimate(nil, lateInit: nil, estimateErrorMessage: mapEstimateError(error))
            }
        }
    }

    func checkSwapError() -> String? {
        guard let inputModel, let swapEstimate, let lateInit else {
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
        let notEnoughForFee = swapEstimate.toAmount?.value == 0 && lateInit.isEnoughNative == false
        if swapError == nil, notEnoughForFee {
            swapError = lang("Not Enough %symbol%", arg1: sellingToken.symbol)
        }
        if swapError == nil, lateInit.isEnoughNative == false && (lateInit.isDiesel != true || swapEstimate.dieselStatus.canContinue != true) {
            if lateInit.isDiesel == true, let swapDieselError = swapEstimate.dieselStatus.errorString {
                swapError = swapDieselError
            } else {
                let chain = sellingToken.chain
                if chain.isSupported, chain.nativeToken.slug != sellingToken.slug {
                    let nativeToken = chain.nativeToken
                    swapError = lang("Not Enough %symbol%", arg1: nativeToken.symbol)
                } else {
                    swapError = lang("Insufficient Balance")
                }
            }
        }
        return swapError
    }

    func performSwap(passcode: String) async throws {
        let swapEstimate = try self.swapEstimate.orThrow()
        // FIXME: get chain from selling token
        let fromAddress = try account.getAddress(chain: .ton).orThrow()
        let shouldTryDiesel = swapEstimate.networkFee.value > 0 &&
            $account.balances["toncoin"] ?? 0 < BigInt((swapEstimate.networkFee.value + 0.015) * 1e9) && swapEstimate.dieselStatus == .available

        let swapBuildRequest = ApiSwapBuildRequest(
            from: swapEstimate.from,
            to: swapEstimate.to,
            fromAddress: fromAddress,
            dexLabel: dex ?? swapEstimate.dexLabel,
            fromAmount: swapEstimate.fromAmount ?? .zero,
            toAmount: swapEstimate.toAmount ?? .zero,
            toMinAmount: swapEstimate.toMinAmount,
            slippage: slippage,
            shouldTryDiesel: shouldTryDiesel,
            swapVersion: nil,
            walletVersion: account.version,
            routes: swapEstimate.routes,
            networkFee: swapEstimate.realNetworkFee,
            swapFee: swapEstimate.swapFee,
            ourFee: swapEstimate.ourFee,
            dieselFee: swapEstimate.dieselFee
        )
        let transferData = try await Api.swapBuildTransfer(accountId: account.id, password: passcode, request: swapBuildRequest)
        let historyItem = ApiSwapHistoryItem.makeFrom(swapBuildRequest: swapBuildRequest, swapTransferData: transferData)
        _ = try await Api.swapSubmit(accountId: account.id, password: passcode, transfers: transferData.transfers, historyItem: historyItem, isGasless: shouldTryDiesel)
    }

    private func updateEstimate(_ swapEstimate: ApiSwapEstimateResponse?, lateInit: ApiSwapCexEstimateResponse.LateInitProperties?, estimateErrorMessage: String? = nil) {
        self.swapEstimate = swapEstimate
        self.lateInit = lateInit
        self.estimateErrorMessage = estimateErrorMessage
        delegate?.receivedOnchainEstimate(swapEstimate: swapEstimate, selectedDex: dex, lateInit: lateInit)
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
