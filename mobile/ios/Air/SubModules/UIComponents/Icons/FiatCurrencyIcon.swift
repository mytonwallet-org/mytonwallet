import SwiftUI
import WalletCore
import WalletContext

public struct FiatCurrencyIcon: View {
    let currency: MBaseCurrency
    let size: CGFloat

    public init(currency: MBaseCurrency, size: CGFloat = 28) {
        self.currency = currency
        self.size = size
    }

    public var body: some View {
        Text(currency.sign)
            .font(.system(size: size * 20 / 28, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(LinearGradient(colors: [Color(red: 160/255, green: 222/255, blue: 126/255),
                                               Color(red: 84/255, green: 203/255, blue: 104/255)],
                                       startPoint: .top, endPoint: .bottom), in: .circle)
            .accessibilityHidden(true)
    }
}
