//
//  BaseCurrencyValueText.swift
//  MyTonWalletAir
//
//  Created by nikstar on 22.11.2024.
//

import SwiftUI
import WalletCore
import WalletContext


public struct AddressActions: View {
    
    var address: String
    var showSaveToFavorites: Bool
    
    public init(address: String, showSaveToFavorites: Bool) {
        self.address = address
        self.showSaveToFavorites = showSaveToFavorites
    }
    
    public var body: some View {
        Button(action: onCopy) {
            Label {
                Text(lang("Copy"))
            } icon: {
                Image("SendCopy", bundle: AirBundle)
            }
        }
        Button(action: onOpenExplorer) {
            Label {
                Text(lang("Open in Explorer"))
            } icon: {
                Image("SendGlobe", bundle: AirBundle)
            }
        }
//        if showSaveToFavorites" {
//            Button(action: onSaveToFavorites) {
//                Label {
//                    Text(lang("Save to Favorites"))
//                } icon: {
//                    Image("SendFavorites", bundle: AirBundle)
//                }
//            }
//        }"
    }
    
    func onCopy() {
        UIPasteboard.general.string = address
        topWViewController()?.showToast(animationName: "Copy", message: lang("Address was copied!"))
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }
    
    func onOpenExplorer() {
        let chain = availableChains.first(where: { $0.validate(address: address) }) ?? ApiChain.ton
        let url = ExplorerHelper.addressUrl(chain: chain, address: address)
        AppActions.openInBrowser(url)
    }
    
    func onSaveToFavorites() {
        topWViewController()?.showToast(message: "Not implemented")
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}
