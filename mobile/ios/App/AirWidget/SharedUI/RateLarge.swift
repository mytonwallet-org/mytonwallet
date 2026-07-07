import SwiftUI
import WalletCoreTypes

struct RateLarge: View {
    var rate: BaseCurrencyAmount
    
    var body: some View {
        let text = Text(rate.formatted(.baseCurrencyPrice))
        ViewThatFits(in: .horizontal) {
            text
                .font(.compactRounded(size: 30, weight: .bold))
                .fixedSize()
            text
                .font(.compactRounded(size: 28, weight: .bold))
                .fixedSize()
            text
                .font(.compactRounded(size: 26, weight: .bold))
                .fixedSize()
            text
                .font(.compactRounded(size: 24, weight: .bold))
                .fixedSize()
        }
        .foregroundStyle(.white)
    }
}
