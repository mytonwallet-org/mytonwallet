//
//  RateLarge.swift
//  App
//
//  Created by nikstar on 28.09.2025.
//

import SwiftUI
import WalletCore
import WalletContext

struct RateLarge: View {
    
    var rate: BaseCurrencyAmount
    
    var body: some View {
        let text = Text(rate.formatted(.baseCurrencyPrice))
        ViewThatFits(in: .horizontal) {
            text
                .font(.compactRoundedSemibold(size: 30))
                .fixedSize()
            text
                .font(.compactRoundedSemibold(size: 28))
                .fixedSize()
            text
                .font(.compactRoundedSemibold(size: 26))
                .fixedSize()
            text
                .font(.compactRoundedSemibold(size: 24))
                .fixedSize()
        }
        .foregroundStyle(.white)
    }
}
