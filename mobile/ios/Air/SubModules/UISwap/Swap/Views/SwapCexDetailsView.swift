import SwiftUI
import UIComponents
import WalletCore
import WalletContext
import Perception

struct SwapCexDetailsView: View {

    var inputModel: SwapInputModel
    var swapEstimate: ApiSwapCexEstimateResponse?
    var swapType: SwapType
    
    var sellingToken: ApiToken? { inputModel.sellingToken }
    var buyingToken: ApiToken? { inputModel.buyingToken }
    var exchangeRate: SwapRate? { displayExchangeRate }
    var displayEstimate: ApiSwapCexEstimateResponse? { swapEstimate }

    var displayExchangeRate: SwapRate? {
        if let est = swapEstimate, let sellingToken, let buyingToken {
            return ExchangeRateHelpers.getSwapRate(
                fromAmount: est.fromAmount.value,
                toAmount: est.toAmount.value,
                fromToken: sellingToken,
                toToken: buyingToken
            )
        }
        return nil
    }

    @State private var isExpanded = false

    var feeDetails: ExplainedTransferFee? {
        guard let swapEstimate, let sellingToken,
              let nativeToken = TokenStore.tokens[sellingToken.nativeTokenSlug] else {
            return nil
        }
        let explainedFee = explainSwapFee(.init(
            swapType: swapType,
            tokenIn: sellingToken,
            networkFee: swapEstimate.networkFee,
            realNetworkFee: swapEstimate.realNetworkFee,
            dieselStatus: nil,
            dieselFee: nil,
            nativeTokenInBalance: inputModel.$account.balances[nativeToken.slug]
        ))
        return explainedFee.networkFeeDetails
    }
    
    var body: some View {
        WithPerceptionTracking {
            SwapDetailsContainer(isExpanded: $isExpanded) {
                pricePerCoinRow
                blockchainFeeRow
            }
        }
    }
    
    @ViewBuilder
    var pricePerCoinRow: some View {
        SwapExchangeRateRow(exchangeRate: exchangeRate)
    }
    
    @ViewBuilder
    var blockchainFeeRow: some View {
        if let sellingToken, let feeDetails, let nativeToken = TokenStore.tokens[sellingToken.nativeTokenSlug] {
            SwapBlockchainFeeRow(nativeToken: nativeToken, feeDetails: feeDetails) {
                FeeView(
                    token: sellingToken,
                    nativeToken: nativeToken,
                    fee: feeDetails.realFee ?? feeDetails.fullFee,
                    explainedTransferFee: feeDetails,
                    includeLabel: false,
                    showDetailsButton: false
                )
            }
        }
    }
}
