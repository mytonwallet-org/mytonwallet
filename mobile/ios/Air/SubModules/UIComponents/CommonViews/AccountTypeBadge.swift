
import SwiftUI
import WalletCore
import WalletContext


public struct AccountTypeBadge: View {
    
    var accountType: AccountType
    
    public init(_ accountType: AccountType) {
        self.accountType = accountType
    }
    
    public var body: some View {
        switch accountType {
        case .mnemonic:
            mnemonic
        case .hardware:
            hardware
        case .view:
            view
        }
    }
    
    var mnemonic: some View {
        EmptyView()
    }
    
    var hardware: some View {
        Image.airBundle("LedgerBadge")
            .opacity(0.75)
    }
    
    var view: some View {
        HStack(spacing: 2) {
            Image.airBundle("ViewBadge")
                .offset(y: 0.667)
            Text(lang("$view_mode"))
                .font(.system(size: 12, weight: .semibold))
        }
        .offset(y: -0.333)
        .opacity(0.75)
        .padding(.horizontal, 3)
        .frame(height: 18)
        .background {
            ZStack {
                BackgroundBlur(radius: 16)
                Color.white.opacity(0.18)
            }
        }
        .clipShape(.rect(cornerRadius: 5))
    }
}


#Preview {
    ZStack {
        HStack(spacing: 0) {
            Color.blue
            Color.blue.opacity(0.5)
        }
        
        VStack {
            AccountTypeBadge(.mnemonic)
            AccountTypeBadge(.hardware)
            AccountTypeBadge(.view)
        }
        .foregroundStyle(.white)
        .scaleEffect(4)
        .padding()
    }
}
