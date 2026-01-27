import SwiftUI
import UIComponents
import WalletCore
import WalletContext
import Perception

struct SwapCexDetailsView: View {

    var inputModel: SwapInputModel
    var crosschainModel: CrosschainSwapModel
    var swapType: SwapType
    
    var sellingToken: ApiToken { inputModel.sellingToken }
    var buyingToken: ApiToken { inputModel.buyingToken }
    var exchangeRate: SwapRate? { displayExchangeRate }
    var swapEstimate: ApiSwapCexEstimateResponse? { crosschainModel.cexEstimate }
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
            InsetSection(horizontalPadding: 0) {
                header
                    
                if isExpanded {
                    pricePerCoinRow
                    blockchainFeeRow
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxHeight: isExpanded ? nil : 44, alignment: .top)
            .frame(height: 400, alignment: .top)
            .tint(Color(WTheme.tint))
            .animation(.spring(duration: isExpanded ? 0.45 : 0.3), value: isExpanded)
        }
    }
    
    var header: some View {
        Button(action: { isExpanded.toggle() }) {
            InsetCell {
                HStack {
                    Text(lang("Swap Details"))
                        .textCase(.uppercase)
                    Spacer()
                    Image.airBundle("RightArrowIcon")
                        .renderingMode(.template)
                        .rotationEffect(isExpanded ? .radians(-0.5 * .pi) : .radians(0.5 * .pi))
                }
                .font13()
                .tint(Color(WTheme.secondaryLabel))
                .foregroundStyle(Color(WTheme.secondaryLabel))
            }
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(InsetButtonStyle())
    }
    
    @ViewBuilder
    var pricePerCoinRow: some View {
        
        if let exchangeRate = exchangeRate, displayEstimate != nil {
            InsetCell {
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 0) {
                        Text(lang("Exchange Rate"))
                            .foregroundStyle(Color(WTheme.secondaryLabel))
                        Spacer(minLength: 4)
                        let priceAmount = DecimalAmount.fromDouble(exchangeRate.price, exchangeRate.fromToken)
                        Text("\(exchangeRate.toToken.symbol) ≈ \(priceAmount.formatted(.none, maxDecimals: min(6, sellingToken.decimals)))")
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
                    .foregroundStyle(Color(WTheme.secondaryLabel))
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
        
        // TODO: Swap fee
    }
}
