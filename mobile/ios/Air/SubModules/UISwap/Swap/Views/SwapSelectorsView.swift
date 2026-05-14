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
    var sellingToken: ApiToken
    
    @Binding var buyingAmount: BigInt?
    var buyingToken: ApiToken
    
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
                .padding(.vertical, 11)
                .padding(.top, 3)
                .padding(.horizontal, 16)
            divider
            
            buyingRow
                .padding(.vertical, 11)
                .padding(.top, 3)
                .padding(.horizontal, 16)
            
        } header: {} footer: {}
            .padding(.horizontal, -16)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                    sellingFocused = true
                }
            }
    }
    
    var sellingRow: some View {
        VStack(spacing: 11) {
            HStack {
                Text(lang("You sell"))
                    .foregroundColor(Color.air.secondaryLabel)
                Spacer()
                if let buttonAmount = availableSellingAmount {
                    UseAllButton(amount: DecimalAmount(buttonAmount, sellingToken), onTap: onUseAll)
                }
            }
            .font(.footnote)
            TokenAmountEntry(
                amount: $sellingAmount,
                token: sellingToken,
                inBaseCurrency: false,
                insufficientFunds: insufficientFunds,
                isValueStale: staleAmountSide == .selling,
                triggerFocused: $sellingFocused,
                onTokenPickerTapped: onSellingTokenPicker,
                onInputTapped: {
                    sellingFocused = true
                },
                onAmountChanged: onSellingAmountChanged
            )
            .padding(8) // increase touch target
            .padding(-8)
        }
    }
    
    var divider: some View {
        InsetDivider()
            .padding(.leading, -16)
            .overlay {
                reverseButton
                    .offset(y: 2)
            }
    }
    
    var reverseButton: some View {
        Button(action: onReverse) {
            ZStack {
                Circle()
                    .fill(Color.air.secondaryFill)
                    .frame(width: 32, height: 32)
                Image("ReverserIcon", bundle: AirBundle)
            }
            .padding(4)
            .contentShape(.circle)
        }
        .padding(-4)
    }
    
    var buyingRow: some View {
        VStack(spacing: 11) {
            Text(lang("You buy"))
                .font(.footnote)
                .foregroundColor(Color.air.secondaryLabel)
                .frame(maxWidth: .infinity, alignment: .leading)
            TokenAmountEntry(
                amount: $buyingAmount,
                token: buyingToken,
                inBaseCurrency: false,
                insufficientFunds: false,
                isValueStale: staleAmountSide == .buying,
                triggerFocused: $buyingFocused,
                onTokenPickerTapped: onBuyingTokenPicker,
                isInputEnabled: !buyingAmountInputDisabled,
                onInputTapped: {
                    if buyingAmountInputDisabled {
                        onBuyingAmountDisabledTap()
                    } else {
                        buyingFocused = true
                    }
                },
                onAmountChanged: onBuyingAmountChanged
            )
            .padding(8)  // increase touch target
            .padding(.bottom, 10)
            .padding(.bottom, -10)
            .padding(-8)
        }
        
    }
}
