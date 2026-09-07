import SwiftUI
import UIKit
import UIComponents
import WalletCore
import WalletContext
import Perception

struct SwapSelectorsView: View {
    
    var model: SwapInputModel
    
    var body: some View {
        WithPerceptionTracking {
            @Perception.Bindable var model = model
            _SwapSelectorsView(
                sellingAmount: $model.sellingAmount,
                sellingToken: model.sellingToken,
                buyingAmount: $model.buyingAmount,
                buyingToken: model.buyingToken,
                tokenBalance: model.tokenBalance,
                maxAmount: model.maxAmount,
                staleAmountSide: model.staleAmountSide,
                sellingFocused: $model.sellingFocused,
                buyingFocused: $model.buyingFocused,
                buyingAmountInputDisabled: model.buyingAmountInputDisabled,
                onUseAll: model.userTappedUseAll,
                onReverse: model.userTappedReverse,
                onSellingTokenPicker: { model.userTappedTokenPicker(side: .selling) },
                onBuyingTokenPicker: { model.userTappedTokenPicker(side: .buying) },
                onBuyingAmountDisabledTap: model.userTappedBuyingAmountDisabled,
                onSellingAmountChanged: { model.userEditedAmount($0, side: .selling) },
                onBuyingAmountChanged: { model.userEditedAmount($0, side: .buying) }
            )
        }
    }
}

fileprivate struct _SwapSelectorsView: View {
    
    @Binding var sellingAmount: BigInt?
    var sellingToken: ApiToken?
    
    @Binding var buyingAmount: BigInt?
    var buyingToken: ApiToken?
    
    var tokenBalance: BigInt?
    var maxAmount: BigInt?
    var staleAmountSide: SwapSide?
    
    @Binding var sellingFocused: Bool
    @Binding var buyingFocused: Bool
    var buyingAmountInputDisabled: Bool

    var onUseAll: () -> ()
    var onReverse: () -> ()
    var onSellingTokenPicker: () -> ()
    var onBuyingTokenPicker: () -> ()
    var onBuyingAmountDisabledTap: () -> ()
    var onSellingAmountChanged: (BigInt?) -> ()
    var onBuyingAmountChanged: (BigInt?) -> ()
    
    private var availableSellingAmount: BigInt? {
        maxAmount ?? tokenBalance
    }

    private var insufficientFunds: Bool {
        if let sellingAmount, let availableSellingAmount {
            return sellingAmount > availableSellingAmount
        }
        return false
    }
    
    var body: some View {
        InsetSection(addDividers: false) {
            sellingRow
                .padding(.top, IOS_26_MODE_ENABLED ? 16 : 14)
                .padding(.bottom, IOS_26_MODE_ENABLED ? 17 : 11)
                .padding(.horizontal, 16)
            divider
                .frame(height: IOS_26_MODE_ENABLED ? 0 : nil, alignment: .bottom)
            
            buyingRow
                .padding(.top, IOS_26_MODE_ENABLED ? 16 : 14)
                .padding(.bottom, IOS_26_MODE_ENABLED ? 17 : 11)
                .padding(.horizontal, 16)
            
        } header: {} footer: {}
            .padding(.horizontal, -16)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                    sellingFocused = sellingToken != nil
                }
            }
    }
    
    var sellingRow: some View {
        VStack(spacing: IOS_26_MODE_ENABLED ? 9 : 11) {
            HStack {
                Text(lang("You Sell"))
                    .foregroundColor(Color.air.secondaryLabel)
                Spacer()
                if let buttonAmount = availableSellingAmount, let sellingToken {
                    UseAllButton(
                        amount: DecimalAmount(buttonAmount, sellingToken),
                        textStyle: IOS_26_MODE_ENABLED ? .supporting : .footnote,
                        textScaling: .dynamic,
                        onTap: onUseAll
                    )
                }
            }
            .textStyle(IOS_26_MODE_ENABLED ? .bodyStrong : .footnote, scaling: .dynamic)
            .frame(minHeight: IOS_26_MODE_ENABLED ? 22 : nil)
            TokenAmountEntry(
                amount: $sellingAmount,
                token: sellingToken,
                inBaseCurrency: false,
                insufficientFunds: insufficientFunds,
                isValueStale: staleAmountSide == .selling,
                style: IOS_26_MODE_ENABLED ? .large : .regular,
                triggerFocused: $sellingFocused,
                onTokenPickerTapped: onSellingTokenPicker,
                onInputTapped: {
                    sellingFocused = sellingToken != nil
                },
                onAmountChanged: onSellingAmountChanged
            )
            .frame(minHeight: IOS_26_MODE_ENABLED ? 42 : nil)
            .padding(8) // increase touch target
            .padding(-8)
        }
    }
    
    var divider: some View {
        Rectangle()
            .fill(Color.air.separator)
            .frame(height: 0.33)
            .padding(.horizontal, IOS_26_MODE_ENABLED ? 16 : 0)
            .overlay {
                reverseButton
                    .offset(y: IOS_26_MODE_ENABLED ? 0 : 2)
            }
    }
    
    var reverseButton: some View {
        Button(action: onReverse) {
            ZStack {
                Circle()
                    .fill(Color.air.secondaryFill)
                    .frame(width: IOS_26_MODE_ENABLED ? 40 : 32, height: IOS_26_MODE_ENABLED ? 40 : 32)
                Image("ReverserIcon", bundle: AirBundle)
                    .renderingMode(.template)
                    .frame(width: 24, height: 24)
            }
            .padding(4)
            .contentShape(.circle)
        }
        .padding(-4)
    }
    
    var buyingRow: some View {
        VStack(spacing: IOS_26_MODE_ENABLED ? 9 : 11) {
            Text(lang("You Buy"))
                .textStyle(IOS_26_MODE_ENABLED ? .bodyStrong : .footnote, scaling: .dynamic)
                .foregroundColor(Color.air.secondaryLabel)
                .frame(maxWidth: .infinity, minHeight: IOS_26_MODE_ENABLED ? 22 : nil, alignment: .leading)
            TokenAmountEntry(
                amount: $buyingAmount,
                token: buyingToken,
                inBaseCurrency: false,
                insufficientFunds: false,
                isValueStale: staleAmountSide == .buying,
                style: IOS_26_MODE_ENABLED ? .large : .regular,
                triggerFocused: $buyingFocused,
                onTokenPickerTapped: onBuyingTokenPicker,
                isInputEnabled: !buyingAmountInputDisabled,
                onInputTapped: {
                    if buyingAmountInputDisabled {
                        onBuyingAmountDisabledTap()
                    } else {
                        buyingFocused = buyingToken != nil
                    }
                },
                onAmountChanged: onBuyingAmountChanged
            )
            .frame(minHeight: IOS_26_MODE_ENABLED ? 42 : nil)
            .padding(8)  // increase touch target
            .padding(.bottom, 10)
            .padding(.bottom, -10)
            .padding(-8)
        }
        
    }
}
