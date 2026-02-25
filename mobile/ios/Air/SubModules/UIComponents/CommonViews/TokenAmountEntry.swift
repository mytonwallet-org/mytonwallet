//
//  BaseCurrencyValueText.swift
//  MyTonWalletAir
//
//  Created by nikstar on 22.11.2024.
//

import SwiftUI
import WalletCore
import WalletContext

public struct TokenAmountEntrySection: View {
    
    @Binding public var amount: BigInt?
    public var token: ApiToken
    public var balance: BigInt?
    public var showMaxAmount: Bool
    public var insufficientFunds: Bool
    @Binding public var amountInBaseCurrency: BigInt?
    @Binding public var switchedToBaseCurrencyInput: Bool
    public var allowSwitchingToBaseCurrency: Bool
    public var fee: MFee?
    public var explainedFee: ExplainedTransferFee?
    @Binding public var isFocused: Bool
    public var onTokenSelect: (() -> ())?
    public var onUseAll: () -> ()
    
    public init(
        amount: Binding<BigInt?>,
        token: ApiToken,
        balance: BigInt?,
        showMaxAmount: Bool = true,
        insufficientFunds: Bool,
        amountInBaseCurrency: Binding<BigInt?>,
        switchedToBaseCurrencyInput: Binding<Bool>,
        allowSwitchingToBaseCurrency: Bool = true,
        fee: MFee?,
        explainedFee: ExplainedTransferFee?,
        isFocused: Binding<Bool>,
        onTokenSelect: (() -> Void)?,
        onUseAll: @escaping () -> Void
    ) {
        self._amount = amount
        self.token = token
        self.balance = balance
        self.showMaxAmount = showMaxAmount
        self.insufficientFunds = insufficientFunds
        self._amountInBaseCurrency = amountInBaseCurrency
        self._switchedToBaseCurrencyInput = switchedToBaseCurrencyInput
        self.allowSwitchingToBaseCurrency = allowSwitchingToBaseCurrency
        self.fee = fee
        self.explainedFee = explainedFee
        self._isFocused = isFocused
        self.onTokenSelect = onTokenSelect
        self.onUseAll = onUseAll
    }
    
    public var body: some View {
        InsetSection {
            InsetCell {
                TokenAmountEntry(
                    amount: switchedToBaseCurrencyInput ? $amountInBaseCurrency : $amount,
                    token: token,
                    inBaseCurrency: switchedToBaseCurrencyInput,
                    insufficientFunds: insufficientFunds,
                    triggerFocused: $isFocused,
                    onTokenPickerTapped: onTokenSelect.flatMap { onTokenSelect in
                        return {
                            isFocused = false
                            onTokenSelect()
                        }
                    }
                )
            }
            .contentShape(.rect)
            .onTapGesture {
                isFocused = true
            }
        } header: {
            HStack {
                Text(lang("Amount"))
                Spacer()
                let balance = balance ?? 0
                if showMaxAmount {
                    UseAllButton(
                        amount: DecimalAmount(balance, token),
                        onTap: {
                            isFocused = false
                            onUseAll()
                        })
                }
            }
        } footer: {
            HStack {
                switchToCurrency
                Spacer()
                feeView
            }
            .animation(.snappy, value: fee)
            .animation(.snappy, value: explainedFee)
        }
    }
    
    private var decimals: Int {
        if switchedToBaseCurrencyInput {
            TokenStore.baseCurrency.decimalsCount
        } else {
            token.decimals
        }
    }

    @ViewBuilder
    var switchToCurrency: some View {
        HStack(spacing: 1) {
            if switchedToBaseCurrencyInput {
                let amount = amount ?? 0
                Text(
                    amount: DecimalAmount(amount, token),
                    format: .init()
                )
                Image("SendInCurrency", bundle: AirBundle)
                
            } else {
                let amount = amountInBaseCurrency ?? 0
                let baseCurrency = TokenStore.baseCurrency
                Text(
                    amount: BaseCurrencyAmount(amount, baseCurrency),
                    format: .init(preset: .baseCurrencyEquivalent)
                )
                if allowSwitchingToBaseCurrency {
                    Image("SendInCurrency", bundle: AirBundle)
                }
            }
        }
        .padding(2)
        .contentShape(.rect)
        .onTapGesture {
            switchedToBaseCurrencyInput.toggle()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isFocused = true
            }
        }
        .allowsHitTesting(allowSwitchingToBaseCurrency)
        .padding(-2)
    }
    
    @ViewBuilder
    var feeView: some View {
        let chain = token.chain
        if chain.isSupported, let nativeToken = TokenStore.tokens[chain.nativeToken.slug] {
            FeeView(token: token, nativeToken: nativeToken, fee: fee, explainedTransferFee: explainedFee, includeLabel: true)
                .transition(.opacity)
        }
    }
}



public struct TokenAmountEntry: View {
    
    @Binding public var amount: BigInt?
    public var token: ApiToken?
    public var inBaseCurrency: Bool
    public var insufficientFunds: Bool
    @Binding public var triggerFocused: Bool
    public var onTokenPickerTapped: (() -> ())?
    
    public init(amount: Binding<BigInt?>, token: ApiToken?, inBaseCurrency: Bool, insufficientFunds: Bool, triggerFocused: Binding<Bool>, onTokenPickerTapped: (() -> ())?) {
        self._amount = amount
        self.token = token
        self.inBaseCurrency = inBaseCurrency
        self.insufficientFunds = insufficientFunds
        self._triggerFocused = triggerFocused
        self.onTokenPickerTapped = onTokenPickerTapped
    }

    private var decimals: Int? {
        if inBaseCurrency {
            TokenStore.baseCurrency.decimalsCount
        } else {
            token?.decimals
        }
    }
    
    public var body: some View {
        HStack(spacing: 0) {
            symbol
            textField
            tokenPicker
        }
    }

    @ViewBuilder
    var symbol: some View {
        if inBaseCurrency {
            let sign = TokenStore.baseCurrency.sign
            Text(verbatim: sign)
                .foregroundStyle(Color((amount ?? 0) == 0 ? UIColor.placeholderText : insufficientFunds ? WTheme.error : WTheme.primaryLabel))
                .font(.system(size: 24, weight: .medium))
        }
    }
    
    @ViewBuilder
    var textField: some View {
        if let decimals {
            WUIAmountInput(
                amount: $amount,
                maximumFractionDigits: decimals,
                font: .systemFont(ofSize: 24, weight: .semibold),
                fractionFont: .systemFont(ofSize: 20, weight: .semibold),
                isFocused: $triggerFocused,
                error: insufficientFunds
            )
            .id(inBaseCurrency)
        } else {
            Text(" ")
                .font(.system(size: 24, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    var tokenPicker: some View {
        TokenPickerButton(
            token: token,
            inBaseCurrency: inBaseCurrency,
            onTap: onTokenPickerTapped
        )
        .offset(x: 8)
        .padding(.vertical, -1)
    }
}
