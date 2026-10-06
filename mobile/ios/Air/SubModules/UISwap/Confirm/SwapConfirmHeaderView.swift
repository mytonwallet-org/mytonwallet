//
//  SwapTokenView.swift
//  UISwap
//
//  Created by Sina on 5/10/24.
//

import SwiftUI
import UIKit
import ProtectedAction
import UIComponents
import WalletCore
import WalletContext

struct SwapConfirmHeaderView: ConfirmationContent {

    var fromAmount: TokenAmount
    var toAmount: TokenAmount
    var batchNotice: String?

    var body: some View {
        VStack(spacing: 12) {
            SwapOverviewView(fromAmount: fromAmount, toAmount: toAmount)
            if let batchNotice {
                Text(batchNotice)
                    .textStyle(.footnoteEmphasized)
                    .foregroundStyle(Color.air.secondaryLabel)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.air.secondaryFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(.bottom, 12)
    }

    var compactRepresentation: some View {
        CompactActionSummary {
            WUIIconViewToken(
                token: fromAmount.token,
                isWalletView: false,
                showldShowChain: false,
                size: 20,
                chainSize: 0,
                chainBorderWidth: 0,
                chainHorizontalOffset: 0,
                chainVerticalOffset: 0
            )
        } label: {
            HStack(spacing: 4) {
                Text(fromAmount.formatted(.defaultAdaptive))
                    .textStyle(.bodyEmphasized, content: .technical)
                Image(systemName: "arrow.right")
                    .textStyle(.footnoteEmphasized, content: .technical)
                Text(toAmount.formatted(.defaultAdaptive))
                    .textStyle(.bodyEmphasized, content: .technical)
                WUIIconViewToken(
                    token: toAmount.token,
                    isWalletView: false,
                    showldShowChain: false,
                    size: 20,
                    chainSize: 0,
                    chainBorderWidth: 0,
                    chainHorizontalOffset: 0,
                    chainVerticalOffset: 0
                )
                .frame(width: 20, height: 20)
            }
        }
    }
}
