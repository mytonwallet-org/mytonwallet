import SwiftUI
import UIKit
import UIComponents
import WalletCore
import WalletContext
import Perception

@MainActor private let slippageFont = WTypography.uiFont(.amountSecondary, content: .technical)

@MainActor struct SwapDetailsVM {
    var fromToken: ApiToken { inputModel.sellingToken }
    var toToken: ApiToken { inputModel.buyingToken }
    let swapEstimate: ApiSwapEstimateResponse?
    
    private var inputModel: SwapInputModel
    
    var displayImpactWarning: Double? {
        if let impact = displayEstimate?.impact, impact > MAX_PRICE_IMPACT_VALUE {
            return impact
        }
        return nil
    }
    
    init(onchainModel: OnchainSwapModel, inputModel: SwapInputModel) {
        self.swapEstimate = onchainModel.swapEstimate
        self.inputModel = inputModel
    }

    var displayEstimate: ApiSwapEstimateResponse? {
        swapEstimate
    }
    var displayExchangeRate: SwapRate? {
        if let est = displayEstimate {
            return ExchangeRateHelpers.getSwapRate(
                fromAmount: est.fromAmount?.value,
                toAmount: est.toAmount?.value,
                fromToken: fromToken,
                toToken: toToken
            )
        }
        return nil
    }
    
    var feeDetails: ExplainedTransferFee? {
        guard let displayEstimate,
              let nativeToken = TokenStore.tokens[fromToken.nativeTokenSlug] else {
            return nil
        }
        let explainedFee = explainSwapFee(.init(
            swapType: .onChain,
            tokenIn: fromToken,
            networkFee: displayEstimate.networkFee,
            realNetworkFee: displayEstimate.realNetworkFee,
            dieselStatus: displayEstimate.dieselStatus,
            dieselFee: displayEstimate.dieselFee,
            nativeTokenInBalance: inputModel.$account.balances[nativeToken.slug]
        ))
        return explainedFee.networkFeeDetails
    }
}

struct SwapDetailsView: View {

    var model: SwapDetailsVM
    var slippage: BigInt
    var onSlippageCommit: (BigInt) -> Void
    var sellingToken: ApiToken { model.fromToken }
    var buyingToken: ApiToken { model.toToken }
    var exchangeRate: SwapRate? { model.displayExchangeRate }
    var swapEstimate: ApiSwapEstimateResponse? { model.swapEstimate }
    var displayEstimate: ApiSwapEstimateResponse? { model.displayEstimate }
    
    @State private var slippageFocused: Bool = false
    @State private var isExpanded = false
    @State private var slippageExpanded = false
    @State private var draftSlippage: BigInt? = DEFAULT_SLIPPAGE
    
    private var slippageError: Bool {
        guard let draftSlippage else { return false }
        return draftSlippage <= BigInt(0) || draftSlippage > MAX_SLIPPAGE_VALUE
    }
    
    var body: some View {
        WithPerceptionTracking {
            SwapDetailsContainer(isExpanded: $isExpanded) {
                pricePerCoinRow
                slippageRow
                blockchainFeeRow
                priceImpactRow
                minimumReceivedRow
            }
            .animation(.snappy, value: slippageExpanded)
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
                            .textStyle(
                                .body,
                                content: .technical,
                                scaling: .dynamic
                            )
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    var slippageRow: some View {
        VStack(spacing: 0) {
            InsetDetailCell(alignment: .firstTextBaseline) {
                Text(lang("Slippage"))
                    .foregroundStyle(Color.air.secondaryLabel)
                    .overlay(alignment: .trailingFirstTextBaseline) {
                        InfoButton(
                            title: lang("Slippage"),
                            message: lang("$swap_slippage_tooltip1") + "\n\n" + lang("$swap_slippage_tooltip2")
                        )
                    }
                
            } value: {
                if !slippageExpanded {
                    SlippagePickerButton(value: slippage) {
                        topViewController()?.view.endEditing(true)
                        draftSlippage = slippage
                        slippageExpanded = true
                    }
                    .transition(.scale.combined(with: .opacity))
                } else {
                    Button(action: {
                        topViewController()?.view.endEditing(true)
                        let nextSlippage = normalizedSwapSlippage(draftSlippage)
                        draftSlippage = nextSlippage
                        onSlippageCommit(nextSlippage)
                        slippageExpanded = false
                    }) {
                        Text(lang("Done"))
                            .textStyle(.bodyStrong, scaling: .dynamic)
                    }
                    .transition(.scale.combined(with: .opacity))
                }
            }
            if slippageExpanded {
                HStack(alignment: .firstTextBaseline) {
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        WUIAmountInput(amount: $draftSlippage, maximumFractionDigits: SLIPPAGE_DECIMALS, font: slippageFont, fractionFont: slippageFont, alignment: .right, isFocused: $slippageFocused, error: slippageError)
                            .frame(width: 68)
                        Text("%")
                            .textStyle(.amountSecondary, content: .technical)
                    }
                    .padding(8)
                    .contentShape(.rect)
                    .onTapGesture {
                        slippageFocused = true
                    }
                    .padding(-8)
                    
                    Spacer()
                    
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        slippageChoice(value: BigInt(2))
                        slippageChoice(value: BigInt(5))
                        slippageChoice(value: BigInt(10))
                        slippageChoice(value: BigInt(20))
                        slippageChoice(value: BigInt(50))
                        slippageChoice(value: BigInt(100))
                    }
                    .fixedSize()
                    .textStyle(.footnoteEmphasized, content: .technical)
                }
                .padding(.horizontal, 16)
                .padding(.top, 2)
                .padding(.bottom, 10)
            }
        }
    }
    
    func slippageChoice(value: BigInt) -> some View {
        
        Button(action: { draftSlippage = value }) {
            Text("\(formatBigIntText(value, tokenDecimals: 1))%")
                .padding(4)
                .contentShape(.rect)
        }
        .padding(-4)
    }
    
    @ViewBuilder
    var blockchainFeeRow: some View {
        if let displayEstimate {
            let nativeToken = TokenStore.tokens[sellingToken.nativeTokenSlug]
            let feeDetails = model.feeDetails
            InsetDetailCell {
                SwapBlockchainFeeLabel(nativeToken: nativeToken, feeDetails: feeDetails)
            } value: {
                if let nativeToken,
                   let feeDetails {
                    FeeView(
                        token: sellingToken,
                        nativeToken: nativeToken,
                        fee: nil,
                        explainedTransferFee: feeDetails,
                        includeLabel: false,
                        showDetailsButton: false
                    )
                } else if let tonToken = TokenStore.tokens[TONCOIN_SLUG] {
                    let fee = sellingToken.chain == .ton ? displayEstimate.realNetworkFee : displayEstimate.networkFee
                    let feeAmountString = DecimalAmount.fromDouble(fee.value, tonToken).formatted(.fee)
                    Text("~\(feeAmountString)")
                        .textStyle(
                            .body,
                            content: .technical,
                            scaling: .dynamic
                        )
                }
            }
        }
    }
    
    @ViewBuilder
    var priceImpactRow: some View {
        if let displayEstimate {
            InsetDetailCell {
                Text(lang("Price Impact"))
                    .foregroundStyle(Color.air.secondaryLabel)
                    .overlay(alignment: .trailingFirstTextBaseline) {
                        InfoButton(title: lang("Price Impact"), message: lang("$swap_price_impact_tooltip1") + "\n\n" +  lang("$swap_price_impact_tooltip2"))
                    }
            } value: {
                HStack(spacing: 3) {
                    Text(formatPercent(displayEstimate.impact / 100, decimals: 1, showPlus: false))
                        .textStyle(
                            .body,
                            content: .technical,
                            scaling: .dynamic
                        )
                    if model.displayImpactWarning != nil {
                        Text(Image(systemName: "exclamationmark.triangle.fill"))
                            .textStyle(
                                .body,
                                content: .technical,
                                scaling: .dynamic
                            )
                            .foregroundStyle(.red)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    var minimumReceivedRow: some View {
        if let displayEstimate {
            InsetDetailCell {
                Text(lang("Minimum Received"))
                    .foregroundStyle(Color.air.secondaryLabel)
                    .overlay(alignment: .trailingFirstTextBaseline) {
                        InfoButton(title: lang("Minimum Received"), message: lang("$swap_minimum_received_tooltip2"))
                    }
            } value: {
                let minAmount = DecimalAmount.fromDouble(displayEstimate.toMinAmount.value, buyingToken)
                Text(minAmount.formatted(.baseCurrencyHighPrecision, roundHalfUp: false))
                    .textStyle(
                        .body,
                        content: .technical,
                        scaling: .dynamic
                    )
            }
        }
    }
}

private struct SlippagePickerButton: View {
    
    var value: BigInt
    var onTap: () -> ()
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 2) {
                Text("\(formatBigIntText(value, tokenDecimals: 1))%")
                    .textStyle(.bodyEmphasized, content: .technical)
                
                Image("SendPickToken", bundle: AirBundle)
                    .textStyle(.footnote, content: .technical)
                    .foregroundStyle(.secondary)
            }
            .fixedSize()
            .padding(.leading, 18)
            .padding(.trailing, 14)
            .padding(.vertical, 8)
            .background(Color.air.secondaryFill, in: .capsule)
        }
        .buttonStyle(.plain)
    }
}

struct SwapBlockchainFeeLabel: View {

    var nativeToken: ApiToken?
    var feeDetails: ExplainedTransferFee?

    var body: some View {
        Text(lang("Blockchain Fee"))
            .foregroundStyle(Color.air.secondaryLabel)
            .overlay(alignment: .trailingFirstTextBaseline) {
                if let nativeToken, let feeDetails {
                    SwapFeeDetailsInfoButton(nativeToken: nativeToken, feeDetails: feeDetails)
                }
            }
    }
}

private struct SwapFeeDetailsInfoButton: View {

    var nativeToken: ApiToken
    var feeDetails: ExplainedTransferFee

    var body: some View {
        if feeDetails.supportsLegacyDetailsView {
            Button(action: showFeeDetails) {
                Image.airBundle("InfoIcon")
                    .renderingMode(.template)
                    .foregroundStyle(Color(.air.secondaryLabel.withAlphaComponent(0.3)))
                    .padding(4)
                    .contentShape(.circle)
            }
            .padding(-4)
            .buttonStyle(.plain)
            .offset(x: 22, y: 1.333)
            .accessibilityLabel(lang("Blockchain Fee Details"))
            .accessibilityHint(lang("Shows more information"))
        }
    }

    func showFeeDetails() {
        if let vc = topWViewController() {
            vc.view.endEditing(true)
            vc.showTip(title: "Blockchain Fee Details", wide: true) {
                FeeDetailsView(nativeToken: nativeToken, fee: feeDetails)
            }
        }
    }
}
