
import Foundation
import ProtectedAction
import SwiftUI
import UIKit
import UIComponents
import WalletCore
import WalletContext

struct StakingConfirmHeaderView: ConfirmationContent {
    
    enum Mode {
        case stake
        case unstake
        case claim
    }
    
    var mode: Mode
    var tokenAmount: TokenAmount
    
    var body: some View {
        VStack(spacing: 0) {
            iconView
                .padding(.bottom, 16)
            amountView
                .padding(.bottom, 12)
            toView
        }
        .padding(.bottom, 12)
    }

    var compactRepresentation: some View {
        CompactActionSummary {
            WUIIconViewToken(
                token: tokenAmount.token,
                isWalletView: false,
                showldShowChain: false,
                size: 20,
                chainSize: 0,
                chainBorderWidth: 0,
                chainHorizontalOffset: 0,
                chainVerticalOffset: 0
            )
        } label: {
            Text(compactAction + " ")
                .textStyle(.body)
                + Text(tokenAmount.formatted(.defaultAdaptive))
                .textStyle(.bodyEmphasized, content: .technical)
        }
    }

    private var compactAction: String {
        switch mode {
        case .stake:
            lang("Stake")
        case .unstake:
            lang("Unstake")
        case .claim:
            lang("Claim")
        }
    }
    
    @ViewBuilder
    var iconView: some View {
        WUIIconViewToken(
            token: tokenAmount.token,
            isWalletView: false,
            showldShowChain: true,
            size: 60,
            chainSize: 24,
            chainBorderWidth: 1.5,
            chainHorizontalOffset: 6,
            chainVerticalOffset: 2
        )
            .frame(width: 60, height: 60)
    }
    
    @ViewBuilder
    var amountView: some View {
        let showPlus = mode == .claim || mode == .unstake
        let isLargeAmount = abs(tokenAmount.doubleValue) >= 10
        AmountText(
            amount: tokenAmount,
            format: .init(preset: .defaultAdaptive, showPlus: showPlus, showMinus: false),
            integerFont: .compactRounded(ofSize: 34, weight: .bold),
            fractionFont: .compactRounded(ofSize: 28, weight: .bold),
            symbolFont: .compactRounded(ofSize: 28, weight: .bold),
            integerColor: UIColor.label,
            fractionColor: isLargeAmount ? .air.secondaryLabel : UIColor.label,
            symbolColor: .air.secondaryLabel
        )
    }
    
    @ViewBuilder
    var toView: some View {
        let hint = switch mode {
        case .stake:
            lang("Moving to staking balance")
        case .unstake:
            lang("Request for unstaking")
        case .claim:
            lang("Accumulated Rewards")
        }
        Text(hint)
            .textStyle(.body, scaling: .dynamic)
    }
}
