//
//  SwapTokenView.swift
//  UISwap
//
//  Created by Sina on 5/10/24.
//

import SwiftUI
import UIKit
import UIComponents
import WalletCore
import WalletContext

struct SwapConfirmHeaderView: View {
    
    var fromAmount: BigInt
    var fromToken: ApiToken
    var toAmount: BigInt
    var toToken: ApiToken
    
    var body: some View {
        SwapOverviewView(fromAmount: fromAmount, fromToken: fromToken, toAmount: toAmount, toToken: toToken)
            .padding(.bottom, 12)
    }
}
