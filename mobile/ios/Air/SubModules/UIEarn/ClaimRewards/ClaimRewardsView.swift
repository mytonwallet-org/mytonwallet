
import SwiftUI
import UIComponents
import WalletCore
import WalletContext
import Perception

struct ClaimRewardsView: View {
    
    var viewModel: ClaimRewardsModel
    
    var body: some View {
        WithPerceptionTracking {
            @Perception.Bindable var viewModel = viewModel
            HStack {
                if viewModel.isConfirming {
                    ClaimRewardsConfirmContent(viewModel: viewModel)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(
                            .asymmetric(
                                insertion: .opacity
                                    .combined(with: .offset(y: 70))
                                    .combined(with: .scale(scale: 0.95))
                                    .animation(.spring(duration: 0.25).delay(0.1)),
                                removal: .opacity
                                    .combined(with: .offset(y: 70))
                                    .combined(with: .scale(scale: 0.95))
                                    .animation(.smooth(duration: 0.2))
                            )
                        )
                } else {
                    ClaimRewardsButtonContent(viewModel: viewModel)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(
                            .asymmetric(
                                insertion: .opacity
                                    .combined(with: .offset(y: -20))
                                    .combined(with: .scale(scale: 0.95))
                                    .animation(.spring(duration: 0.2).delay(0.1)),
                                removal: .opacity
                                    .combined(with: .offset(y: -20))
                                    .combined(with: .scale(scale: 0.95))
                                    .animation(.smooth(duration: 0.2))
                                )
                        )
                }
            }
            .background {
                Rectangle().fill(.background)
            }
            .clipShape(.rect(cornerRadius: 30))
            .contentShape(.rect(cornerRadius: 30))
            .shadow(color: .black.opacity(0.2), radius: 16, x: 0, y: 4)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background {
                whiteGradient
                    .allowsHitTesting(false)
            }
            .frame(height: 300, alignment: .bottom)
            .frame(height: 100, alignment: .bottom)
        }
    }
    
    var whiteGradient: some View {
        Rectangle().fill(
            LinearGradient(colors: [
                .clear,
                Color(WTheme.background).opacity(0.65),
                Color(WTheme.background).opacity(0.95),
            ], startPoint: .top, endPoint: .bottom)
        )
        .padding(.top, -30)
        .ignoresSafeArea(.all)
    }
}

struct ClaimRewardsButtonContent: View {
    var viewModel: ClaimRewardsModel
    private var accountContext: AccountContext { viewModel.accountContext }
    
    var body: some View {
        WithPerceptionTracking {
            HStack(spacing: 10) {
                icon
                labels
                if accountContext.account.supportsEarn {
                    claimButton
                        .padding(.trailing, 5)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .frame(height: 60)
        }
    }
    
    var icon: some View {
        ZStack {
            LinearGradient(
                colors: WColors.greenGradient.map(Color.init),
                startPoint: .top,
                endPoint: .bottom
            )
            Image.airBundle("ActionReceive")
                .resizable()
        }
        .frame(width: 40, height: 40)
        .clipShape(.circle)
    }
    
    var labels: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(lang("Accumulated Rewards"))
                .fontWeight(.medium)
            Text(amount: viewModel.amount, format: .init())
                .contentTransition(.numericText())
                .foregroundStyle(earnGradient)
                .animation(.default, value: viewModel.amount)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    var claimButton: some View {
        Button(lang("Claim")) {
            withAnimation(.spring(duration: 0.35)) {
                viewModel.isConfirming = true
            }
        }
        .buttonStyle(OpenButtonStyle())
    }
}

struct ClaimRewardsConfirmContent: View {
    var viewModel: ClaimRewardsModel
    private var accountContext: AccountContext { viewModel.accountContext }
    
    var body: some View {
        WithPerceptionTracking {
            VStack {
                Text(lang("Claim Rewards"))
                    .fontWeight(.semibold)
                    .padding(.vertical, 12)
                    .padding(.bottom, 6)
                amountSection
                HStack {
                    Button(lang("Cancel")) {
                        withAnimation(.spring(duration: 0.25)) {
                            viewModel.isConfirming = false
                        }
                    }
                    .buttonStyle(WUIButtonStyle(style: .secondary))
                    Button(lang("Confirm")) {
                        viewModel.onClaim()
                    }
                    .buttonStyle(WUIButtonStyle(style: .primary))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .padding(.vertical, 10)
        }
    }
    
    var amountSection: some View {
        InsetSection(backgroundColor: WTheme.sheetBackground) {
            AmountCell(amount: viewModel.amount.amount, token: viewModel.amount.token, format: .init(showPlus: true))
                .contentTransition(.numericText())
                .animation(.default, value: viewModel.amount)
                .backportGeometryGroup()
        } header: {
            EmptyView()
        } footer: {
            HStack(alignment: .firstTextBaseline) {
                let currency = TokenStore.baseCurrency
                let rate = viewModel.amount.token.price ?? 1
                let balance = accountContext.balances[TONCOIN_SLUG] ?? 0
                let fees = getFee(.claimJettons)
                let isEnoughNative = balance >= fees.gas ?? 0
                let convAmount = viewModel.amount.convertTo(currency, exchangeRate: rate)
                if convAmount.doubleValue > 0.01 {
                    Text(
                        amount: convAmount,
                        format: .init()
                    )
                }
                Spacer()
                FeeView(
                    token: viewModel.amount.token,
                    nativeToken: .TONCOIN,
                    fee: MFee(
                        precision: isEnoughNative ? .approximate : .lessThan,
                        terms: MFee.FeeTerms(
                            token: nil,
                            native: isEnoughNative ? fees.real : fees.gas,
                            stars: nil
                        ),
                        nativeSum: nil
                    ),
                    explainedTransferFee: nil,
                    includeLabel: true
                )
            }
        }
    }
}

#if DEBUG
@available(iOS 18, *)
#Preview {
    @Previewable @State var viewModel = ClaimRewardsModel(accountContext: AccountContext(source: .current))
    let _ = (viewModel.amount = TokenAmount(132_000_001, .MYCOIN))
    ClaimRewardsView(viewModel: viewModel)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .background {
            Color.blue.opacity(0.9).ignoresSafeArea()
        }
}
#endif
