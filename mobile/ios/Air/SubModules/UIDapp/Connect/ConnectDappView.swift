//
//  ConnectDappVC.swift
//  UIDapp
//
//  Created by Sina on 8/13/24.
//

import SwiftUI
import UIKit
import UIPasscode
import UIComponents
import WalletCore
import WalletContext
import Ledger

enum ConnectDappViewOrPlaceholderContent {
    case placeholder(TonConnectPlaceholder)
    case connectDapp(ConnectDappView)
}

struct ConnectDappViewOrPlaceholder: View {
    
    var content: ConnectDappViewOrPlaceholderContent
    
    var body: some View {
        switch content {
        case .placeholder(let view):
            view
                .transition(.opacity.animation(.default))
        case .connectDapp(let view):
            view
                .transition(.opacity.animation(.default))
        }
    }
}

struct ConnectDappView: View {
    var body: some View {
        EmptyView()
    }
}
