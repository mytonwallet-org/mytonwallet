//
//  FeeView.swift
//
//  Created by nikstar on 22.11.2024.
//

import SwiftUI
import WalletCore
import WalletContext
import Dependencies


public struct FeeView: View {
    
    private let token: ApiToken
    private let nativeToken: ApiToken
    private let fee: MFee?
    private let explainedTransferFee: ExplainedTransferFee?
    private let includeLabel: Bool
    private let showDetailsButton: Bool
    private let isLoading: Bool
    private let isError: Bool
    private let textStyle: WTextStyle
    private let textScaling: WTextScaling
    
    @Dependency(\.tokenStore.baseCurrency) private var baseCurrency
    @State private var showInBaseCurrency = false
    
    private var shouldShowDetails: Bool {
        showDetailsButton && explainedTransferFee?.supportsLegacyDetailsView == true
    }
    
    public init(
        token: ApiToken,
        nativeToken: ApiToken,
        fee: MFee?,
        explainedTransferFee: ExplainedTransferFee?,
        includeLabel: Bool,
        showDetailsButton: Bool = true,
        isLoading: Bool = false,
        isError: Bool = false,
        textStyle: WTextStyle = .body,
        textScaling: WTextScaling = .dynamic
    ) {
        self.token = token
        self.nativeToken = nativeToken
        self.fee = fee
        self.explainedTransferFee = explainedTransferFee
        self.includeLabel = includeLabel
        self.showDetailsButton = showDetailsButton
        self.isLoading = isLoading
        self.isError = isError
        self.textStyle = textStyle
        self.textScaling = textScaling
    }
    
    public var body: some View {
        if isLoading {
            loadingContent
        } else if let fee = fee ?? explainedTransferFee?.realFee {
            if isError {
                feeContent(fee)
                    .foregroundStyle(Color.air.error)
            } else {
                feeContent(fee)
            }
        }
    }

    private var loadingContent: some View {
        HStack(alignment: .center, spacing: 4) {
            if includeLabel {
                Text(lang("$fee_value_with_colon", arg1: ""))
            }
            WUIActivityIndicator(size: 14)
                .foregroundStyle(Color.air.secondaryLabel)
                .frame(width: 14, height: 14)
        }
        .textStyle(textStyle, scaling: textScaling)
        .padding(2)
        .padding(-2)
    }
    
    @ViewBuilder
    private func feeContent(_ fee: MFee) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            feeValueView(fee)
            if shouldShowDetails {
                Button(action: showFeeDetails) {
                    Image(systemName: "questionmark.circle.fill")
                        .imageScale(.medium)
                        .foregroundStyle(Color(.air.secondaryLabel.withAlphaComponent(0.3)))
                }
                .buttonStyle(.plain)
            }
        }
        .textStyle(textStyle, scaling: textScaling)
        .padding(2)
        .padding(-2)
    }

    private func canToggleBaseCurrency(for fee: MFee) -> Bool {
        fee.isNativeOnly && (showInBaseCurrency || baseCurrencyAmount(for: fee) != nil)
    }

    private func toggleBaseCurrencyDisplay(for fee: MFee) {
        guard canToggleBaseCurrency(for: fee) else { return }
        withAnimation(.smooth()) {
            showInBaseCurrency.toggle()
        }
    }

    @ViewBuilder
    private func feeValueView(_ fee: MFee) -> some View {
        if canToggleBaseCurrency(for: fee) {
            feeValueText(fee)
                .id(showInBaseCurrency)
                .transition(.opacity)
                .contentShape(.rect)
                .onTapGesture {
                    toggleBaseCurrencyDisplay(for: fee)
                }
                .accessibilityRemoveTraits(.isStaticText)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction {
                    toggleBaseCurrencyDisplay(for: fee)
                }
        } else {
            feeValueText(fee)
        }
    }

    private func feeValueText(_ fee: MFee) -> Text {
        let value: Text
        if showInBaseCurrency, let bcAmount = baseCurrencyAmount(for: fee) {
            value = Text(amount: bcAmount, format: .init(preset: .baseCurrencyEquivalent, precision: fee.precision))
                .textStyle(
                    textStyle,
                    content: .technical,
                    scaling: textScaling
                )
        } else {
            value = Text(fee.toString(token: token, nativeToken: nativeToken))
                .textStyle(
                    textStyle,
                    content: .technical,
                    scaling: textScaling
                )
        }
        if includeLabel {
            let label = Text(lang("$fee_value_with_colon", arg1: ""))
                .textStyle(textStyle, scaling: textScaling)
            return Text("\(label)\(value)")
        } else {
            return value
        }
    }

    private func baseCurrencyAmount(for fee: MFee) -> BaseCurrencyAmount? {
        guard fee.isNativeOnly,
              let nativeAmount = fee.nativeSumOrTerms,
              nativeAmount > 0,
              let price = nativeToken.price,
              price > 0 else { return nil }
        let converted = convertAmount(
            nativeAmount,
            price: price,
            tokenDecimals: nativeToken.decimals,
            baseCurrencyDecimals: baseCurrency.decimalsCount
        )
        return BaseCurrencyAmount(converted, baseCurrency)
    }

    private func showFeeDetails() {
        if shouldShowDetails, let explainedTransferFee {
            if let vc = topWViewController() {
                vc.view.endEditing(true)
                vc.showTip(title: "Blockchain Fee Details", wide: true) {
                    FeeDetailsView(nativeToken: nativeToken, fee: explainedTransferFee)
                }
            }
        }
    }
}  
