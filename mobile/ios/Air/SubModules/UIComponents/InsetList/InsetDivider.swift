
import SwiftUI
import WalletContext


public struct InsetDivider: View {
    
    public init() {}

    public var body: some View {
        Rectangle()
            .fill(Color(WTheme.separator))
            .frame(height: 0.33)
            .padding(.leading, 16)
            .padding(.trailing, -16)
    }
}
