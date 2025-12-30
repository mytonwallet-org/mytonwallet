
import SwiftUI
import WalletCore
import WalletContext

let viewBadgeCornerRadius: CGFloat = 5
let viewBadgeVerticalPadding: CGFloat = 3

public struct AccountTypeBadge: View {
    
    var accountType: AccountType
    var increasedOpacity: Bool
    
    public init(_ accountType: AccountType, increasedOpacity: Bool = false) {
        self.accountType = accountType
        self.increasedOpacity = increasedOpacity
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
            .opacity(increasedOpacity ? 1 : 0.75)
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
        .opacity(increasedOpacity ? 1 : 0.75)
        .padding(.horizontal, 3)
        .frame(height: 18)
        .background {
            Rectangle()
                .opacity(0.12)
        }
        .clipShape(.rect(cornerRadius: viewBadgeCornerRadius))
        .padding(.vertical, -viewBadgeVerticalPadding)
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
