
import Foundation
import SwiftUI
import UIKit
import UIComponents
import WalletCore
import WalletContext

struct StakingConfirmHeaderView: View {
    
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
    
    @ViewBuilder
    var iconView: some View {
        WUIIconViewToken(
            token: tokenAmount.token,
            isWalletView: false,
            showldShowChain: true,
            size: 60,
            chainSize: 24,
            chainBorderWidth: 1.5,
            chainBorderColor: WTheme.sheetBackground,
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
            integerColor: WTheme.primaryLabel,
            fractionColor: isLargeAmount ? WTheme.secondaryLabel : WTheme.primaryLabel,
            symbolColor: WTheme.secondaryLabel
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
    }
}
