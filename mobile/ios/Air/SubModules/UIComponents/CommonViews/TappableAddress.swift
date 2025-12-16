//
//  BaseCurrencyValueText.swift
//  MyTonWalletAir
//
//  Created by nikstar on 22.11.2024.
//

import SwiftUI
import WalletCore
import WalletContext


public struct TappableAddress: View {
    
    var name: String?
    var chain: String
    var resolvedAddress: String?
    var addressOrName: String

    @State private var menuContext = MenuContext()
    
    public init(name: String?, chain: String, resolvedAddress: String?, addressOrName: String) {
        self.name = name
        self.chain = chain
        self.resolvedAddress = resolvedAddress
        self.addressOrName = addressOrName
    }
    
    public var body: some View {
        
        let address = name ?? resolvedAddress ?? addressOrName
        let compact = (address != name && address.count > 13) || address.count > 25
        
        let addr = Text(
            formatAddressAttributed(
                address,
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
        .menuSource(menuContext: menuContext)
        .task {
            menuContext.makeConfig = makeTappableAddressMenu(displayName: name, chain: chain, address: resolvedAddress ?? addressOrName)
        }
    }
}


public struct TappableAddressFull: View {
    
    var chain: String
    var address: String
    
    @State private var menuContext = MenuContext()
    
    let openInBrowser: (URL) -> () = { url in
        AppActions.openInBrowser(url)
    }
    
    public init(chain: String, address: String) {
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
                menuContext.makeConfig = makeTappableAddressMenu(displayName: nil, chain: chain, address: address)
            }
    }
}
