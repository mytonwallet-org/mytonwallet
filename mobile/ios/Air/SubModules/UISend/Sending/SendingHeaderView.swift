//
//  SendingHeaderView.swift
//  MyTonWalletAir
//
//  Created by nikstar on 27.11.2024.
//

import Foundation
import SwiftUI
import UIKit
import UIComponents
import WalletCore
import WalletContext

struct SendingHeaderView: View {
    
    @EnvironmentObject private var model: SendModel
    
    var body: some View {
        let text = lang("Send to") + " "
        if let nft = model.nfts?.first {
            NftOverviewView(
                nft: nft,
                isOutgoing: true,
                text: text,
                addressName: model.toAddressDraft?.addressName,
                resolvedAddress: model.toAddressDraft?.resolvedAddress,
                addressOrDomain: model.addressOrDomain
            )
        } else {
            TransactionOverviewView(
                amount: model.amount ?? 0,
                token: model.token!,
                isOutgoing: true,
                text: text,
                addressName: model.toAddressDraft?.addressName,
                resolvedAddress: model.toAddressDraft?.resolvedAddress,
                addressOrDomain: model.addressOrDomain
            )
        }
    }
}
