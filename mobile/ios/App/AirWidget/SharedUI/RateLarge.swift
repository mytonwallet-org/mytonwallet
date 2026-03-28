import SwiftUI

struct RateLarge: View {
    var rate: BaseCurrencyAmount
    
    var body: some View {
        let text = Text(rate.formatted(.baseCurrencyPrice))
        ViewThatFits(in: .horizontal) {
            text
                .font(.compactRounded(size: 30, weight: .semibold))
                .fixedSize()
            text
                .font(.compactRounded(size: 28, weight: .semibold))
                .fixedSize()
            text
                .font(.compactRounded(size: 26, weight: .semibold))
                .fixedSize()
            text
                .font(.compactRounded(size: 24, weight: .semibold))
                .fixedSize()
        }
        .foregroundStyle(.white)
    }
}
