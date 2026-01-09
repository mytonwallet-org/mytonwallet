import SwiftUI
import WalletCore
import WalletContext
import Perception

public struct TappableAddress: View {
    
    var account: AccountContext
    var knownName: String?
    var chain: String
    var addressOrName: String

    @State private var menuContext = MenuContext()
    
    public init(account: AccountContext, name: String?, chain: String, addressOrName: String) {
        self.account = account
        self.knownName = name
        self.chain = chain
        self.addressOrName = addressOrName
    }
    
    public var body: some View {
        WithPerceptionTracking {
            let displayName = self.displayName
            let compact = (displayName != knownName && displayName.count > 20) || displayName.count > 25
            
            let addr = Text(
                formatAddressAttributed(
                    displayName,
                    startEnd: compact,
                    primaryColor: WTheme.secondaryLabel
                )
            )
            let more: Text = Text(
                Image(systemName: "chevron.down")
            )
                .font(.system(size: 14))
                .foregroundColor(Color(WTheme.secondaryLabel))

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                addr
                more
            }
            .imageScale(.small)
            .menuSource(menuContext: menuContext)
            .task {
                menuContext.makeConfig = makeTappableAddressMenu(accountContext: account, displayName: knownName, chain: chain, address: addressOrName)
            }
        }
    }
    
    var displayName: String {
        if let chain = ApiChain(rawValue: chain), let name = account.getLocalName(chain: chain, address: addressOrName) {
            return name
        }
        return knownName ?? addressOrName
    }
}


public struct TappableAddressFull: View {
    
    var accountContext: AccountContext
    var chain: String
    var address: String
    
    @State private var menuContext = MenuContext()
    
    let openInBrowser: (URL) -> () = { url in
        AppActions.openInBrowser(url)
    }
    
    public init(accountContext: AccountContext, chain: String, address: String) {
        self.accountContext = accountContext
        self.chain = chain
        self.address = address
    }
    
    public var body: some View {
        
        let addr = Text(
            formatAddressAttributed(
                address,
                startEnd: false
            )
        )
        let more: Text = Text(
            Image(systemName: "chevron.down")
        )
            .font(.system(size: 14))
            .foregroundColor(Color(WTheme.secondaryLabel))

        
        Text("\(addr) \(more)")
            .lineLimit(nil)
            .multilineTextAlignment(.leading)
            .menuSource(menuContext: menuContext)
            .task {
                menuContext.makeConfig = makeTappableAddressMenu(accountContext: accountContext, displayName: nil, chain: chain, address: address)
            }
    }
}
