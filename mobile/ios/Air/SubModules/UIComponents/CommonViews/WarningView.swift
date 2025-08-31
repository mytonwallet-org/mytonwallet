
import SwiftUI
import WalletContext


public struct WarningView: View {
    
    public var text: String
    public var color: Color
    
    public init(text: String, color: Color = Color(WTheme.error)) {
        self.text = text
        self.color = color
    }
    
    public var body: some View {
        Text(LocalizedStringKey(text))
            .multilineTextAlignment(.leading)
            .foregroundStyle(color)
            .font13()
//            .font14h18()
            .padding(.bottom, 2)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(color)
                    .frame(width: 4)
            }
            .background(color.opacity(0.1))
            .clipShape(.rect(cornerRadius: 10))
    }
}
