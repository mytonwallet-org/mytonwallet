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
    
    var fromAmount: TokenAmount
    var toAmount: TokenAmount
    
    var body: some View {
        SwapOverviewView(fromAmount: fromAmount, toAmount: toAmount)
            .padding(.bottom, 12)
    }
}
