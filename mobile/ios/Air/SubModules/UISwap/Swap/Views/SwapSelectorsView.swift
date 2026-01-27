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
                tokenBalance: model.maxAmount,
                sellingFocused: $model.sellingFocused,
                buyingFocused: $model.buyingFocused,
                onUseAll: model.onUseAll,
                onReverse: model.onReverse,
                onSellingTokenPicker: model.onSellingTokenPicker,
                onBuyingTokenPicker: model.onBuyingTokenPicker
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
    
    @Binding var sellingFocused: Bool
    @Binding var buyingFocused: Bool

    var onUseAll: () -> ()
    var onReverse: () -> ()
    var onSellingTokenPicker: () -> ()
    var onBuyingTokenPicker: () -> ()
    
    private var insufficientFunds: Bool {
        if let sellingAmount, let tokenBalance {
            return sellingAmount > tokenBalance
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
                    .foregroundColor(Color(WTheme.secondaryLabel))
                Spacer()
                if let tokenBalance {
                    UseAllButton(amount: DecimalAmount(tokenBalance, sellingToken), onTap: onUseAll)
                }
            }
            .font(.footnote)
            TokenAmountEntry(
                amount: $sellingAmount,
                token: sellingToken,
                inBaseCurrency: false,
                insufficientFunds: insufficientFunds,
                triggerFocused: $sellingFocused,
                onTokenPickerTapped: onSellingTokenPicker
            )
            .padding(8) // increase touch target
            .contentShape(.rect)
            .onTapGesture {
                sellingFocused = true
            }
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
                    .fill(Color(WTheme.secondaryFill))
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
                .foregroundColor(Color(WTheme.secondaryLabel))
                .frame(maxWidth: .infinity, alignment: .leading)
            TokenAmountEntry(
                amount: $buyingAmount,
                token: buyingToken,
                inBaseCurrency: false,
                insufficientFunds: false,
                triggerFocused: $buyingFocused,
                onTokenPickerTapped: onBuyingTokenPicker
            )
            .padding(8)  // increase touch target
            .padding(.bottom, 10)
            .contentShape(.rect)
            .onTapGesture {
                buyingFocused = true
            }
            .padding(.bottom, -10)
            .padding(-8)
        }
        
    }
}
