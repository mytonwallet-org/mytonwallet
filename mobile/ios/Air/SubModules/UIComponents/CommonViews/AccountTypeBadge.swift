
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
        .foregroundStyle(foregroundStyle)
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
                switch style {
                case .card:
                    Color.primary.opacity(0.18)
                case .list:
                    Color(WTheme.secondaryLabel).opacity(0.12)
                }
                
            }
        }
        .clipShape(.rect(cornerRadius: 5))
    }
    
    var foregroundStyle: Color {
        switch style {
        case .card:
            Color.primary
        case .list:
            Color(WTheme.secondaryLabel)
        }
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
