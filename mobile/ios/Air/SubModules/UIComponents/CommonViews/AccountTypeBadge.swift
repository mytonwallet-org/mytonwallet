
import SwiftUI
import WalletCore
import WalletContext


public struct AccountTypeBadge: View {
    
    var accountType: AccountType
    public enum Style {
        case card
        case list
    }
    var style: Style
    
    public init(_ accountType: AccountType, style: Style) {
        self.accountType = accountType
        self.style = style
    }
    
    public var body: some View {
        HStack {
            switch accountType {
            case .mnemonic:
                mnemonic
            case .hardware:
                hardware
            case .view:
                view
            }
        }
    }
    
    var mnemonic: some View {
        EmptyView()
    }
    
    var hardware: some View {
        Image.airBundle("LedgerBadge")
            .opacity(0.75)
    }
    
    @ViewBuilder
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
            Rectangle()
                .opacity(0.18)
        }
        .clipShape(.rect(cornerRadius: 5))
        .padding(.vertical, -3)
    }
}


#Preview {
    ZStack {
        HStack(spacing: 0) {
            Color.blue
            Color.blue.opacity(0.5)
        }
        
        VStack {
            AccountTypeBadge(.mnemonic, style: .card)
            AccountTypeBadge(.hardware, style: .card)
            AccountTypeBadge(.view, style: .card)
        }
        .foregroundStyle(.white)
        .scaleEffect(4)
        .padding()
    }
}
