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
    var resolvedAddress: String?
    var addressOrName: String
    var openInBrowser: (URL) -> () = { url in
        AppActions.openInBrowser(url)
    }
    
    public init(name: String?, resolvedAddress: String?, addressOrName: String) {
        self.name = name
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

        Menu {
            AddressActions(address: resolvedAddress ?? addressOrName, showSaveToFavorites: true)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                addr
                more
            }
        }
    }
}


public struct TappableAddressFull: View {
    
    var address: String
    let openInBrowser: (URL) -> () = { url in
        AppActions.openInBrowser(url)
    }
    
    public init(address: String) {
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
            .overlay {
                Menu {
                    AddressActions(address: address, showSaveToFavorites: true)
                } label: {
                    Color.clear.contentShape(.rect)
                }
            }
    }
}
