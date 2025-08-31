//
//  SwapDetailsView.swift
//  UISwap
//
//  Created by Sina on 5/10/24.
//

import SwiftUI
import UIKit
import UIComponents
import WalletCore
import WalletContext
import Combine

public let DEFAULT_SLIPPAGE = BigInt(5_0)
public let MAX_SLIPPAGE_VALUE = BigInt(50_0)
public let SLIPPAGE_DECIMALS = 1
private let slippageFont = UIFont.systemFont(ofSize: 20, weight: .semibold)

@MainActor
class SwapDetailsVM: ObservableObject {
    
    @Published var isExpanded = false
    @Published var slippageExpanded = false
    @Published var slippage: BigInt? = DEFAULT_SLIPPAGE
    
    var onSlippageChanged: (Double) -> () = { _ in }
    var onPreferredDexChanged: (ApiSwapDexLabel?) -> () = { _ in }

    var fromToken: ApiToken { tokensSelectorVM.sellingToken }
    var toToken: ApiToken { tokensSelectorVM.buyingToken }
    var swapEstimate: Api.SwapEstimateResponse? { swapVM.swapEstimate }
    var selectedDex: ApiSwapDexLabel? { swapVM.dex }
    
    private var swapVM: SwapVM
    private var tokensSelectorVM: SwapSelectorsVM
    private var observer: AnyCancellable?
    
    init(swapVM: SwapVM, tokensSelectorVM: SwapSelectorsVM) {
        self.swapVM = swapVM
        self.tokensSelectorVM = tokensSelectorVM
        observer = $slippage.sink { [weak self] value in
            if let value {
                let doubleValue = value.doubleAbsRepresentation(decimals: SLIPPAGE_DECIMALS)
                self?.onSlippageChanged(doubleValue)
            }
        }
    }
    
    var displayEstimate: Api.SwapEstimateResponse? {
        swapEstimate?.displayEstimate(selectedDex: selectedDex)
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
}

extension Api.SwapEstimateResponse {
    func displayEstimate(selectedDex: ApiSwapDexLabel?) -> Api.SwapEstimateResponse {
        if let selectedDex, let other = other?.first(where: { $0.dexLabel == selectedDex }) {
            var est = self
            est.updateFromVariant(other)
            return est
        } else {
            return self
        }
    }
}


struct SwapDetailsView: View {

    @ObservedObject var swapVM: SwapVM
    @ObservedObject var selectorsVM: SwapSelectorsVM
    @ObservedObject var model: SwapDetailsVM
    var sellingToken: ApiToken { model.fromToken }
    var buyingToken: ApiToken { model.toToken }
    var exchangeRate: SwapRate? { model.displayExchangeRate }
    var swapEstimate: Api.SwapEstimateResponse? { model.swapEstimate }
    var displayEstimate: Api.SwapEstimateResponse? { model.displayEstimate }
    var hasAlternative: Bool { swapEstimate?.other?.nilIfEmpty != nil }
    
    @State private var slippageFocused: Bool = false
    
    private var slippageError: Bool {
        if let slippage = model.slippage, slippage > MAX_SLIPPAGE_VALUE { return true }
        return false
    }
    
    var body: some View {
        
        InsetSection(horizontalPadding: 0) {
            header
                
            if model.isExpanded {
                pricePerCoinRow
                slippageRow
                blockchainFeeRow
                routingFeesRow
                priceImpactRow
                minimumReceivedRow
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxHeight: model.isExpanded ? nil : 44, alignment: .top)
        .clipShape(.rect(cornerRadius: 12))
        .frame(height: 400, alignment: .top)
        .tint(Color(WTheme.tint))
        .animation(.spring(duration: model.isExpanded ? 0.45 : 0.3), value: model.isExpanded)
        .animation(.snappy, value: model.slippageExpanded)
    }
    
    var header: some View {
        Button(action: { model.isExpanded.toggle() }) {
            InsetCell {
                HStack {
                    Text(lang("Swap Details"))
                        .textCase(.uppercase)
                    Spacer()
                    Image.airBundle("RightArrowIcon")
                        .renderingMode(.template)
                        .rotationEffect(model.isExpanded ? .radians(-0.5 * .pi) : .radians(0.5 * .pi))
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
                        Text(lang("Price per") + " 1 " + exchangeRate.toToken.symbol)
                            .foregroundStyle(Color(WTheme.secondaryLabel))
                        Spacer(minLength: 4)
                        Text("~\(formatAmountText(amount: exchangeRate.price, decimalsCount: min(6, sellingToken.decimals))) \(exchangeRate.fromToken.symbol)")
                    }
                    selectDexButton
                }
            }
        }
    }
    
    @ViewBuilder
    private var selectDexButton: some View {
        if swapEstimate != nil {
            Button(action: showDexPicker) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    if model.selectedDex == nil && hasAlternative {
                        Text(lang("Best rate"))
                            .foregroundStyle(gradient)
                            .background {
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(secondaryGradient)
                                    .padding(.vertical, -2)
                                    .padding(.horizontal, -5)
                            }
                            .padding(.trailing, 2)
                    }
                    Text(lang(" via "))
                    Text(dexString)
                    if hasAlternative {
                        Text(Image(systemName: "chevron.right.circle.fill"))
                            .foregroundStyle(Color(WTheme.secondaryLabel.withAlphaComponent(0.3)))
                    }
                }
                .font13()
                .foregroundStyle(Color(WTheme.secondaryLabel))
                .contentShape(.rect)
            }
            .allowsHitTesting(hasAlternative)
        }
    }
    
    var gradient: LinearGradient {
        LinearGradient(colors: [
            Color("EarnGradientColorLeft", bundle: AirBundle),
            Color("EarnGradientColorRight", bundle: AirBundle),
        ], startPoint: .leading, endPoint: .trailing)
    }
    
    var secondaryGradient: LinearGradient {
        LinearGradient(colors: [
            Color("EarnGradientDisabledColorLeft", bundle: AirBundle),
            Color("EarnGradientDisabledColorRight", bundle: AirBundle),
        ], startPoint: .leading, endPoint: .trailing)
    }
    
    private var dexString: String {
        displayEstimate?.dexLabel.displayName ?? ""
    }
    
    func showDexPicker() {
        if let topVC = topViewController() {
            topVC.view.endEditing(true)
            let vc = UIHostingController(rootView: SwapAgregatorContainerView(model: model))
            vc.modalPresentationStyle = .overFullScreen
            vc.view.backgroundColor = .clear
            topVC.present(vc, animated: false)
        }
    }
    
    var slippageRow: some View {
        VStack(spacing: 0) {
            InsetDetailCell(alignment: .firstTextBaseline) {
                Text(lang("Slippage"))
                    .foregroundStyle(Color(WTheme.secondaryLabel))
                    .overlay(alignment: .trailingFirstTextBaseline) {
                        InfoButton(title: "Slippage", message: "This sets how much the price is allowed to change before your swap is processed.\n\nIf during the processing of your swap, the price changes more than this value, your order will be canceled.")
                    }
                
            } value: {
                if !model.slippageExpanded {
                    SlippagePickerButton(value: model.slippage ?? DEFAULT_SLIPPAGE) {
                        topViewController()?.view.endEditing(true)
                        model.slippageExpanded = true
                    }
                    .transition(.scale.combined(with: .opacity))
                } else {
                    Button(action: {
                        topViewController()?.view.endEditing(true)
                        model.slippageExpanded = false
                        let slippage = model.slippage
                        if let slippage, slippage <= BigInt(0) || slippage > MAX_SLIPPAGE_VALUE {
                            model.slippage = DEFAULT_SLIPPAGE
                        } else if slippage == nil {
                            model.slippage = DEFAULT_SLIPPAGE
                        }
                    }) {
                        Text(lang("Done"))
                            .fontWeight(.semibold)
                    }
                    .transition(.scale.combined(with: .opacity))
                }
            }
            if model.slippageExpanded {
                HStack(alignment: .firstTextBaseline) {
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        WUIAmountInput(amount: $model.slippage, maximumFractionDigits: SLIPPAGE_DECIMALS, font: slippageFont, fractionFont: slippageFont, alignment: .right, isFocused: $slippageFocused, error: slippageError)
                            .frame(width: 68)
                        Text("%")
                            .font(Font(slippageFont))
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
                    .font(.system(size: 13, weight: .medium))
                }
                .padding(.horizontal, 16)
                .padding(.top, 2)
                .padding(.bottom, 10)
            }
        }
    }
    
    func slippageChoice(value: BigInt) -> some View {
        
        Button(action: { model.slippage = value }) {
            Text("\(formatBigIntText(value, tokenDecimals: 1))%")
                .padding(4)
                .contentShape(.rect)
        }
        .padding(-4)
    }
    
    @ViewBuilder
    var blockchainFeeRow: some View {
        if let displayEstimate {
            InsetDetailCell {
                Text(lang("Blockchain Fee"))
                    .foregroundStyle(Color(WTheme.secondaryLabel))
            } value: {
                let fee = sellingToken.chain == "ton" ? displayEstimate.realNetworkFee : displayEstimate.networkFee
                Text("~\(formatAmountText(amount: fee.value, currency: "TON", decimalsCount: 6))")
            }
        }
    }
    
    @ViewBuilder
    var routingFeesRow: some View {
        if displayEstimate != nil {
            InsetDetailCell {
                Text(lang("Routing Fees"))
                    .foregroundStyle(Color(WTheme.secondaryLabel))
                    .overlay(alignment: .trailingFirstTextBaseline) {
                        InfoButton(title: lang("Routing Fees"), message: lang("Both decentralized exchange and app fees (~0.875%) are already included in the price you see and will not be charged additionally."))
                    }
            } value: {
                Text(lang("Included"))
            }
        }
    }
    
    @ViewBuilder
    var priceImpactRow: some View {
        if let displayEstimate {
            InsetDetailCell {
                Text(lang("Price Impact"))
                    .foregroundStyle(Color(WTheme.secondaryLabel))
                    .overlay(alignment: .trailingFirstTextBaseline) {
                        InfoButton(title: lang("Price Impact"), message: lang("This shows how much your trade might change the token price.\nBig trades can make the price go up or down more. Lower is usually better."))
                    }
            } value: {
                Text("\(formatAmountText(amount: displayEstimate.impact, decimalsCount: 2))%")
            }
        }
    }
    
    @ViewBuilder
    var minimumReceivedRow: some View {
        if let displayEstimate {
            InsetDetailCell {
                Text(lang("Minimum Received"))
                    .foregroundStyle(Color(WTheme.secondaryLabel))
                    .overlay(alignment: .trailingFirstTextBaseline) {
                        InfoButton(title: lang("Minimum Received"), message: lang("This is the least amount of new tokens you'll get from this swap, considering current market conditions, slippage tolerance, and potential price impact."))
                    }
            } value: {
                Text(formatAmountText(amount: displayEstimate.toMinAmount.value,
                                      currency: buyingToken.symbol,
                                      decimalsCount: tokenDecimals(for: displayEstimate.toMinAmount.value, tokenDecimals: buyingToken.decimals)))
            }
        }
    }
}


struct SlippagePickerButton: View {
    
    var value: BigInt
    var onTap: () -> ()
    
    public var body: some View {
        Button(action: onTap) {
            HStack(spacing: 2) {
                Text("\(formatBigIntText(value, tokenDecimals: 1))%")
                    .font(.system(size: 17, weight: .medium))
                
                Image("SendPickToken", bundle: AirBundle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .fixedSize()
            .padding(.leading, 18)
            .padding(.trailing, 14)
            .padding(.vertical, 8)
            .background(Color(WTheme.secondaryFill), in: .capsule)
        }
        .buttonStyle(.plain)
    }
}


struct InfoButton: View {
    
    var title: String
    var message: String
    
    var body: some View {
        Button(action: onTap) {
            Image.airBundle("InfoIcon")
                .renderingMode(.template)
                .foregroundStyle(Color(WTheme.secondaryLabel.withAlphaComponent(0.3)))
                .padding(4)
                .contentShape(.circle)
        }
        .padding(-4)
        .buttonStyle(.plain)
        .offset(x: 22, y: 1.333)
    }
    
    func onTap() {
        topWViewController()?.showTip(title: title) {
            Text(message)
        }
    }
}
