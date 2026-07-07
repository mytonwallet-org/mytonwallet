import SwiftUI
import UIComponents
import WalletCore
import WalletContext
import Perception

struct SwapCexDetailsView: View {

    var inputModel: SwapInputModel
    var swapEstimate: ApiSwapCexEstimateResponse?
    var swapType: SwapType
    
    var sellingToken: ApiToken { inputModel.sellingToken }
    var buyingToken: ApiToken { inputModel.buyingToken }
    var exchangeRate: SwapRate? { displayExchangeRate }
    var displayEstimate: ApiSwapCexEstimateResponse? { swapEstimate }

    var displayExchangeRate: SwapRate? {
        if let est = swapEstimate {
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
        guard let swapEstimate,
              let nativeToken = TokenStore.tokens[sellingToken.nativeTokenSlug] else {
            return nil
        }
        let explainedFee = explainSwapFee(.init(
            swapType: swapType,
            tokenIn: sellingToken,
            networkFee: swapEstimate.networkFee,
            realNetworkFee: swapEstimate.realNetworkFee,
            ourFee: nil,
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
        
        if let exchangeRate = exchangeRate, displayEstimate != nil {
            InsetCell {
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 0) {
                        Text(lang("Exchange Rate"))
                            .foregroundStyle(Color.air.secondaryLabel)
                        Spacer(minLength: 4)
                        let priceAmount = DecimalAmount.fromDouble(exchangeRate.price, exchangeRate.fromToken)
                        Text("\(exchangeRate.toToken.symbol) ≈ \(priceAmount.formatted(.compact))")
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    var blockchainFeeRow: some View {
        let sellingToken = inputModel.sellingToken
        if let feeDetails, let nativeToken = TokenStore.tokens[sellingToken.nativeTokenSlug] {
            InsetDetailCell {
                Text(lang("Blockchain Fee"))
                    .foregroundStyle(Color.air.secondaryLabel)
            } value: {
                FeeView(
                    token: sellingToken,
                    nativeToken: nativeToken,
                    fee: feeDetails.realFee ?? feeDetails.fullFee,
                    explainedTransferFee: feeDetails,
                    includeLabel: false
                )
            }
        }
    }
}
