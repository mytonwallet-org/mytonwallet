import SwiftUI
import UIKit
import UIComponents
import WalletCore
import WalletContext
import Perception

@MainActor private let slippageFont = WTypography.uiFont(.amountSecondary, content: .technical)
private let swapDetailsInfoButtonOffset = CGSize(width: 0, height: 1.333)

@MainActor struct SwapDetailsVM {
    var fromToken: ApiToken? { inputModel.sellingToken }
    var toToken: ApiToken? { inputModel.buyingToken }
    let swapEstimate: ApiSwapDexEstimateResponse?
    
    private var inputModel: SwapInputModel
    
    var displayImpactWarning: Double? {
        if let impact = displayEstimate?.impact, impact > MAX_PRICE_IMPACT_VALUE {
            return impact
        }
        return nil
    }
    
    init(swapEstimate: ApiSwapDexEstimateResponse?, inputModel: SwapInputModel) {
        self.swapEstimate = swapEstimate
        self.inputModel = inputModel
    }

    var displayEstimate: ApiSwapDexEstimateResponse? {
        swapEstimate
    }
    var displayExchangeRate: SwapRate? {
        if let est = displayEstimate, let fromToken, let toToken {
            return ExchangeRateHelpers.getSwapRate(
                fromAmount: est.fromAmount.value,
                toAmount: est.toAmount.value,
                fromToken: fromToken,
                toToken: toToken
            )
        }
        return nil
    }
    
    var feeDetails: ExplainedTransferFee? {
        guard let displayEstimate, let fromToken,
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
    var isFeeError: Bool
    var onSlippageCommit: (BigInt) -> Void
    var sellingToken: ApiToken? { model.fromToken }
    var buyingToken: ApiToken? { model.toToken }
    var exchangeRate: SwapRate? { model.displayExchangeRate }
    var swapEstimate: ApiSwapDexEstimateResponse? { model.swapEstimate }
    var displayEstimate: ApiSwapDexEstimateResponse? { model.displayEstimate }
    
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
            .onAppear { if isFeeError { isExpanded = true } }
            .onChange(of: isFeeError) { if $0 { isExpanded = true } }
        }
    }
    
    @ViewBuilder
    var pricePerCoinRow: some View {
        SwapExchangeRateRow(exchangeRate: exchangeRate)
    }
    
    @ViewBuilder
    var slippageRow: some View {
        VStack(spacing: 0) {
            SwapDetailCell(alignment: .firstTextBaseline) {
                SwapDetailLabel(title: lang("Slippage")) {
                    InfoButton(
                        title: lang("Slippage"),
                        message: lang("$swap_slippage_tooltip1") + "\n\n" + lang("$swap_slippage_tooltip2"),
                        offset: swapDetailsInfoButtonOffset
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
                        ForEach(SWAP_SLIPPAGE_PRESETS, id: \.self) { value in
                            slippageChoice(value: value)
                        }
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
        if let displayEstimate, let sellingToken {
            let nativeToken = TokenStore.tokens[sellingToken.nativeTokenSlug]
            let feeDetails = model.feeDetails
            if let nativeToken, let feeDetails {
                SwapBlockchainFeeRow(nativeToken: nativeToken, feeDetails: feeDetails) {
                    FeeView(
                        token: sellingToken,
                        nativeToken: nativeToken,
                        fee: isFeeError ? feeDetails.fullFee : nil,
                        explainedTransferFee: feeDetails,
                        includeLabel: false,
                        showDetailsButton: false,
                        isError: isFeeError
                    )
                }
            } else if let tonToken = TokenStore.tokens[TONCOIN_SLUG] {
                SwapBlockchainFeeRow(nativeToken: nil, feeDetails: nil) {
                    let fee = isFeeError || sellingToken.chain != .ton ? displayEstimate.networkFee : displayEstimate.realNetworkFee
                    let feeAmountString = DecimalAmount.fromDouble(fee.value, tonToken).formatted(.fee)
                    Text("\(isFeeError ? "" : "~")\(feeAmountString)")
                        .foregroundStyle(isFeeError ? Color.air.error : Color.air.primaryLabel)
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
            SwapDetailCell {
                SwapDetailLabel(title: lang("Price Impact")) {
                    InfoButton(title: lang("Price Impact"), message: lang("$swap_price_impact_tooltip1") + "\n\n" +  lang("$swap_price_impact_tooltip2"), offset: swapDetailsInfoButtonOffset)
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
        if let displayEstimate, let buyingToken {
            SwapDetailCell {
                SwapDetailLabel(title: lang("Minimum Received")) {
                    InfoButton(title: lang("Minimum Received"), message: lang("$swap_minimum_received_tooltip2"), offset: swapDetailsInfoButtonOffset)
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

private struct SwapDetailLabel<Info: View>: View {
    var title: String
    @ViewBuilder var info: Info

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(title)
                .fixedSize(horizontal: false, vertical: true)
            info
                .fixedSize()
        }
        .foregroundStyle(Color.air.secondaryLabel)
    }
}

struct SwapBlockchainFeeLabel: View {

    var nativeToken: ApiToken?
    var feeDetails: ExplainedTransferFee?

    var body: some View {
        SwapDetailLabel(title: lang("Blockchain Fee")) {
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
            .offset(swapDetailsInfoButtonOffset)
            .accessibilityLabel(lang("Blockchain Fee Details"))
            .accessibilityHint(lang("Shows more information"))
        }
    }

    func showFeeDetails() {
        topWViewController()?.showFeeDetails(nativeToken: nativeToken, fee: feeDetails)
    }
}
