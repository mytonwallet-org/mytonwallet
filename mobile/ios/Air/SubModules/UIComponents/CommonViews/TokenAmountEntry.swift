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
    public var isFeeError: Bool
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
        isFeeError: Bool = false,
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
        self.isFeeError = isFeeError
        self._amountInBaseCurrency = amountInBaseCurrency
        self._switchedToBaseCurrencyInput = switchedToBaseCurrencyInput
        self.allowSwitchingToBaseCurrency = allowSwitchingToBaseCurrency
        self.fee = fee
        self.explainedFee = explainedFee
        self._isFocused = isFocused
        self.onTokenSelect = onTokenSelect
        self.onUseAll = onUseAll
    }

    public init(
        amount: BigInt?,
        onAmountChange:
            @escaping @MainActor @Sendable (BigInt?) -> Void,
        token: ApiToken,
        balance: BigInt?,
        showMaxAmount: Bool = true,
        insufficientFunds: Bool,
        isFeeError: Bool = false,
        amountInBaseCurrency: BigInt?,
        onBaseCurrencyAmountChange:
            @escaping @MainActor @Sendable (BigInt?) -> Void,
        switchedToBaseCurrencyInput: Bool,
        onInputCurrencyChange:
            @escaping @MainActor @Sendable (Bool) -> Void,
        allowSwitchingToBaseCurrency: Bool = true,
        fee: MFee?,
        explainedFee: ExplainedTransferFee?,
        isFocused: Binding<Bool>,
        onTokenSelect: (() -> Void)?,
        onUseAll: @escaping () -> Void
    ) {
        self.init(
            amount: Binding(
                get: { amount },
                set: { amount in
                    MainActor.assumeIsolated {
                        onAmountChange(amount)
                    }
                }
            ),
            token: token,
            balance: balance,
            showMaxAmount: showMaxAmount,
            insufficientFunds: insufficientFunds,
            isFeeError: isFeeError,
            amountInBaseCurrency: Binding(
                get: { amountInBaseCurrency },
                set: { amount in
                    MainActor.assumeIsolated {
                        onBaseCurrencyAmountChange(amount)
                    }
                }
            ),
            switchedToBaseCurrencyInput: Binding(
                get: { switchedToBaseCurrencyInput },
                set: { switched in
                    MainActor.assumeIsolated {
                        onInputCurrencyChange(switched)
                    }
                }
            ),
            allowSwitchingToBaseCurrency:
                allowSwitchingToBaseCurrency,
            fee: fee,
            explainedFee: explainedFee,
            isFocused: isFocused,
            onTokenSelect: onTokenSelect,
            onUseAll: onUseAll
        )
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
                    .layoutPriority(1)
                Spacer()
                feeView
                    .layoutPriority(1)
            }
            .animation(.snappy, value: fee)
            .animation(.snappy, value: explainedFee)
        }
    }
    
    @ViewBuilder
    var switchToCurrency: some View {
        ZStack(alignment: .leading) {
            HStack(spacing: 1) {
                Text(
                    amount: DecimalAmount(amount ?? 0, token),
                    format: .init()
                )
                Image("SendInCurrency", bundle: AirBundle)
            }
            .opacity(switchedToBaseCurrencyInput ? 1 : 0)
            
            HStack(spacing: 1) {
                Text(
                    amount: BaseCurrencyAmount(amountInBaseCurrency ?? 0, TokenStore.baseCurrency),
                    format: .init(preset: .baseCurrencyEquivalent)
                )
                if allowSwitchingToBaseCurrency {
                    Image("SendInCurrency", bundle: AirBundle)
                }
            }
            .opacity(switchedToBaseCurrencyInput ? 0 : 1)
        }
        .animation(.smooth(), value: switchedToBaseCurrencyInput)
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
            FeeView(
                token: token,
                nativeToken: nativeToken,
                fee: fee,
                explainedTransferFee: explainedFee,
                includeLabel: true,
                isError: isFeeError,
                textStyle: .footnote
            )
                .transition(.opacity)
        }
    }
}



public struct TokenAmountEntry: View {
    
    @Binding public var amount: BigInt?
    public var token: ApiToken?
    public var inBaseCurrency: Bool
    public var insufficientFunds: Bool
    public var isValueStale: Bool
    @Binding public var triggerFocused: Bool
    public var onTokenPickerTapped: (() -> ())?
    public var isInputEnabled: Bool
    public var onInputTapped: (() -> ())?
    public var onAmountChanged: ((BigInt?) -> ())?
    
    public init(
        amount: Binding<BigInt?>,
        token: ApiToken?,
        inBaseCurrency: Bool,
        insufficientFunds: Bool,
        isValueStale: Bool = false,
        triggerFocused: Binding<Bool>,
        onTokenPickerTapped: (() -> ())?,
        isInputEnabled: Bool = true,
        onInputTapped: (() -> ())? = nil,
        onAmountChanged: ((BigInt?) -> ())? = nil
    ) {
        self._amount = amount
        self.token = token
        self.inBaseCurrency = inBaseCurrency
        self.insufficientFunds = insufficientFunds
        self.isValueStale = isValueStale
        self._triggerFocused = triggerFocused
        self.onTokenPickerTapped = onTokenPickerTapped
        self.isInputEnabled = isInputEnabled
        self.onInputTapped = onInputTapped
        self.onAmountChanged = onAmountChanged
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
            HStack(spacing: 0) {
                symbol
                textField
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(isValueStale ? 0.55 : 1)
            .contentShape(.rect)
            .onTapGesture {
                if let onInputTapped {
                    onInputTapped()
                } else if isInputEnabled {
                    triggerFocused = true
                }
            }
            tokenPicker
        }
        .onChange(of: isInputEnabled) { isEnabled in
            if !isEnabled {
                triggerFocused = false
            }
        }
    }

    @ViewBuilder
    var symbol: some View {
        if inBaseCurrency {
            let sign = TokenStore.baseCurrency.sign
            Text(verbatim: sign)
                .foregroundStyle(Color((amount ?? 0) == 0 ? UIColor.placeholderText : insufficientFunds ? .air.error : isValueStale ? .air.secondaryLabel : UIColor.label))
                .textStyle(.amountSymbol, content: .technical)
        }
    }
    
    @ViewBuilder
    var textField: some View {
        if let decimals {
            WUIAmountInput(
                amount: $amount,
                maximumFractionDigits: decimals,
                font: WTypography.uiFont(.amount, content: .technical),
                fractionFont: WTypography.uiFont(.amountSecondary, content: .technical),
                isFocused: $triggerFocused,
                error: insufficientFunds,
                muted: isValueStale,
                onUserChange: onAmountChanged
            )
            .id(inBaseCurrency)
            .allowsHitTesting(isInputEnabled)
        } else {
            Text(" ")
                .textStyle(.amount, content: .technical)
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
