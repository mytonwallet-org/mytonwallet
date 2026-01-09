
import Foundation
import SwiftUI
import UIComponents
import WalletCore
import WalletContext
import Perception

struct UnstakeView: View {
    
    var model: UnstakeModel
    var navigationBarInset: CGFloat
    var onScrollPositionChange: (CGFloat) -> ()
    
    @Namespace private var ns
    
    var body: some View {
        WithPerceptionTracking {
            @Perception.Bindable var model = model
            InsetList {
                AmountSection(model: model)
                    .background {
                        GeometryReader { geom in
                            Color.clear.onChange(of: geom.frame(in: .named(ns)).origin.y) { y in
                                onScrollPositionChange(y + 2)
                            }
                        }
                    }

                UnstakeInfoSection(model: model)
                    .padding(.top, -8)
            }
            .padding(.top, -8)
            .coordinateSpace(name: ns)
            .navigationBarInset(navigationBarInset)
            .contentShape(.rect)
            .onTapGesture {
                model.onBackgroundTapped()
            }
            .onChange(of: model.amount) { amount in
                if let amount, model.switchedToBaseCurrencyInput == false {
                    model.updateBaseCurrencyAmount(amount)
                }
            }
            .onChange(of: model.amountInBaseCurrency) { baseCurrencyAmount in
                if let baseCurrencyAmount, model.switchedToBaseCurrencyInput == true {
                    model.updateAmountFromBaseCurrency(baseCurrencyAmount)
                }
            }
            .task(id: model.amount) {
                await model.updateFee()
            }
        }
    }
}


fileprivate struct AmountSection: View {
    
    var model: UnstakeModel
    
    var body: some View {
        WithPerceptionTracking {
            @Perception.Bindable var model = model   
            TokenAmountEntrySection(
                amount: $model.amount,
                token: displayToken,
                balance: model.maxAmount,
                insufficientFunds: model.insufficientFunds,
                amountInBaseCurrency: $model.amountInBaseCurrency,
                switchedToBaseCurrencyInput: $model.switchedToBaseCurrencyInput,
                fee: model.fee,
                explainedFee: nil,
                isFocused: $model.isAmountFieldFocused,
                onTokenSelect: nil,
                onUseAll: { model.onUseAll() }
            )
        }
    }
    
    /// even when withdrawing "staked", show normal token
    var displayToken: ApiToken {
        if model.stakedTokenSlug == STAKED_TON_SLUG ||
            model.stakedTokenSlug == STAKED_MYCOIN_SLUG ||
            model.stakedTokenSlug == TON_TSUSDE_SLUG {
            model.baseToken
        } else {
            model.stakedToken
        }
    }
}


fileprivate struct UnstakeInfoSection: View {
    
    var model: UnstakeModel
    
    var body: some View {
        WithPerceptionTracking {
            InsetSection {
                InsetCell {
                    HStack {
                        Text(lang("Receiving"))
                            .font17h22()
                            .foregroundStyle(Color(WTheme.secondaryLabel))
                        Spacer()
                        receivingBadge
                    }
                }
                if case .liquid(let liquid) = model.stakingState {
                    let amnt = TokenAmount(liquid.instantAvailable, TokenStore.tokens[TONCOIN_SLUG]!)
                    InsetCell {
                        HStack {
                            Text(lang("Instant Withdrawal"))
                                .font17h22()
                                .foregroundStyle(Color(WTheme.secondaryLabel))
                            Spacer()
                            Text(lang("up to %1$@", arg1: amnt.formatted(.none, maxDecimals: 0)))
                        }
                        .padding(.top, -1)
                    }
                }
            } header: {
                Text(lang("Details"))
            } footer: {}
        }
    }
    
    
    @ViewBuilder
    var receivingBadge: some View {
        switch model.withdrawalType {
        case .loading:
            ProgressView().progressViewStyle(.circular)
        case .instant:
            HStack(spacing: 4) {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(gradient)
                    .imageScale(.small)
                Text(lang("Instantly"))
            }
        case .timed(let remaining):
            HStack(spacing: 4) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color(WTheme.secondaryLabel))
                    .imageScale(.small)
                Text(formatTimeToWait(remaining))
            }

        }
    }
    
    var gradient: LinearGradient {
        LinearGradient(colors: [
            Color("EarnGradientColorLeft", bundle: AirBundle),
            Color("EarnGradientColorRight", bundle: AirBundle),
        ], startPoint: .top, endPoint: .bottom)
    }

    func formatTimeToWait(_ remaining: TimeInterval) -> String {
        return Duration.seconds(remaining).formatted(.units(
            allowed: [.days, .hours, .minutes],
            width: .wide,
            maximumUnitCount: 2,
            fractionalPart: .hide
        ).locale(LocalizationSupport.shared.locale))
    }
 }
