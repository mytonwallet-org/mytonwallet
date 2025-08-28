
import SwiftUI
import WalletContext

public struct WideSeparator: View {
    public init() {}
    
    public var body: some View {
        Rectangle()
            .fill(Color.air.menuWideSeparator)
            .frame(height: 8)
    }
}
