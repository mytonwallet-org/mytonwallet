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
import Perception

struct SendingHeaderView: View {
    
    let model: SendModel
    
    var body: some View {
        WithPerceptionTracking {
            let text = lang("Send to") + " "
            if model.nfts.count > 0 {
                NftOverviewView(
                    nfts: model.nfts,
                    isOutgoing: true,
                    text: text,
                    addressViewModel: model.addressViewModel
                )
            } else {
                TransactionOverviewView(
                    amount: model.amount ?? 0,
                    token: model.token,
                    isOutgoing: true,
                    text: text,
                    addressViewModel: model.addressViewModel
                )
            }
        }
    }
}
